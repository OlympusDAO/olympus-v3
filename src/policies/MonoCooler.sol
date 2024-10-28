// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";

import {IStaking} from "interfaces/IStaking.sol";

import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {CHREGv1} from "modules/CHREG/CHREG.v1.sol";
import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";

import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";
import {DelegateEscrow} from "src/external/cooler/DelegateEscrow.sol";
import {SafeCast} from "libraries/SafeCast.sol";
import {CompoundedInterest} from "libraries/CompoundedInterest.sol";

/*
@todo considerations:

- Olympus modules/policies/permissions need reviewing closely as i'm not too familiar with best practice, just blindly pasta'd
- Interest accrual is based on a global 'accumulator', and then each account has their own accumulator which is checkpoint whenever they do an action.
  Used in Temple Line of Credit, and was based on other mono-contract money markets.
- Uses a 'memory' cache to pre-load this info so we're not reading from 'storage' variables all the time (gas saving)
- Did a little gas golfing to pack storage variables - slight tradeoff for readability (eg safely encode uint256 => uint128). But worth it imo.
- Funding of DAI/USDS debt is done 'just in time'. Will need an opinion on whether this is OK or if too gassy and we need to have a debt buffer or use 
  the same Clearinghouse max weekly funding model.

- Discussed adding a circuit breaker (like Temple's TLC) - sounds like we should?
 */

