// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IStaking} from "interfaces/IStaking.sol";

import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {CHREGv1} from "modules/CHREG/CHREG.v1.sol";
import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {DLGTEv1} from "modules/DLGTE/DLGTE.v1.sol";

import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";
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

    //============================================================================================//
    //                                         IMMUTABLES                                         //
    //============================================================================================//

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

    //============================================================================================//
    //                                          MODULES                                           //
    //============================================================================================//

    CHREGv1 public CHREG; // Olympus V3 Clearinghouse Registry Module
    MINTRv1 public MINTR; // Olympus V3 Minter Module
    TRSRYv1 public TRSRY; // Olympus V3 Treasury Module
    DLGTEv1 public DLGTE; // Olympus V3 Delegation Module

//-- begin slot 6

    /// @notice The total amount of collateral posted across all accounts.
    uint128 public override totalCollateral;

    /// @notice The total amount of debt which has been borrowed across all users 
    /// as of the latest checkpoint
    uint128 public override totalDebt;

//--- begin slot 7
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

//--- begin slot 8

    /// @notice The accumulator index used to track the compounding of debt, starting at 1e27 at genesis
    /// @dev To RAY (1e27) precision
    uint256 public override interestAccumulatorRay;

//-- begin slot 9
    /// @dev A per account store, tracking collateral/debt as of their latest checkpoint.
    mapping(address /* account */ => AccountState) private allAccountState;

    //============================================================================================//
    //                                         CONSTANTS                                          //
    //============================================================================================//

    bytes32 public constant COOLER_OVERSEER_ROLE = bytes32("cooler_overseer");

    /// @notice Extra precision scalar
    uint256 private constant RAY = 1e27;

    uint96 private constant ONE_YEAR = 365 days;

    //============================================================================================//
    //                                      INITIALIZATION                                        //
    //============================================================================================//

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

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](5);
        dependencies[0] = toKeycode("CHREG");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("TRSRY");
        dependencies[4] = toKeycode("DLGTE");

        CHREG = CHREGv1(getModuleAddress(toKeycode("CHREG")));
        MINTR = MINTRv1(getModuleAddress(toKeycode("MINTR")));
        ROLES = ROLESv1(getModuleAddress(toKeycode("ROLES")));
        TRSRY = TRSRYv1(getModuleAddress(toKeycode("TRSRY")));
        DLGTE = DLGTEv1(getModuleAddress(toKeycode("DLGTE")));

        (uint8 CHREG_MAJOR, ) = CHREG.VERSION();
        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();
        (uint8 DLGTE_MAJOR, ) = DLGTE.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1, 1, 1]);
        if (CHREG_MAJOR != 1 || MINTR_MAJOR != 1 || ROLES_MAJOR != 1 || TRSRY_MAJOR != 1 || DLGTE_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Approve MINTR for burning OHM (called here so that it is re-approved on updates)
        ohm.approve(address(MINTR), type(uint256).max);

        // Approve DLGTE to pull gOHM for delegation
        collateralToken.approve(address(DLGTE), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode CHREG_KEYCODE = toKeycode("CHREG");
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        Keycode DLGTE_KEYCODE = toKeycode("DLGTE");

        requests = new Permissions[](10);
        requests[0] = Permissions(CHREG_KEYCODE, CHREG.activateClearinghouse.selector);
        requests[1] = Permissions(CHREG_KEYCODE, CHREG.deactivateClearinghouse.selector);
        requests[2] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        requests[3] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        requests[4] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        requests[5] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        requests[6] = Permissions(DLGTE_KEYCODE, DLGTE.depositUndelegatedGohm.selector);
        requests[7] = Permissions(DLGTE_KEYCODE, DLGTE.withdrawUndelegatedGohm.selector);
        requests[8] = Permissions(DLGTE_KEYCODE, DLGTE.applyDelegations.selector);
        requests[9] = Permissions(DLGTE_KEYCODE, DLGTE.setMaxDelegateAddresses.selector);
    }

    //============================================================================================//
    //                                        COLLATERAL                                          //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function addCollateral(
        uint128 collateralAmount,
        address onBehalfOf,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external override {
        if (collateralAmount == 0) revert ExpectedNonZero();
        if (onBehalfOf == address(0)) revert InvalidAddress();

        collateralToken.safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount 
        );

        AccountState storage aState = allAccountState[onBehalfOf];
        uint128 newAccountCollateral = aState.collateral + collateralAmount;
        aState.collateral = newAccountCollateral;
        totalCollateral += collateralAmount;

        // Deposit the gOHM into DLGTE (undelegated)
        DLGTE.depositUndelegatedGohm(onBehalfOf, collateralAmount);

        // Apply any delegation requests on the undelegated gOHM
        if (delegationRequests.length > 0) {
            // While adding collateral on another user's behalf is ok,
            // delegating on behalf of someone else is not allowed.
            if (onBehalfOf != msg.sender) revert InvalidAddress();

            DLGTE.applyDelegations(
                msg.sender,
                delegationRequests
            );
        }

        // NB: No need to check if the position is healthy when adding collateral as this
        // only improves the liquidity.
        emit CollateralAdded(msg.sender, onBehalfOf, collateralAmount);
    }

    /// @inheritdoc IMonoCooler
    function withdrawCollateral(
        uint128 collateralAmount,
        address recipient,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external override {
        if (collateralAmount == 0) revert ExpectedNonZero();
        if (recipient == address(0)) revert InvalidAddress();

        AccountState storage aState = allAccountState[msg.sender];

        if (delegationRequests.length > 0) {
            // Apply the delegation requests in order to pull the required collateral back into this contract.
            DLGTE.applyDelegations(
                msg.sender,
                delegationRequests
            );
        }

        DLGTE.withdrawUndelegatedGohm(msg.sender, collateralAmount);

        // Update the collateral balance, and then verify that it doesn't make the debt unsafe.
        aState.collateral -= collateralAmount;
        totalCollateral -= collateralAmount;

        // Verify the account LTV given the reduction in collateral
        _validateOriginationLtv(aState, _globalStateRO());

        // Finally transfer the collateral to the recipient
        collateralToken.safeTransfer(
            recipient,
            collateralAmount
        );
        emit CollateralWithdrawn(msg.sender, recipient, collateralAmount);
    }

    //============================================================================================//
    //                                       BORROW/REPAY                                         //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function borrow(uint128 borrowAmount, address recipient) external override {
        if (borrowsPaused) revert Paused();
        if (borrowAmount == 0) revert ExpectedNonZero();
        if (recipient == address(0)) revert InvalidAddress();

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

    /// @inheritdoc IMonoCooler
    function repay(uint128 repayAmount, address onBehalfOf) external override {
        if (repayAmount == 0) revert ExpectedNonZero();
        if (onBehalfOf == address(0)) revert InvalidAddress();

        AccountState storage aState = allAccountState[onBehalfOf];
        GlobalStateCache memory gState = _globalStateRW();

        // Update the account's latest debt
        uint128 latestDebt = _currentAccountDebt(
            gState, 
            aState.debtCheckpoint,
            aState.interestAccumulatorRay,
            true // round up for repay balance
        );
        if (latestDebt == 0) revert ExpectedNonZero();

        // Cap the amount to be repaid to the current debt as of this block
        if (repayAmount >= latestDebt) {
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

    //============================================================================================//
    //                                        DELEGATION                                          //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function applyDelegations(
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external override returns (
        uint256 /*totalDelegated*/, 
        uint256 /*totalUndelegated*/
    ) {
        return DLGTE.applyDelegations(msg.sender, delegationRequests);
    }

    /// @inheritdoc IMonoCooler
    function applyUnhealthyDelegations(
        address account,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external override returns (
        uint256 totalUndelegated
    ) {
        if (liquidationsPaused) revert Paused();
        GlobalStateCache memory gState = _globalStateRW();
        LiquidationStatus memory status = _computeLiquidity(
            allAccountState[account],
            gState
        );
        if (!status.exceededLiquidationLtv) revert CannotLiquidate();

        // Note: More collateral may be undelegated than required for the liquidation here.
        // But this is assumed ok - the liquidated user will need to re-apply the delegations again.
        uint256 totalDelegated;
        (totalDelegated, totalUndelegated) = DLGTE.applyDelegations(
            account, 
            delegationRequests
        );

        // Only allowed to undelegate.
        if (totalDelegated > 0) revert InvalidDelegationRequests();
    }

    //============================================================================================//
    //                                       LIQUIDATIONS                                         //
    //============================================================================================//

    // @todo incentivise liquidations

    /// @inheritdoc IMonoCooler
    function batchLiquidate(
        address[] calldata accounts,
        DLGTEv1.DelegationRequest[][] calldata delegationRequests
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
                
                // Apply any undelegation requests
                DLGTEv1.DelegationRequest[] calldata dreqs = delegationRequests[i];
                if (dreqs.length > 1) {
                    // Note: More collateral may be undelegated than required for the liquidation here.
                    // But this is assumed ok - the liquidated user will need to re-apply the delegations again.
                    (uint256 appliedDelegations,) = DLGTE.applyDelegations(
                        account, 
                        dreqs
                    );

                    // For liquidations, only allow undelegation requests
                    if (appliedDelegations > 0) revert InvalidDelegationRequests();
                }

                // Withdraw the undelegated gOHM
                DLGTE.withdrawUndelegatedGohm(account, status.collateral);

                totalCollateralClaimed += status.collateral;
                totalDebtWiped += status.currentDebt;

                // Clear the account data
                delete allAccountState[account];
            }
        }

        // burn the gOHM collateral and update the total state.
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

    //============================================================================================//
    //                                           ADMIN                                            //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
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

    /// @inheritdoc IMonoCooler
    function setLiquidationsPaused(bool isPaused) external override onlyRole(COOLER_OVERSEER_ROLE) {
        liquidationsPaused = isPaused;
        emit LiquidationsPausedSet(isPaused);
    }

    /// @inheritdoc IMonoCooler
    function setBorrowPaused(bool isPaused) external override onlyRole(COOLER_OVERSEER_ROLE) {
        emit BorrowPausedSet(isPaused);
        borrowsPaused = isPaused;
    }

    /// @inheritdoc IMonoCooler
    function setInterestRateBps(uint16 newInterestRateBps) external override onlyRole(COOLER_OVERSEER_ROLE) {
        // Force an update of state on the old rate first.
        _globalStateRW();

        emit InterestRateSet(newInterestRateBps);
        interestRateBps = newInterestRateBps;
    }

    /// @inheritdoc IMonoCooler
    function setMaxDelegateAddresses(
        address account, 
        uint32 maxDelegateAddresses
    ) external override onlyRole(COOLER_OVERSEER_ROLE) {
        DLGTE.setMaxDelegateAddresses(account, maxDelegateAddresses);
    }

    /// @inheritdoc IMonoCooler
    function checkpointDebt() external override returns (uint128 /*totalDebt*/, uint256 /*interestAccumulatorRay*/) {
        GlobalStateCache memory gState = _globalStateRW();
        return (gState.totalDebt, gState.interestAccumulatorRay);
    }

    //============================================================================================//
    //                                      VIEW FUNCTIONS                                        //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
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
        position.maxOriginationDebtAmount = uint256(maxOriginationLtv)
            .mulWadDown(position.collateral)
            .encodeUInt128();

        // liquidationLtv [USDS/gOHM] * collateral [gOHM]
        // Round down to get the conservative max debt allowed
        position.liquidationDebtAmount = uint256(liquidationLtv)
            .mulWadDown(position.collateral)
            .encodeUInt128();

        // healthFactor = liquidationLtv [USDS/gOHM] * collateral [gOHM] / debt [USDS]
        position.healthFactor = position.currentDebt == 0
            ? type(uint256).max
            : uint256(liquidationLtv).mulDivDown(
                position.collateral,
                position.currentDebt
            );
        
        (
            /*totalGOhm*/, 
            position.totalDelegated,
            position.numDelegateAddresses, 
            position.maxDelegateAddresses
        ) = DLGTE.accountDelegationSummary(account);
    }

    /// @inheritdoc IMonoCooler
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

    /// @inheritdoc IMonoCooler
    function accountDelegationsList(
        address account, 
        uint256 startIndex, 
        uint256 maxItems
    ) external override view returns (
        DLGTEv1.AccountDelegation[] memory delegations
    ) {
        return DLGTE.accountDelegationsList(account, startIndex, maxItems);
    }

    /// @inheritdoc IMonoCooler
    function accountState(address account) external override view returns (AccountState memory) {
        return allAccountState[account];
    }
    
    /// @inheritdoc IMonoCooler
    function globalState() external override view returns (uint128 /*totalDebt*/, uint256 /*interestAccumulatorRay*/) {
        GlobalStateCache memory gState = _globalStateRO();
        return (gState.totalDebt, gState.interestAccumulatorRay);
    }

    //============================================================================================//
    //                                    INTERNAL STATE MGMT                                     //
    //============================================================================================//

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
            // If the cache is dirty (increase in time) then write the 
            // updated state
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
        // Copies from storage
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

    //============================================================================================//
    //                                     INTERNAL FUNDING                                       //
    //============================================================================================//

    function _fundFromTreasury(uint256 debtTokenAmount, address recipient) private {
        uint256 outstandingDebt = TRSRY.reserveDebt(debtToken, address(this));
        TRSRY.setDebt({
            debtor_: address(this),
            token_: debtToken,
            amount_: outstandingDebt + debtTokenAmount
        });

        // Since TRSRY holds sUSDS, a conversion must be done before funding.
        // Withdraw that sUSDS amount locally and then redeem to USDS sending to the recipient
        uint256 debtSavingsVaultAmount = debtSavingsVault.previewWithdraw(debtTokenAmount);
        TRSRY.increaseWithdrawApproval(address(this), debtSavingsVault, debtSavingsVaultAmount);
        TRSRY.withdrawReserves(address(this), debtSavingsVault, debtSavingsVaultAmount);
        debtSavingsVault.redeem(debtSavingsVaultAmount, recipient, address(this));
    }

    function _repayTreasury(uint256 debtTokenAmount, address from) private {
        uint256 outstandingDebt = TRSRY.reserveDebt(debtToken, address(this));
        TRSRY.setDebt({
            debtor_: address(this),
            token_: debtToken,
            amount_: (outstandingDebt > debtTokenAmount) ? outstandingDebt - debtTokenAmount : 0
        });

        // Pull in the debToken from the user and deposit into the savings vault,
        // with TRSRY as the receiver
        debtToken.safeTransferFrom(from, address(this), debtTokenAmount);
        debtToken.safeApprove(address(debtSavingsVault), debtTokenAmount);
        debtSavingsVault.deposit(debtTokenAmount, address(TRSRY));
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
        unchecked {
            totalDebt = gState.totalDebt = repayAmount > gState.totalDebt
                ? 0
                : gState.totalDebt - repayAmount;
        }
    }

    //============================================================================================//
    //                                      INTERNAL HEALTH                                       //
    //============================================================================================//

    function _validateOriginationLtv(
        AccountState storage aState,
        GlobalStateCache memory gState
    ) private view {
        LiquidationStatus memory status = _computeLiquidity(
            aState,
            gState
        );
        if (status.exceededMaxOriginationLtv) {
            revert ExceededMaxOriginationLtv(status.currentLtv, maxOriginationLtv);
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
            ? 0
            : uint256(status.currentDebt).divWadUp(status.collateral);

        status.exceededLiquidationLtv = status.currentLtv > liquidationLtv;
        status.exceededMaxOriginationLtv = status.currentLtv > maxOriginationLtv;
    }

    //============================================================================================//
    //                                       INTERNAL AUX                                         //
    //============================================================================================//

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
