// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";

import {IStaking} from "interfaces/IStaking.sol";

import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {DLGTEv1} from "modules/DLGTE/DLGTE.v1.sol";

import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";
import {ICoolerLtvOracle} from "policies/interfaces/ICoolerLtvOracle.sol";
import {SafeCast} from "libraries/SafeCast.sol";
import {CompoundedInterest} from "libraries/CompoundedInterest.sol";

// @todo add helper to get max debt given collateral?

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

    /// @inheritdoc IMonoCooler
    ERC20 public immutable override collateralToken;

    /// @inheritdoc IMonoCooler
    ERC20 public immutable override debtToken;

    /// @inheritdoc IMonoCooler
    ERC20 public immutable override ohm;

    /// @inheritdoc IMonoCooler
    IStaking public immutable override staking;

    /// @inheritdoc IMonoCooler
    ERC4626 public immutable override debtSavingsVault;

    /// @inheritdoc IMonoCooler
    uint256 public immutable override minDebtRequired;

    /// @inheritdoc IMonoCooler
    bytes32 public immutable override DOMAIN_SEPARATOR;

    //============================================================================================//
    //                                          MODULES                                           //
    //============================================================================================//

    MINTRv1 public MINTR; // Olympus V3 Minter Module
    TRSRYv1 public TRSRY; // Olympus V3 Treasury Module
    DLGTEv1 public DLGTE; // Olympus V3 Delegation Module

    //============================================================================================//
    //                                         MUTABLES                                           //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    uint128 public override totalCollateral;

    /// @inheritdoc IMonoCooler
    uint128 public override totalDebt;

    /// @inheritdoc IMonoCooler
    bool public override liquidationsPaused;

    /// @inheritdoc IMonoCooler
    bool public override borrowsPaused;

    /// @inheritdoc IMonoCooler
    uint16 public override interestRateBps;

    /// @inheritdoc IMonoCooler
    uint32 public override interestAccumulatorUpdatedAt;

    /// @inheritdoc IMonoCooler
    ICoolerLtvOracle public override ltvOracle;

    /// @inheritdoc IMonoCooler
    uint256 public override interestAccumulatorRay;

    /// @dev A per account store, tracking collateral/debt as of their latest checkpoint.
    mapping(address /* account */ => AccountState) private allAccountState;

    /// @inheritdoc IMonoCooler
    mapping(address /* account */ => 
        mapping(address /* authorized */ => 
            uint96 /* authorizationDeadline */
        )
    ) public override authorizations;

    /// @inheritdoc IMonoCooler
    mapping(address /* account */ => uint256) public override authorizationNonces;

    //============================================================================================//
    //                                         CONSTANTS                                          //
    //============================================================================================//

    bytes32 public constant COOLER_OVERSEER_ROLE = bytes32("cooler_overseer");

    /// @notice Extra precision scalar
    uint256 private constant RAY = 1e27;

    /// @dev The EIP-712 typeHash for EIP712Domain.
    bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");

    /// @dev The EIP-712 typeHash for Authorization.
    bytes32 private constant AUTHORIZATION_TYPEHASH =
        keccak256("Authorization(address account,address authorized,uint96 authorizationDeadline,uint256 nonce,uint256 signatureDeadline)");

    //============================================================================================//
    //                                      INITIALIZATION                                        //
    //============================================================================================//

    constructor(
        address ohm_,
        address gohm_,
        address staking_,
        address debtSavingsVault_,
        address kernel_,
        address ltvOracle_,
        uint16 interestRateBps_,
        uint256 minDebtRequired_
    ) Policy(Kernel(kernel_)) {
        collateralToken = ERC20(gohm_);
        debtSavingsVault = ERC4626(debtSavingsVault_);
        debtToken = ERC20(debtSavingsVault.asset());

        // Only handle 18dp collateral and debt tokens
        if (collateralToken.decimals() != 18) revert InvalidParam();
        if (debtToken.decimals() != 18) revert InvalidParam();

        ohm = ERC20(ohm_);
        staking = IStaking(staking_);
        minDebtRequired = minDebtRequired_;

        ltvOracle = ICoolerLtvOracle(ltvOracle_);
        (uint96 newOLTV, uint96 newLLTV) = ltvOracle.currentLtvs();
        if (newOLTV > newLLTV) revert InvalidParam();

        interestRateBps = interestRateBps_;
        interestAccumulatorUpdatedAt = uint32(block.timestamp);
        interestAccumulatorRay = RAY;

        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");
        dependencies[2] = toKeycode("TRSRY");
        dependencies[3] = toKeycode("DLGTE");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[2]));
        DLGTE = DLGTEv1(getModuleAddress(dependencies[3]));

        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();
        (uint8 DLGTE_MAJOR, ) = DLGTE.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1, 1]);
        if (
            MINTR_MAJOR != 1 ||
            ROLES_MAJOR != 1 ||
            TRSRY_MAJOR != 1 ||
            DLGTE_MAJOR != 1
        ) revert Policy_WrongModuleVersion(expected);

        // Approve MINTR for burning OHM (called here so that it is re-approved on updates)
        ohm.approve(address(MINTR), type(uint256).max);

        // Approve DLGTE to pull gOHM for delegation
        collateralToken.approve(address(DLGTE), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        Keycode DLGTE_KEYCODE = toKeycode("DLGTE");

        requests = new Permissions[](8);
        requests[0] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        requests[3] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        requests[4] = Permissions(DLGTE_KEYCODE, DLGTE.depositUndelegatedGohm.selector);
        requests[5] = Permissions(DLGTE_KEYCODE, DLGTE.withdrawUndelegatedGohm.selector);
        requests[6] = Permissions(DLGTE_KEYCODE, DLGTE.applyDelegations.selector);
        requests[7] = Permissions(DLGTE_KEYCODE, DLGTE.setMaxDelegateAddresses.selector);
    }

    //============================================================================================//
    //                                     AUTHORIZATION                                          //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function setAuthorization(address authorized, uint96 authorizationDeadline) external {
        emit AuthorizationSet(msg.sender, msg.sender, authorized, authorizationDeadline);
        authorizations[msg.sender][authorized] = authorizationDeadline;
    }

    /// @inheritdoc IMonoCooler
    function setAuthorizationWithSig(Authorization memory authorization, Signature calldata signature) external {
        /// Do not check whether authorization is already set because the nonce increment is a desired side effect.
        if (block.timestamp > authorization.signatureDeadline) revert ExpiredSignature(authorization.signatureDeadline);
        if (authorization.nonce != authorizationNonces[authorization.account]++) revert InvalidNonce(authorization.nonce);

        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        address signer = ECDSA.recover(
            ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash),
            signature.v,
            signature.r,
            signature.s
        );
        if (signer != authorization.account) revert InvalidSigner(signer, authorization.account);

        emit AuthorizationSet(msg.sender, authorization.account, authorization.authorized, authorization.authorizationDeadline);
        authorizations[authorization.account][authorization.authorized] = authorization.authorizationDeadline;
    }

    /// @inheritdoc IMonoCooler
    function isSenderAuthorized(address sender, address onBehalfOf) public view returns (bool) {
        return sender == onBehalfOf || block.timestamp < authorizations[onBehalfOf][sender];
    }

    //============================================================================================//
    //                                       COLLATERAL                                           //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function addCollateral(
        uint128 collateralAmount,
        address onBehalfOf,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external override {
        if (collateralAmount == 0) revert ExpectedNonZero();
        if (onBehalfOf == address(0)) revert InvalidAddress();

        // Add collateral on behalf of another account
        AccountState storage aState = allAccountState[onBehalfOf];
        collateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);

        aState.collateral += collateralAmount;
        totalCollateral += collateralAmount;

        // Deposit the gOHM into DLGTE (undelegated)
        DLGTE.depositUndelegatedGohm(onBehalfOf, collateralAmount);

        // Apply any delegation requests on the undelegated gOHM
        if (delegationRequests.length > 0) {
            // While adding collateral on another user's behalf is ok,
            // delegating on behalf of someone else is not allowed unless authorized
            if (!isSenderAuthorized(msg.sender, onBehalfOf)) revert UnathorizedOnBehalfOf();
            DLGTE.applyDelegations(onBehalfOf, delegationRequests);
        }

        // NB: No need to check if the position is healthy when adding collateral as this
        // only decreases the LTV.
        emit CollateralAdded(msg.sender, onBehalfOf, collateralAmount);
    }

    /// @inheritdoc IMonoCooler
    function withdrawCollateral(
        uint128 collateralAmount,
        address onBehalfOf,
        address recipient,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external override returns (uint128 collateralWithdrawn) {
        if (collateralAmount == 0) revert ExpectedNonZero();
        if (recipient == address(0)) revert InvalidAddress();
        if (!isSenderAuthorized(msg.sender, onBehalfOf)) revert UnathorizedOnBehalfOf();

        // No need to sync global debt state when withdrawing collateral
        GlobalStateCache memory gStateCache = _globalStateRO();
        AccountState storage aState = allAccountState[onBehalfOf];
        uint128 _accountCollateral = aState.collateral;

        if (delegationRequests.length > 0) {
            // Apply the delegation requests in order to pull the required collateral back into this contract.
            DLGTE.applyDelegations(onBehalfOf, delegationRequests);
        }

        uint128 currentDebt = _currentAccountDebt(
            aState.debtCheckpoint, 
            aState.interestAccumulatorRay, 
            gStateCache.interestAccumulatorRay, 
            true
        );

        if (collateralAmount == type(uint128).max) {
            uint128 minRequiredCollateral = _minCollateral(currentDebt, gStateCache.maxOriginationLtv);
            if (_accountCollateral > minRequiredCollateral) {
                collateralWithdrawn = _accountCollateral - minRequiredCollateral;
            } else {
                // Already at/above the origination LTV
                revert ExceededMaxOriginationLtv(
                    _calculateCurrentLtv(currentDebt, _accountCollateral),
                    gStateCache.maxOriginationLtv
                );
            }
            _accountCollateral = minRequiredCollateral;
        } else {
            collateralWithdrawn = collateralAmount;
            if (_accountCollateral < collateralWithdrawn) revert ExceededCollateralBalance();
            _accountCollateral -= collateralWithdrawn;
        }
        
        DLGTE.withdrawUndelegatedGohm(onBehalfOf, collateralWithdrawn);

        // Update the collateral balance, and then verify that it doesn't make the debt unsafe.
        aState.collateral = _accountCollateral;
        totalCollateral -= collateralWithdrawn;

        // Calculate the new LTV and verify it's less than or equal to the maxOriginationLtv
        if (currentDebt > 0) {
            uint256 newLtv = _calculateCurrentLtv(currentDebt, _accountCollateral);
            _validateOriginationLtv(newLtv, gStateCache.maxOriginationLtv);
        }

        // Finally transfer the collateral to the recipient
        emit CollateralWithdrawn(msg.sender, onBehalfOf, recipient, collateralWithdrawn);
        collateralToken.safeTransfer(recipient, collateralWithdrawn);
    }

    //============================================================================================//
    //                                       BORROW/REPAY                                         //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function borrow(
        uint128 borrowAmount,
        address onBehalfOf,
        address recipient
    ) external override returns (uint128 amountBorrowed) {
        if (borrowsPaused) revert Paused();
        if (borrowAmount == 0) revert ExpectedNonZero();
        if (recipient == address(0)) revert InvalidAddress();
        if (!isSenderAuthorized(msg.sender, onBehalfOf)) revert UnathorizedOnBehalfOf();

        // Sync global debt state when borrowing
        GlobalStateCache memory gStateCache = _globalStateRW();
        AccountState storage aState = allAccountState[onBehalfOf];
        uint128 _accountCollateral = aState.collateral;
        uint128 _accountDebtCheckpoint = aState.debtCheckpoint;

        // don't round up the debt when borrowing.
        uint128 currentDebt = _currentAccountDebt(
            _accountDebtCheckpoint, 
            aState.interestAccumulatorRay, 
            gStateCache.interestAccumulatorRay, 
            false
        );

        // Apply the new borrow. If type(uint128).max was specified
        // then borrow up to the maxOriginationLtv
        if (borrowAmount == type(uint128).max) {
            uint128 accountTotalDebt = _maxDebt(_accountCollateral, gStateCache.maxOriginationLtv);
            if (accountTotalDebt > currentDebt) {
                amountBorrowed = accountTotalDebt - currentDebt;
            } else {
                // Already at/above the origination LTV
                revert ExceededMaxOriginationLtv(
                    _calculateCurrentLtv(currentDebt, _accountCollateral),
                    gStateCache.maxOriginationLtv
                );
            }
            _accountDebtCheckpoint = accountTotalDebt;
        } else {
            amountBorrowed = borrowAmount;
            _accountDebtCheckpoint = currentDebt + amountBorrowed;
        }

        if (_accountDebtCheckpoint < minDebtRequired)
            revert MinDebtNotMet(minDebtRequired, _accountDebtCheckpoint);

        // Update the state
        aState.debtCheckpoint = _accountDebtCheckpoint;
        aState.interestAccumulatorRay = gStateCache.interestAccumulatorRay;
        totalDebt = gStateCache.totalDebt = gStateCache.totalDebt + amountBorrowed;

        // Calculate the new LTV and verify it's less than or equal to the maxOriginationLtv
        {
            uint256 newLtv = _calculateCurrentLtv(_accountDebtCheckpoint, _accountCollateral);
            _validateOriginationLtv(newLtv, gStateCache.maxOriginationLtv);
        }

        // Finally, borrow the funds from the Treasury and send the tokens to the recipient.
        emit Borrow(msg.sender, onBehalfOf, recipient, amountBorrowed);
        _fundFromTreasury(amountBorrowed, recipient);
    }

    /// @inheritdoc IMonoCooler
    function repay(
        uint128 repayAmount,
        address onBehalfOf
    ) external override returns (uint128 amountRepaid) {
        if (repayAmount == 0) revert ExpectedNonZero();
        if (onBehalfOf == address(0)) revert InvalidAddress();

        // Sync global debt state when repaying
        GlobalStateCache memory gStateCache = _globalStateRW();
        AccountState storage aState = allAccountState[onBehalfOf];
        uint128 _accountDebtCheckpoint = aState.debtCheckpoint;

        // Update the account's latest debt
        // round up for repay balance
        uint128 latestDebt = _currentAccountDebt(
            _accountDebtCheckpoint, 
            aState.interestAccumulatorRay, 
            gStateCache.interestAccumulatorRay, 
            true
        );
        if (latestDebt == 0) revert ExpectedNonZero();

        // Cap the amount to be repaid to the current debt as of this block
        if (repayAmount < latestDebt) {
            amountRepaid = repayAmount;

            // Ensure the minimum debt amounts are still maintained
            aState.debtCheckpoint = _accountDebtCheckpoint = latestDebt - amountRepaid;
            if (_accountDebtCheckpoint < minDebtRequired) {
                revert MinDebtNotMet(minDebtRequired, _accountDebtCheckpoint);
            }
        } else {
            amountRepaid = latestDebt;
            aState.debtCheckpoint = 0;
        }

        aState.interestAccumulatorRay = gStateCache.interestAccumulatorRay;
        _reduceTotalDebt(gStateCache, amountRepaid);

        // NB: No need to check if the position is healthy after a repayment as this
        // only decreases the LTV.
        emit Repay(msg.sender, onBehalfOf, amountRepaid);
        _repayTreasury(amountRepaid, msg.sender);
    }

    //============================================================================================//
    //                                        DELEGATION                                          //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function applyDelegations(
        DLGTEv1.DelegationRequest[] calldata delegationRequests,
        address onBehalfOf
    ) external override returns (uint256 /*totalDelegated*/, uint256 /*totalUndelegated*/) {
        if (!isSenderAuthorized(msg.sender, onBehalfOf)) revert UnathorizedOnBehalfOf();
        return DLGTE.applyDelegations(onBehalfOf, delegationRequests);
    }

    /// @inheritdoc IMonoCooler
    function applyUnhealthyDelegations(
        address account,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external override returns (uint256 totalUndelegated) {
        if (liquidationsPaused) revert Paused();
        GlobalStateCache memory gState = _globalStateRW();
        LiquidationStatus memory status = _computeLiquidity(allAccountState[account], gState);
        if (!status.exceededLiquidationLtv) revert CannotLiquidate();

        // Note: More collateral may be undelegated than required for the liquidation here.
        // But this is assumed ok - the liquidated user will need to re-apply the delegations again.
        uint256 totalDelegated;
        (totalDelegated, totalUndelegated) = DLGTE.applyDelegations(account, delegationRequests);

        // Only allowed to undelegate.
        if (totalDelegated > 0) revert InvalidDelegationRequests();
    }

    //============================================================================================//
    //                                       LIQUIDATIONS                                         //
    //============================================================================================//

    // @todo incentivise liquidations
    /*
Frontier:
> I wasn't sure how we want to incentivise liquidations. Heart based model with increasing reward doesn't work here imo since we can't easily know the start time of when it first became unhealthy.

Anon:
> First thought that comes to mind is have interest keep accruing but give the keeper the delta above liq point? kind of an already there gda mechanism

It means the liquidation won't happen until that accrued interest pays for gas++, but probably not a problem if it's a few hours/days after the fact. It’s a softer liquidation mechanism but that’s more in the nature of expiry time to debt threshold, ie you could top up or repay before liquidation bot actually liquidates
*/

    /// @inheritdoc IMonoCooler
    function batchLiquidate(
        address[] calldata accounts,
        DLGTEv1.DelegationRequest[][] calldata delegationRequests
    ) external override returns (uint128 totalCollateralClaimed, uint128 totalDebtWiped) {
        if (liquidationsPaused) revert Paused();

        LiquidationStatus memory status;
        GlobalStateCache memory gState = _globalStateRW();
        address account;
        uint256 numAccounts = accounts.length;
        for (uint256 i; i < numAccounts; ++i) {
            account = accounts[i];
            status = _computeLiquidity(allAccountState[account], gState);

            // Skip if this account is still under the maxLTV
            if (status.exceededLiquidationLtv) {
                emit Liquidated(account, status.collateral, status.currentDebt);

                // Apply any undelegation requests
                DLGTEv1.DelegationRequest[] calldata dreqs = delegationRequests[i];
                if (dreqs.length > 1) {
                    // Note: More collateral may be undelegated than required for the liquidation here.
                    // But this is assumed ok - the liquidated user will need to re-apply the delegations again.
                    (uint256 appliedDelegations, ) = DLGTE.applyDelegations(account, dreqs);

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
            MINTR.burnOhm(
                address(this),
                staking.unstake(address(this), totalCollateralClaimed, false, false)
            );

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
    function setLtvOracle(address newOracle) external override onlyRole(COOLER_OVERSEER_ROLE) {
        (uint96 newOLTV, uint96 newLLTV) = ICoolerLtvOracle(newOracle).currentLtvs();
        if (newOLTV > newLLTV) revert InvalidParam();

        (uint96 existingOLTV, uint96 existingLLTV) = ICoolerLtvOracle(ltvOracle).currentLtvs();
        if (newOLTV < existingOLTV || newLLTV < existingLLTV) revert InvalidParam();

        emit LtvOracleSet(newOracle);
        ltvOracle = ICoolerLtvOracle(newOracle);
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
    function setInterestRateBps(
        uint16 newInterestRateBps
    ) external override onlyRole(COOLER_OVERSEER_ROLE) {
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
    function checkpointDebt()
        external
        override
        returns (uint128 /*totalDebt*/, uint256 /*interestAccumulatorRay*/)
    {
        GlobalStateCache memory gState = _globalStateRW();
        return (gState.totalDebt, gState.interestAccumulatorRay);
    }

    //============================================================================================//
    //                                      VIEW FUNCTIONS                                        //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function loanToValues() external view override returns (uint96 maxOriginationLtv, uint96 liquidationLtv) {
        return ltvOracle.currentLtvs();
    }

    /// @inheritdoc IMonoCooler
    function debtDeltaForMaxOriginationLtv(
        address account,
        int128 collateralDelta
    ) external view override returns (int128 debtDelta) {
        AccountState storage aState = allAccountState[account];
        GlobalStateCache memory gStateCache = _globalStateRO();

        int128 newCollateral = collateralDelta + int128(aState.collateral);
        if (newCollateral < 0) revert InvalidCollateralDelta();

        uint128 maxDebt = _maxDebt(uint128(newCollateral), gStateCache.maxOriginationLtv);
        uint128 currentDebt = _currentAccountDebt(
            aState.debtCheckpoint, 
            aState.interestAccumulatorRay, 
            gStateCache.interestAccumulatorRay, 
            true
        );
        debtDelta = int128(maxDebt) - int128(currentDebt);
    }

    /// @inheritdoc IMonoCooler
    function accountPosition(
        address account
    ) external view override returns (AccountPosition memory position) {
        AccountState memory aStateCache = allAccountState[account];
        GlobalStateCache memory gStateCache = _globalStateRO();
        LiquidationStatus memory status = _computeLiquidity(aStateCache, gStateCache);

        position.collateral = aStateCache.collateral;
        position.currentDebt = status.currentDebt;
        position.currentLtv = status.currentLtv;
        position.maxOriginationDebtAmount = _maxDebt(aStateCache.collateral, gStateCache.maxOriginationLtv);

        // liquidationLtv [USDS/gOHM] * collateral [gOHM]
        // Round down to get the conservative max debt allowed
        position.liquidationDebtAmount = uint256(gStateCache.liquidationLtv).mulWadDown(position.collateral);

        // healthFactor = liquidationLtv [USDS/gOHM] * collateral [gOHM] / debt [USDS]
        position.healthFactor = position.currentDebt == 0
            ? type(uint256).max
            : uint256(gStateCache.liquidationLtv).mulDivDown(position.collateral, position.currentDebt);

        (
            /*totalGOhm*/ ,
            position.totalDelegated,
            position.numDelegateAddresses,
            position.maxDelegateAddresses
        ) = DLGTE.accountDelegationSummary(account);
    }

    /// @inheritdoc IMonoCooler
    function computeLiquidity(
        address[] calldata accounts
    ) external view override returns (LiquidationStatus[] memory status) {
        uint256 numAccounts = accounts.length;
        status = new LiquidationStatus[](numAccounts);
        GlobalStateCache memory gStateCache = _globalStateRO();
        for (uint256 i; i < numAccounts; ++i) {
            status[i] = _computeLiquidity(allAccountState[accounts[i]], gStateCache);
        }
    }

    /// @inheritdoc IMonoCooler
    function accountDelegationsList(
        address account,
        uint256 startIndex,
        uint256 maxItems
    ) external view override returns (DLGTEv1.AccountDelegation[] memory delegations) {
        return DLGTE.accountDelegationsList(account, startIndex, maxItems);
    }

    /// @inheritdoc IMonoCooler
    function accountState(address account) external view override returns (AccountState memory) {
        return allAccountState[account];
    }

    /// @inheritdoc IMonoCooler
    function accountCollateral(address account) external view override returns (uint128) {
        return allAccountState[account].collateral;
    }

    /// @inheritdoc IMonoCooler
    function accountDebt(address account) external view override returns (uint128) {
        AccountState storage aState = allAccountState[account];
        GlobalStateCache memory gStateCache = _globalStateRO();
        return _currentAccountDebt(
            aState.debtCheckpoint,
            aState.interestAccumulatorRay,
            gStateCache.interestAccumulatorRay,
            true
        );
    }

    /// @inheritdoc IMonoCooler
    function globalState()
        external
        view
        override
        returns (uint128 /*totalDebt*/, uint256 /*interestAccumulatorRay*/)
    {
        GlobalStateCache memory gStateCache = _globalStateRO();
        return (gStateCache.totalDebt, gStateCache.interestAccumulatorRay);
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

        /**
         * @notice The current Liquidation LTV, served from the `ltvOracle`
         */
        uint96 liquidationLtv;

        /**
         * @notice The current Max Origination LTV, served from the `ltvOracle`
         */
        uint96 maxOriginationLtv;
    }

    /**
     * @dev Setup and refresh the global state
     * Update storage if and only if the timestamp has changed since last updated.
     */
    function _globalStateRW() private returns (GlobalStateCache memory gStateCache) {
        if (_initGlobalStateCache(gStateCache)) {
            // If the cache is dirty (increase in time) then write the
            // updated state
            interestAccumulatorUpdatedAt = uint32(block.timestamp);
            totalDebt = gStateCache.totalDebt;
            interestAccumulatorRay = gStateCache.interestAccumulatorRay;
        }
    }

    /**
     * @dev Setup the GlobalStateCache for a given token
     * read only -- storage isn't updated.
     */
    function _globalStateRO() private view returns (GlobalStateCache memory gStateCache) {
        _initGlobalStateCache(gStateCache);
    }

    /**
     * @dev Initialize the global state cache from storage to this block, for a given token.
     */
    function _initGlobalStateCache(
        GlobalStateCache memory gStateCache
    ) private view returns (bool dirty) {
        // Copies from storage
        gStateCache.interestAccumulatorRay = interestAccumulatorRay;
        gStateCache.totalDebt = totalDebt;
        (gStateCache.maxOriginationLtv, gStateCache.liquidationLtv) = ltvOracle.currentLtvs();

        // Only compound if we're on a new block
        uint32 timeElapsed;
        unchecked {
            timeElapsed = uint32(block.timestamp) - interestAccumulatorUpdatedAt;
        }

        if (timeElapsed > 0) {
            dirty = true;

            // Compound the accumulator
            uint256 newInterestAccumulatorRay = gStateCache
                .interestAccumulatorRay
                .continuouslyCompounded(timeElapsed, uint96(interestRateBps) * 1e14);

            // Calculate the latest totalDebt from this
            gStateCache.totalDebt = newInterestAccumulatorRay
                .mulDivUp(gStateCache.totalDebt, gStateCache.interestAccumulatorRay)
                .encodeUInt128();
            gStateCache.interestAccumulatorRay = newInterestAccumulatorRay;
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

        // Pull in the debtToken from the user and deposit into the savings vault,
        // with TRSRY as the receiver
        debtToken.safeTransferFrom(from, address(this), debtTokenAmount);
        debtToken.safeApprove(address(debtSavingsVault), debtTokenAmount);
        debtSavingsVault.deposit(debtTokenAmount, address(TRSRY));
    }

    /**
     * @dev Reduce the total debt in storage by a repayment amount.
     * NB: The sum of all users debt may be slightly more than the recorded total debt
     * because users debt is rounded up for dust.
     * The total debt is floored at 0.
     */
    function _reduceTotalDebt(GlobalStateCache memory gStateCache, uint128 repayAmount) private {
        unchecked {
            totalDebt = gStateCache.totalDebt = repayAmount > gStateCache.totalDebt
                ? 0
                : gStateCache.totalDebt - repayAmount;
        }
    }

    //============================================================================================//
    //                                      INTERNAL HEALTH                                       //
    //============================================================================================//

    /**
     * @dev Calculate the maximum amount which can be borrowed up to the maxOriginationLtv, given
     * a collateral amount
     */
    function _maxDebt(uint128 collateral, uint256 maxOriginationLtv) private pure returns (uint128) {
        // debt [USDS] = maxOriginationLtv [USDS/gOHM] * collateral [gOHM]
        // Round down to get the conservative max debt allowed
        return maxOriginationLtv.mulWadDown(collateral).encodeUInt128();
    }

    /**
     * @dev Calculate the maximum collateral amount which can be withdrawn up to the maxOriginationLtv, given
     * a current debt amount
     */
    function _minCollateral(uint128 debt, uint256 maxOriginationLtv) private pure returns (uint128) {
        // collateral [gOHM] = debt [USDS] / maxOriginationLtv [USDS/gOHM]
        // Round up to get the conservative min collateral allowed
        return uint256(debt).divWadUp(maxOriginationLtv).encodeUInt128();
    }

    /**
     * @dev Ensure the LTV isn't higher than the maxOriginationLtv
     */
    function _validateOriginationLtv(uint256 ltv, uint256 maxOriginationLtv) private pure {
        if (ltv > maxOriginationLtv) {
            revert ExceededMaxOriginationLtv(ltv, maxOriginationLtv);
        }
    }

    /**
     * @dev Calculate the current LTV based on the latest debt
     */
    function _calculateCurrentLtv(
        uint128 currentDebt,
        uint128 collateral
    ) private pure returns (uint256) {
        return
            collateral == 0
                ? type(uint256).max // Represent 'undefined' as max uint256
                : uint256(currentDebt).divWadUp(collateral);
    }

    /**
     * @dev Generate the LiquidationStatus struct with current details
     * for this account.
     */
    function _computeLiquidity(
        AccountState memory aStateCache,
        GlobalStateCache memory gStateCache
    ) private pure returns (LiquidationStatus memory status) {
        status.collateral = aStateCache.collateral;

        // Round the debt up
        status.currentDebt = _currentAccountDebt(
            aStateCache.debtCheckpoint, 
            aStateCache.interestAccumulatorRay, 
            gStateCache.interestAccumulatorRay, 
            true
        );
        status.currentLtv = _calculateCurrentLtv(status.currentDebt, status.collateral);

        status.exceededLiquidationLtv = status.collateral > 0 &&
            status.currentLtv > gStateCache.liquidationLtv;
        status.exceededMaxOriginationLtv =
            status.collateral > 0 &&
            status.currentLtv > gStateCache.maxOriginationLtv;
    }

    //============================================================================================//
    //                                       INTERNAL AUX                                         //
    //============================================================================================//

    /**
     * @dev Calculate the latest debt for a given account & token.
     * Derived from the prior debt checkpoint, and the interest accumulator.
     */
    function _currentAccountDebt(
        uint128 accountDebtCheckpoint_,
        uint256 accountInterestAccumulatorRay_,
        uint256 globalInterestAccumulatorRay_,
        bool roundUp
    ) private pure returns (uint128 result) {
        if (accountDebtCheckpoint_ == 0) return 0;

        // Shortcut if no change.
        if (accountInterestAccumulatorRay_ == globalInterestAccumulatorRay_) {
            return accountDebtCheckpoint_;
        }

        uint256 debt = roundUp
            ? globalInterestAccumulatorRay_.mulDivUp(
                accountDebtCheckpoint_,
                accountInterestAccumulatorRay_
            )
            : globalInterestAccumulatorRay_.mulDivDown(
                accountDebtCheckpoint_,
                accountInterestAccumulatorRay_
            );
        return debt.encodeUInt128();
    }
}


// Add function to get max borrow given an amount of collateral