contract MonoCooler is IMonoCooler, Policy, RolesConsumer {
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;
    using CompoundedInterest for uint256;
    using SafeTransferLib for ERC20;
    using SafeTransferLib for ERC4626;
    using EnumerableSet for EnumerableSet.AddressSet;

    // --- IMMUTABLES -----------------------------------------------

    /// @notice The collateral token supplied by users/accounts, eg gOHM
    ERC20 public immutable override collateralToken;

    /// @notice The debt token which can be borrowed, eg DAI or USDS
    ERC20 public immutable override debtToken;

    /// @notice Unwrapped gOHM
    ERC20 public immutable ohm;

    // Necessary to unstake (and burn) OHM from liquidations
    IStaking public immutable staking;

    /// @notice The ERC2626 reserve asset which is pulled from treasury, eg sDAI
    /// @dev The asset of this vault must be `debtToken`
    ERC4626 public immutable debtSavingsVault;

    /**
     * @notice The minimum debt a user needs to maintain
     * @dev It costs gas to liquidate users, so we don't want dust amounts.
     */
    uint256 public immutable override minDebtRequired;

    // --- MODULES --------------------------------------------------

    CHREGv1 public CHREG; // Olympus V3 Clearinghouse Registry Module
    MINTRv1 public MINTR; // Olympus V3 Minter Module
    TRSRYv1 public TRSRY; // Olympus V3 Treasury Module

//-- begin slot 5

    /// @notice The total amount of collateral posted across all accounts.
    uint128 public override totalCollateral;

    /// @notice The total amount of debt which has been borrowed across all users 
    /// as of the latest checkpoint
    uint128 public override totalDebt;

//--- begin slot 6
    /// @notice Liquidations may be paused in order for users to recover/repay debt after 
    /// emergency actions or interest rate changes
    bool public override liquidationsPaused;

    /// @notice Borrows may be paused for emergency actions or deprecating the facility
    bool public override borrowsPaused;

    /// @notice The flat interest rate, defined in basis points.
    /// @dev Interest (approximately) continuously compounds at this rate.
    uint16 public override interestRateBps;

    /// @notice The Loan To Value point at which an account can be liquidated
    /// @dev Defined in terms of [debtToken/collateralToken] -- eg [USDS/gOHM]
    uint96 public override liquidationLtv;

    /// @notice The maximum Loan To Value an account is allowed when borrowing or withdrawing collateral
    /// @dev Defined in terms of [debtToken/collateralToken] -- eg [USDS/gOHM]
    uint96 public override maxOriginationLtv;

    /// @notice The last time the global debt accumulator was updated
    uint32 public override interestAccumulatorUpdatedAt;

//--- begin slot 7

    /// @notice The accumulator index used to track the compounding of debt, starting at 1e27 at genesis
    /// @dev To RAY (1e27) precision
    uint256 public override interestAccumulatorRay;

//-- begin slot 8
    /// @dev A per account store, tracking collateral/debt as of their latest checkpoint.
    mapping(address /* account */ => AccountState) private allAccountState;

//-- begin slot 9

    mapping(address /*delegate*/ => DelegateEscrow /*delegateEscrow*/) private delegateEscrows;

//-- begin slot 10
    /// @dev The delegate addresses and total collateral delegated for a given account
    struct AccountDelegations {
        /// @dev A regular account is allowed to delegate up to 10 different addresses.
        /// The account may be whitelisted to delegate more than that.
        EnumerableSet.AddressSet delegateAddresses;

        /// @dev The total collateral delegated for this user across all delegates
        uint128 totalDelegated;

        /// @dev By default an account can only delegate to 10 addresses.
        /// This may be increased on a per account basis by governance.
        uint128 maxDelegateAddresses;
    }

    /// @dev Mapping an account to their A given account is allowed up to 10 delegates
    // It's capped because upon liquidation this gOHM needs to be unstaked and burned.
    // needs to be private for the EnumerableSet
    mapping(address /*account*/ => AccountDelegations /*delegations*/) private _accountDelegations;

    // --- CONSTANTS ------------------------------------------------

    bytes32 public constant COOLER_OVERSEER_ROLE = bytes32("cooler_overseer");

    /// @dev The default maximum number of addresses an account can delegate to
    uint128 public override constant DEFAULT_MAX_DELEGATE_ADDRESSES = 10;

    /// @notice Extra precision scalar
    uint256 private constant RAY = 1e27;

    uint96 private constant ONE_YEAR = 365 days;

    // --- INITIALIZATION -------------------------------------------

    constructor(
        address ohm_,
        address gohm_,
        address staking_,
        address debtSavingsVault_,
        address kernel_,
        uint96 liquidationLtv_,
        uint96 maxOriginationLtv_,
        uint16 interestRateBps_,
        uint256 minDebtRequired_
    ) Policy(Kernel(kernel_)) {
        ohm = ERC20(ohm_);
        collateralToken = ERC20(gohm_);
        staking = IStaking(staking_);
        debtSavingsVault = ERC4626(debtSavingsVault_);
        debtToken = ERC20(debtSavingsVault.asset());
        minDebtRequired = minDebtRequired_;

        // This contract only handles 18dp
        if (collateralToken.decimals() != 18) revert InvalidParam();
        if (debtToken.decimals() != 18) revert InvalidParam();

        liquidationLtv = liquidationLtv_;
        maxOriginationLtv = maxOriginationLtv_;
        interestRateBps = interestRateBps_;

        interestAccumulatorUpdatedAt = uint32(block.timestamp);
        interestAccumulatorRay = RAY;
    }

    /// @notice Default framework setup. Configure dependencies for olympus-v3 modules.
    /// @dev    This function will be called when the `executor` installs the Clearinghouse
    ///         policy in the olympus-v3 `Kernel`.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("CHREG");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("TRSRY");

        CHREG = CHREGv1(getModuleAddress(toKeycode("CHREG")));
        MINTR = MINTRv1(getModuleAddress(toKeycode("MINTR")));
        ROLES = ROLESv1(getModuleAddress(toKeycode("ROLES")));
        TRSRY = TRSRYv1(getModuleAddress(toKeycode("TRSRY")));

        (uint8 CHREG_MAJOR, ) = CHREG.VERSION();
        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1, 1]);
        if (CHREG_MAJOR != 1 || MINTR_MAJOR != 1 || ROLES_MAJOR != 1 || TRSRY_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Approve MINTR for burning OHM (called here so that it is re-approved on updates)
        ohm.approve(address(MINTR), type(uint256).max);
    }

    /// @notice Default framework setup. Request permissions for interacting with olympus-v3 modules.
    /// @dev    This function will be called when the `executor` installs the Clearinghouse
    ///         policy in the olympus-v3 `Kernel`.
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode CHREG_KEYCODE = toKeycode("CHREG");
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");

        requests = new Permissions[](6);
        requests[0] = Permissions(CHREG_KEYCODE, CHREG.activateClearinghouse.selector);
        requests[1] = Permissions(CHREG_KEYCODE, CHREG.deactivateClearinghouse.selector);
        requests[2] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        requests[3] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        requests[4] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        requests[5] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
    }

    // --- COLLATERAL -----------------------------------------------

    /**
     * @notice Deposit gOHM as collateral
     * @param collateralAmount The amount to deposit
     *    - MUST be greater than zero
     * @param onBehalfOf An account can add collateral on behalf of themselves or another address.
     *    - MUST NOT be address(0)
     * @param delegationRequests The set of delegations to apply after adding collateral.
     *    - MAY be empty, meaning no delegations are applied.
     *    - Total collateral delegated as part of these requests MUST BE less than the account collateral.
     *    - MUST NOT apply delegations that results in more collateral being undelegated than
     *      the account has collateral for.
     *    - MUST be empty if `onBehalfOf` does not equal msg.sender - ie calling on behalf of another address.
     */
    function addCollateral(
        uint128 collateralAmount,
        address onBehalfOf,
        DelegationRequest[] calldata delegationRequests
    ) external override {
        if (collateralAmount == 0) revert ExpectedNonZero();
        if (onBehalfOf == address(0)) revert InvalidParam();

        // While adding collateral on another user's behalf is ok,
        // Delegating on behalf of someone else is not allowed.
        if (onBehalfOf != msg.sender && delegationRequests.length > 0) revert InvalidParam();

        collateralToken.safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount 
        );

        AccountState storage aState = allAccountState[onBehalfOf];
        uint128 newAccountCollateral = aState.collateral + collateralAmount;
        aState.collateral = newAccountCollateral;
        totalCollateral += collateralAmount;

        // Apply the delegation requests to the newly added collateral
        _applyDelegations(onBehalfOf, newAccountCollateral, delegationRequests, false);

        // NB: No need to check if the position is healthy when adding collateral as this
        // only improves the liquidity.
        emit CollateralAdded(msg.sender, onBehalfOf, collateralAmount);
    }

    /**
     * @notice Withdraw gOHM collateral.
     *    - Account LTV MUST be less than or equal to `maxOriginationLtv` after the withdraw is applied
     *    - At least `collateralAmount` collateral MUST be undelegated for this account.
     *      Use the `delegationRequests` to rescind enough as part of this request.
     * @param collateralAmount The amount of collateral to remove
     *    - MUST be greater than zero
     * @param recipient Send the gOHM collateral to a specified recipient address.
     *    - MUST NOT be address(0)
     * @param delegationRequests The set of delegations to apply before removing collateral.
     *    - MAY be empty, meaning no delegations are applied.
     *    - Total collateral delegated as part of these requests MUST BE less than the account collateral.
     *    - MUST NOT apply delegations that results in more collateral being undelegated than
     *      the account has collateral for.
     */
    function withdrawCollateral(
        uint128 collateralAmount,
        address recipient,
        DelegationRequest[] calldata delegationRequests
    ) external override {
        if (collateralAmount == 0) revert ExpectedNonZero();
        if (recipient == address(0)) revert InvalidParam();

        AccountState storage aState = allAccountState[msg.sender];
        uint128 existingCollateral =  aState.collateral;

        // Apply the delegation requests in order to pull the required collateral
        // back into this contract.
        // The account must have at least `collateralAmount` undelegated afer applying these requests.
        uint128 totalDelegated = _applyDelegations(msg.sender, existingCollateral, delegationRequests, false);
        if (existingCollateral - totalDelegated < collateralAmount) {
            revert ExceededUndelegatedCollateralBalance(existingCollateral, collateralAmount);
        }

        // Update the collateral balance, and then verify that it doesn't make the debt unsafe.
        aState.collateral = existingCollateral - collateralAmount;
        totalCollateral -= collateralAmount;

        // Verify the account LTV given the reduction in collateral
        _validateOriginationLtv(aState, _globalStateRO());

        // Finally transfer the collateral to the recipient
        collateralToken.safeTransfer(
            recipient,
            collateralAmount
        );
        emit CollateralRemoved(msg.sender, recipient, collateralAmount);
    }

    // --- BORROW/REPAY ---------------------------------------------

    /**
     * @notice Borrow `debtToken`
     *    - Account LTV MUST be less than or equal to `maxOriginationLtv` after the borrow is applied
     *    - Total debt for this account MUST be greater than or equal to the `minDebtRequired`
     *      after the borrow is applied
     * @param borrowAmount The amount of `debtToken` to borrow
     *    - MUST be greater than zero
     * @param recipient Send the borrowed token to a specified recipient address.
     *    - MUST NOT be address(0)
     */
    function borrow(uint128 borrowAmount, address recipient) external override {
        if (borrowsPaused) revert Paused();
        if (borrowAmount == 0) revert ExpectedNonZero();
        if (recipient == address(0)) revert InvalidParam();

        AccountState storage aState = allAccountState[msg.sender];
        GlobalStateCache memory gState = _globalStateRW();

        // Apply the new borrow
        uint128 accountTotalDebt = _currentAccountDebt(
            gState,
            aState.debtCheckpoint,
            aState.interestAccumulatorRay,
            false // don't round up on the way in
        ) + borrowAmount;

        if (accountTotalDebt < minDebtRequired) revert MinDebtNotMet(minDebtRequired, accountTotalDebt);

        // Update the state
        aState.debtCheckpoint = accountTotalDebt;
        aState.interestAccumulatorRay = gState.interestAccumulatorRay;
        totalDebt = gState.totalDebt = gState.totalDebt + borrowAmount;

        emit Borrow(msg.sender, recipient, borrowAmount);

        _validateOriginationLtv(aState, gState);

        // Finally, borrow the funds from the Treasury and send the tokens to the recipient.
        _fundFromTreasury(borrowAmount, recipient);
    }

    /**
     * @notice Repay a portion, or all of the debt
     *    - MUST NOT be called for an account which has no debt
     *    - If the entire debt isn't paid off, then the total debt for this account 
     *      MUST be greater than or equal to the `minDebtRequired` after the borrow is applied
     * @param repayAmount The amount to repay. Capped to the current debt as of this block.
     *    - MUST be greater than zero
     *    - MAY be greater than the latest debt as of this block. In which case the 
     *      debt will be fully paid off.
     * @param onBehalfOf Another address can repay the debt on behalf of someone else
     */
    function repay(uint128 repayAmount, address onBehalfOf) external override {
        if (repayAmount == 0) revert ExpectedNonZero();

        AccountState storage aState = allAccountState[onBehalfOf];
        GlobalStateCache memory gState = _globalStateRW();

        // Update the account's latest debt
        uint128 latestDebt = _currentAccountDebt(
            gState, 
            aState.debtCheckpoint,
            aState.interestAccumulatorRay,
            true // round up for repay balance
        );
        if (latestDebt == 0) revert InvalidParam();

        // Cap the amount to be repaid to the current debt as of this block
        if (repayAmount > latestDebt) {
            repayAmount = latestDebt;
            aState.debtCheckpoint = 0;
        } else {
            // Ensure the minimum debt amounts are still maintained
            aState.debtCheckpoint = latestDebt - repayAmount;
            if (aState.debtCheckpoint < minDebtRequired) revert MinDebtNotMet(minDebtRequired, aState.debtCheckpoint);
        }
      
        aState.interestAccumulatorRay = gState.interestAccumulatorRay;

        _reduceTotalDebt(gState, repayAmount);

        emit Repay(msg.sender, onBehalfOf, repayAmount);
        // NB: Liquidity doesn't need to be checked after a repay, as that only improves the health.

        _repayTreasury(repayAmount, msg.sender);
    }

    // --- GOV. DELEGATION ------------------------------------------

    function applyDelegations(
        DelegationRequest[] calldata delegationRequests
    ) external override returns (
        uint256 /*totalDelegated*/
    ) {
        return _applyDelegations(msg.sender, allAccountState[msg.sender].collateral, delegationRequests, false);
    }

    // --- LIQUIDATIONS ---------------------------------------------

    // @todo incentivise liquidations

    /**
     * @notice Liquidate one or more accounts which have exceeded the `liquidationLtv`
     * The gOHM collateral is seized (unstaked to OHM and burned), and the accounts debt is wiped.
     * @dev If one of the provided accounts in the batch hasn't exceeded the max LTV then it is skipped.
     */
    function batchLiquidate(
        address[] calldata accounts
    ) external override returns (
        uint128 totalCollateralClaimed,
        uint128 totalDebtWiped
    ) {
        if (liquidationsPaused) revert Paused();

        LiquidationStatus memory status;
        GlobalStateCache memory gState = _globalStateRW();
        address account;
        uint256 numAccounts = accounts.length;
        for (uint256 i; i < numAccounts; ++i) {
            account = accounts[i];
            status = _computeLiquidity(
                allAccountState[account],
                gState
            );

            // Skip if this account is still under the maxLTV
            if (status.exceededLiquidationLtv) {
                emit Liquidated(account, status.collateral, status.currentDebt);
                totalCollateralClaimed += status.collateral;
                totalDebtWiped += status.currentDebt;

                // Clear the account data
                delete allAccountState[account];
            }
        }

        // burn the gOHM collateral by repaying to TRV. This will burn the equivalent dgOHM debt too.
        if (totalCollateralClaimed > 0) {
            // Unstake and burn gOHM holdings.
            collateralToken.safeApprove(address(staking), totalCollateralClaimed);
            MINTR.burnOhm(address(this), staking.unstake(address(this), totalCollateralClaimed, false, false));

            totalCollateral -= totalCollateralClaimed;
        }

        // Remove debt from the totals
        if (totalDebtWiped > 0) {
            _reduceTotalDebt(gState, totalDebtWiped);
        }
    }

    /**
     * @notice If an account becomes unhealthy and has many delegations such that liquidation can't be
     * performed in one transaction due to gas limits, then delegations can be rescinded over multiple
     * transactions in order to get this account into a state where it can then be liquidated.
     */
    function applyUnhealthyDelegations(
        address account,
        DelegationRequest[] calldata delegationRequests
    ) external override returns (
        uint256 /*totalDelegated*/
    ) {
        if (liquidationsPaused) revert Paused();
        GlobalStateCache memory gState = _globalStateRW();
        LiquidationStatus memory status = _computeLiquidity(
            allAccountState[account],
            gState
        );
        if (!status.exceededLiquidationLtv) revert CannotLiquidate();
        return _applyDelegations(account, allAccountState[account].collateral, delegationRequests, true);
    }

    // --- ADMIN ----------------------------------------------------

    /**
     * @notice Set the Loan To Value's for both the `liquidationLtv` and `maxOriginationLtv`
     * @param newLiquidationLtv The Loan To Value point at which an account can be liquidated
     *    - Defined in terms of [debtToken/collateralToken] -- eg [USDS/gOHM]
     *    - MUST NOT decrease compared to the existing `liquidationLtv`
     * @param newMaxOriginationLtv The maximum Loan To Value an account is allowed to have when
     *      borrowing or withdrawing collateral
     *    - Defined in terms of [debtToken/collateralToken] -- eg [USDS/gOHM]
     *    - MUST be greater than the `newLiquidationLtv`
     */
    function setLoanToValue(
        uint96 newLiquidationLtv,
        uint96 newMaxOriginationLtv
    ) external override onlyRole(COOLER_OVERSEER_ROLE) {
        uint256 currentLiquidationLtv = liquidationLtv;
        if (newLiquidationLtv != currentLiquidationLtv) {
            // Not allowed to decrease
            if (newLiquidationLtv < currentLiquidationLtv) revert InvalidParam();
            emit LiquidationLtvSet(newLiquidationLtv);
            liquidationLtv = newLiquidationLtv;
        }

        uint256 currentMaxOriginationLtv = maxOriginationLtv;
        if (newMaxOriginationLtv != currentMaxOriginationLtv) {
            // Must be less than the liquidationLtv
            if (newMaxOriginationLtv >= newLiquidationLtv) revert InvalidParam();
            emit MaxOriginationLtvSet(newMaxOriginationLtv);
            maxOriginationLtv = newMaxOriginationLtv;
        }
    }

    /**
     * @notice Liquidation may be paused in order for users to recover/repay debt after emergency
     * actions
     */
    function setLiquidationsPaused(bool isPaused) external override onlyRole(COOLER_OVERSEER_ROLE) {
        liquidationsPaused = isPaused;
        emit LiquidationsPausedSet(isPaused);
    }

    /**
     * @notice Pause any new borrows of `debtToken`
     */
    function setBorrowPaused(bool isPaused) external override onlyRole(COOLER_OVERSEER_ROLE) {
        emit BorrowPausedSet(isPaused);
        borrowsPaused = isPaused;
    }

    /**
     * @notice Update the interest rate, specified in basis points.
     */
    function setInterestRateBps(uint16 newInterestRateBps) external override onlyRole(COOLER_OVERSEER_ROLE) {
        // Force an update of state on the old rate first.
        _globalStateRW();

        emit InterestRateSet(newInterestRateBps);
        interestRateBps = newInterestRateBps;
    }

    /**
     * @notice Allow an account to have more or less than the DEFAULT_MAX_DELEGATE_ADDRESSES 
     * number of delegates.
     */
    function setMaxDelegateAddresses(
        address account, 
        uint128 maxDelegateAddresses
    ) external override onlyRole(COOLER_OVERSEER_ROLE) {
        emit MaxDelegateAddressesSet(account, maxDelegateAddresses);
        _accountDelegations[account].maxDelegateAddresses = maxDelegateAddresses;
    }

    // --- AUX FUNCTIONS --------------------------------------------

    /**
     * @notice An view of an accounts current and up to date position as of this block
     * @param account The account to get a position for
     */
    function accountPosition(
        address account
    ) external override view returns (
        AccountPosition memory position
    ) {
        AccountState storage aState = allAccountState[account];
        GlobalStateCache memory gState = _globalStateRO();

        LiquidationStatus memory status = _computeLiquidity(aState, gState);

        position.collateral = status.collateral;
        position.currentDebt = status.currentDebt;
        position.currentLtv = status.currentLtv;

        // maxOriginationLtv [USDS/gOHM] * collateral [gOHM]
        // Round down to get the conservative max debt allowed
        position.maxDebt = uint256(maxOriginationLtv)
            .mulWadDown(position.collateral)
            .encodeUInt128();

        // healthFactor = liquidationLtv [USDS/gOHM] * collateral [gOHM] / debt [USDS]
        position.healthFactor = position.currentDebt == 0
            ? type(uint256).max
            : uint256(liquidationLtv).mulDivDown(
                position.collateral,
                position.currentDebt
            );
        
        AccountDelegations storage delegations = _accountDelegations[account];
        position.totalDelegated = delegations.totalDelegated;
        position.numDelegateAddresses = delegations.delegateAddresses.length();
        position.maxDelegateAddresses = delegations.maxDelegateAddresses;
    }

    /**
     * @notice Compute the liquidity status for a set of accounts.
     * @dev This can be used to verify if accounts can be liquidated or not.
     * @param accounts The accounts to get the status for.
     */
    function computeLiquidity(
        address[] calldata accounts
    ) external override view returns (LiquidationStatus[] memory status) {
        uint256 numAccounts = accounts.length;
        status = new LiquidationStatus[](numAccounts);
        GlobalStateCache memory gState = _globalStateRO();
        for (uint256 i; i < numAccounts; ++i) {
            status[i] = _computeLiquidity(
                allAccountState[accounts[i]], 
                gState
            );
        }
    }

    /**
     * @notice Paginated view of an account's delegations
     * @dev Can call sequentially increasing the `startIndex` each time by the number of items returned in the previous call,
     * until number of items returned is less than `maxItems`
     */
    function accountDelegations(
        address account, 
        uint256 startIndex, 
        uint256 maxItems
    ) external override view returns (
        AccountDelegation[] memory delegations
    ) {
        AccountDelegations storage acctDelegations = _accountDelegations[account];
        EnumerableSet.AddressSet storage acctDelegateAddresses = acctDelegations.delegateAddresses;
        
        // No items if either maxItems is zero or there are no delegate addresses.
        if (maxItems == 0) return new AccountDelegation[](0);
        uint256 length = acctDelegateAddresses.length();
        if (length == 0) return new AccountDelegation[](0);

        // No items if startIndex is greater than the max array index
        if (startIndex >= length) return new AccountDelegation[](0);

        // end index is the max of the requested items or the length
        uint256 requestedEndIndex = startIndex + maxItems - 1;
        uint256 maxPossibleEndIndex = length - startIndex - 1;
        if (maxPossibleEndIndex < requestedEndIndex) requestedEndIndex = maxPossibleEndIndex;

        delegations = new AccountDelegation[](requestedEndIndex-startIndex+1);
        DelegateEscrow escrow;
        AccountDelegation memory delegateInfo;
        for (uint256 i = startIndex; i <= requestedEndIndex; ++i) {
            delegateInfo = delegations[i];
            delegateInfo.delegate = acctDelegateAddresses.at(i);
            escrow = delegateEscrows[delegateInfo.delegate];
            delegateInfo.delegateEscrow = address(escrow);
            delegateInfo.delegationAmount = escrow.delegations(address(this), account);
        }
    }

    /**
     * @notice A view of the last checkpoint of account data (not as of this block)
     */
    function accountState(address account) external override view returns (AccountState memory) {
        return allAccountState[account];
    }
    
    /**
     * @notice A view of the derived/internal cache data.
     */
    function globalState() external view returns (uint128 /*totalDebt*/, uint256 /*interestAccumulatorRay*/) {
        GlobalStateCache memory gState = _globalStateRO();
        return (gState.totalDebt, gState.interestAccumulatorRay);
    }

    // --- INTERNAL STATE CACHE -------------------------------------

    struct GlobalStateCache {
        /**
         * @notice The total amount that has already been borrowed by all accounts.
         * This increases as interest accrues or new borrows. 
         * Decreases on repays or liquidations.
         */
        uint128 totalDebt;

        /**
         * @notice Internal tracking of the accumulated interest as an index starting from 1.0e27
         * When this accumulator is compunded by the interest rate, the total debt can be calculated as
         * `updatedTotalDebt = prevTotalDebt * latestInterestAccumulator / prevInterestAccumulator
         */
        uint256 interestAccumulatorRay;
    }

    /**
     * @dev Setup and refresh the global state
     * Update storage if and only if the timestamp has changed since last updated.
     */
    function _globalStateRW() private returns (
        GlobalStateCache memory gState
    ) {
        if (_initGlobalStateCache(gState)) {
            interestAccumulatorUpdatedAt = uint32(block.timestamp);
            totalDebt = gState.totalDebt;
            interestAccumulatorRay = gState.interestAccumulatorRay;
        }
    }

    /**
     * @dev Setup the GlobalStateCache for a given token
     * read only -- storage isn't updated.
     */
    function _globalStateRO() private view returns (
        GlobalStateCache memory gState
    ) {
        _initGlobalStateCache(gState);
    }

    /**
     * @dev Initialize the global state cache from storage to this block, for a given token.
     */
    function _initGlobalStateCache(GlobalStateCache memory gState) private view returns (bool dirty) {
        // Copies from storage (once)
        gState.interestAccumulatorRay = interestAccumulatorRay;
        gState.totalDebt = totalDebt;

        // Convert annual IR [basis points] into WAD per second, assuming 365 days in a year
        uint96 interestRatePerSec = uint96(interestRateBps) * 1e14 / ONE_YEAR;

        // Only compound if we're on a new block
        uint32 timeElapsed;
        unchecked {
            timeElapsed = uint32(block.timestamp) - interestAccumulatorUpdatedAt;
        }

        if (timeElapsed > 0) {
            dirty = true;

            // Compound the accumulator
            uint256 newInterestAccumulatorRay = gState.interestAccumulatorRay.continuouslyCompounded(
                timeElapsed,
                interestRatePerSec
            );

            // Calculate the latest totalDebt from this
            gState.totalDebt = newInterestAccumulatorRay.mulDivUp(
                gState.totalDebt,
                gState.interestAccumulatorRay
            ).encodeUInt128();
            gState.interestAccumulatorRay = newInterestAccumulatorRay;
        }
    }

    // --- INTERNAL FUNDING OF DEBT ---------------------------------

    function _fundFromTreasury(uint256 debtTokenAmount, address recipient) private {
        uint256 outstandingDebt = TRSRY.reserveDebt(debtToken, address(this));
        TRSRY.setDebt({
            debtor_: address(this),
            token_: debtToken,
            amount_: outstandingDebt + debtTokenAmount
        });

        // Since TRSRY holds sUSDS, a conversion must be done before
        // funding.
        uint256 debtSavingsVaultAmount = debtSavingsVault.previewWithdraw(debtTokenAmount);
        TRSRY.increaseWithdrawApproval(address(this), debtSavingsVault, debtSavingsVaultAmount);
        TRSRY.withdrawReserves(recipient, debtSavingsVault, debtSavingsVaultAmount);
    }

    function _repayTreasury(uint256 debtTokenAmount, address from) private {
        uint256 outstandingDebt = TRSRY.reserveDebt(debtToken, address(this));
        TRSRY.setDebt({
            debtor_: address(this),
            token_: debtToken,
            amount_: (outstandingDebt > debtTokenAmount) ? outstandingDebt - debtTokenAmount : 0
        });

        // Since TRSRY holds sUSDS, a conversion must be done before
        // sending sUSDS back.
        uint256 debtSavingsVaultAmount = debtSavingsVault.previewDeposit(debtTokenAmount);
        debtSavingsVault.safeTransferFrom(from, address(TRSRY), debtSavingsVaultAmount);
    }

    /**
     * @dev Reduce the total debt in storage by a repayment amount.
     * The sum each users debt may be slightly more than the recorded total debt
     * because users debt is rounded up for dust.
     * The Total debt is floored at 0.
     */
    function _reduceTotalDebt(
        GlobalStateCache memory gState,
        uint128 repayAmount
    ) private {
        if (repayAmount == 0) return; // @todo can this ever happen??

        unchecked {
            totalDebt = gState.totalDebt = repayAmount > gState.totalDebt
                ? 0
                : gState.totalDebt - repayAmount;
        }
    }

    // --- INTERNAL HEALTH ------------------------------------------

    function _validateOriginationLtv(
        AccountState storage aState,
        GlobalStateCache memory gState
    ) private view {
        LiquidationStatus memory status = _computeLiquidity(
            aState,
            gState
        );
        if (status.exceededMaxOriginationLtv) {
            revert ExceededMaxOriginationLtv(status.collateral, status.currentDebt);
        }
    }

    /**
     * @dev Generate the LiquidationStatus struct with current details 
     * for this account.
     */
    function _computeLiquidity(
        AccountState storage aState,
        GlobalStateCache memory gState
    ) private view returns (LiquidationStatus memory status) {
        status.collateral = aState.collateral;

        // Ensure to round both the currentDebt and the currentLtv up
        status.currentDebt = _currentAccountDebt(
            gState, 
            aState.debtCheckpoint, 
            aState.interestAccumulatorRay,
            true
        );

        status.currentLtv = status.collateral == 0
            ? 0 // @todo possible?
            : uint256(status.currentDebt).divWadUp(status.collateral);

        status.exceededLiquidationLtv = status.currentLtv > liquidationLtv;
        status.exceededMaxOriginationLtv = status.currentLtv > maxOriginationLtv;
    }

    // --- INTERNAL DELEGATION --------------------------------------

    function _getOrCreateDelegateEscrow(
        address delegate, 
        EnumerableSet.AddressSet storage acctDelegateAddresses,
        uint128 maxDelegateAddresses
    ) private returns (DelegateEscrow delegateEscrow) {
        delegateEscrow = delegateEscrows[delegate];
        
        if (address(delegateEscrow) == address(0)) {
            // Ensure it's added to this user's set of delegate addresses
            acctDelegateAddresses.add(delegate);

            // create new escrow if the user has under the 10 cap
            if (acctDelegateAddresses.length() > maxDelegateAddresses) revert TooManyDelegates();

            // @todo clones factory required?
            delegateEscrow = new DelegateEscrow(address(collateralToken), delegate);

            delegateEscrows[delegate] = delegateEscrow;
            emit DelegateEscrowCreated(delegate, address(delegateEscrow));
        }
    }
    
    function _applyDelegations(
        address onBehalfOf, 
        uint128 accountCollateral, 
        DelegationRequest[] calldata delegationRequests,
        bool rescindOnly
    ) private returns (uint128 totalDelegated) {
        AccountDelegations storage acctDelegations = _accountDelegations[onBehalfOf];
        EnumerableSet.AddressSet storage acctDelegateAddresses = acctDelegations.delegateAddresses;

        totalDelegated = acctDelegations.totalDelegated;
        uint128 maxDelegateAddresses = acctDelegations.maxDelegateAddresses;

        // If this is the first delegation, set to the default.
        // NB: This means the lowest number of delegate addresses an account can have after
        // whitelisting is 1 (since if it's set to zero, it will reset to the default)
        if (maxDelegateAddresses == 0) {
            acctDelegations.maxDelegateAddresses = maxDelegateAddresses = DEFAULT_MAX_DELEGATE_ADDRESSES;
        }

        uint256 length = delegationRequests.length;
        for (uint256 i; i < length; ++i) {
            totalDelegated = _applyDelegation(
                onBehalfOf, 
                accountCollateral, 
                totalDelegated,
                maxDelegateAddresses,
                acctDelegateAddresses,
                delegationRequests[i],
                rescindOnly
            );
        }

        // Ensure the account hasn't delegated more than their actual collateral balance.
        if (totalDelegated > accountCollateral) {
            revert ExceededCollateralBalance(accountCollateral, totalDelegated);
        }

        acctDelegations.totalDelegated = totalDelegated;
    }

    function _applyDelegation(
        address onBehalfOf,
        uint128 collateral,
        uint128 totalDelegated,
        uint128 maxDelegateAddresses,
        EnumerableSet.AddressSet storage acctDelegateAddresses,
        DelegationRequest calldata delegationRequest,
        bool rescindOnly
    ) private returns (uint128 newTotalDelegated) {
        if (delegationRequest.fromDelegate == address(0) && delegationRequest.toDelegate == address(0)) revert InvalidParam();
        if (delegationRequest.fromDelegate == delegationRequest.toDelegate) revert InvalidParam();

        // Special case to delegate all remaining (undelegated) collateral.
        uint128 collateralAmount = delegationRequest.collateralAmount == type(uint128).max
            ? collateral - totalDelegated
            : delegationRequest.collateralAmount;
        if (collateralAmount == 0) revert ExpectedNonZero();

        newTotalDelegated = totalDelegated;
        DelegateEscrow delegateEscrow;
        if (delegationRequest.fromDelegate == address(0)) {
            newTotalDelegated = collateralAmount;
        } else {
            delegateEscrow = delegateEscrows[delegationRequest.fromDelegate];
            if (address(delegateEscrow) == address(0)) revert InvalidDelegateEscrow();

            // Pull collateral from the old escrow
            // And remove from acctDelegateAddresses if it's now empty
            uint256 delegatedBalance = delegateEscrow.rescindDelegation(onBehalfOf, collateralAmount);
            if (delegatedBalance == 0) {
                acctDelegateAddresses.remove(delegationRequest.fromDelegate);
            }
        }
        
        if (delegationRequest.toDelegate == address(0)) {
            newTotalDelegated -= collateralAmount;
        } else if (rescindOnly) {
            revert CanOnlyRescindDelegation();
        } else {
            delegateEscrow = _getOrCreateDelegateEscrow(
                delegationRequest.toDelegate, 
                acctDelegateAddresses, 
                maxDelegateAddresses
            );

            // Push collateral to the new escrow
            collateralToken.safeApprove(address(delegateEscrow), collateralAmount);
            delegateEscrow.delegate(onBehalfOf, collateralAmount);
        }

        emit DelegationApplied(
            msg.sender, 
            delegationRequest.fromDelegate, 
            delegationRequest.toDelegate, 
            collateralAmount
        );
    }

    // --- INTERNAL AUX ------------------------------------------

    /**
     * @dev Calculate the latest debt for a given account & token.
     * Derived from the prior debt checkpoint, and the interest accumulator.
     */
    function _currentAccountDebt(
        GlobalStateCache memory gState,
        uint128 accountDebtCheckpoint,
        uint256 accountInterestAccumulatorRay,
        bool roundUp
    ) private pure returns (uint128 result) {
        if (accountDebtCheckpoint == 0) return 0;

        uint256 debt = roundUp
            ? gState.interestAccumulatorRay.mulDivUp(
                accountDebtCheckpoint, 
                accountInterestAccumulatorRay
            )
            : gState.interestAccumulatorRay.mulDivDown(
                accountDebtCheckpoint, 
                accountInterestAccumulatorRay
            );
        return debt.encodeUInt128();
    }

}
