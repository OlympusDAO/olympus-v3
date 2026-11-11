// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_COLLATERAL_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {BL_ACTION_DEPOSIT, BL_ACTION_WITHDRAW} from "src/policies/burnerloans/libraries/LoanActions.sol";
import {LoanCustody} from "src/policies/burnerloans/libraries/LoanCustody.sol";
import {LoanMarket} from "src/policies/burnerloans/libraries/LoanMarket.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BaseBurnerLoansAction} from "src/policies/burnerloans/abstracts/BaseBurnerLoansAction.sol";

/// @notice User-facing collateral rules; Core alone moves funds and updates positions.
/// @dev This action validates borrower authority and collateral health. Core moves tokens and records
///      DepositManager's actual credit in FLOAN; previews can only estimate that credit without a deposit.
contract BurnerLoansCollateral is BaseBurnerLoansAction, IBurnerLoansCollateral {
    /// @notice Binds deployment dependencies and initializes the local contract state.
    /// @dev Reverts if:
    ///      - Core does not advertise IBurnerLoansCore and IEnabler through ERC165.
    ///      - Core reports a different Kernel.
    /// @param kernel_ Kernel supplying modules and governance authority.
    /// @param core_ Permanent accounting and DepositManager operator contract.
    constructor(
        Kernel kernel_,
        IBurnerLoansCore core_
    ) BaseBurnerLoansAction(kernel_, core_, BL_COLLATERAL_POLICY_ROLE) {}

    /// @inheritdoc IBurnerLoansCollateral
    /// @dev Reverts if:
    ///      - The action or Core is inactive or disabled.
    ///      - The borrower is zero, or the actual caller lacks a current borrower/operator authorization.
    ///      - The amount is zero.
    ///      - The market is unregistered.
    ///      - DepositManager or Core’s deposit period is unavailable.
    ///      - The amount is below the configured minimum or actual credit exceeds the deposit cap.
    ///      - A transfer, receipt approval, vault deposit or FLOAN credit fails.
    ///      - Actual credit is zero or exceeds uint128.
    function depositCollateral(
        address asset_,
        uint128 amount_,
        address borrower_
    )
        external
        override
        onlyOperational
        returns (uint128 credit, uint128 collateral, uint256 resultingHealthFactor)
    {
        IBurnerLoansCore.AuthorizationContext memory authContext = _captureBorrower(
            borrower_,
            BL_ACTION_DEPOSIT
        );
        IFLOANv1.Position memory beforePosition = _validateDeposit(asset_, amount_, borrower_);
        IBurnerLoansRisk evaluator = IBurnerLoansRisk(_CORE.risk());
        IBurnerLoansCore.PriceSnapshot memory snapshot;
        if (beforePosition.principalDue != 0) snapshot = evaluator.refreshSnapshot(asset_);
        (credit, collateral) = _CORE.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: asset_,
                amount: amount_,
                payer: msg.sender,
                borrower: borrower_
            }),
            msg.sender,
            authContext
        );
        (, , IFLOANv1.Position memory afterPosition) = LoanPositions.forCore(
            _CORE,
            asset_,
            borrower_
        );
        // Helpful deposits may leave health below one. Report actual credit without imposing a cure threshold.
        resultingHealthFactor = LoanPositions.health(evaluator, snapshot, afterPosition);
        emit IBurnerLoansCollateral.CollateralDeposited(
            msg.sender,
            asset_,
            borrower_,
            amount_,
            credit
        );
    }

    /// @inheritdoc IBurnerLoansCollateral
    /// @dev Reverts if:
    ///      - The action or Core is inactive or disabled.
    ///      - The borrower is zero, or the actual caller lacks a current borrower/operator authorization.
    ///      - The amount is zero or exceeds recorded collateral.
    ///      - The recipient is zero, Core or selected Custody.
    ///      - A debt-bearing position cannot obtain valid prices.
    ///      - FLOAN debit, DepositManager redemption or the output transfer fails.
    ///      - Actual output is zero or the output token is unexpected.
    ///      - The actual remaining debt-bearing position is unhealthy.
    function withdrawCollateral(
        address asset_,
        uint128 amount_,
        address borrower_,
        address recipient_
    )
        external
        override
        onlyOperational
        returns (IBurnerLoansCollateral.WithdrawPreview memory result)
    {
        IBurnerLoansCore.AuthorizationContext memory authContext = _captureBorrower(
            borrower_,
            BL_ACTION_WITHDRAW
        );
        IFLOANv1.Position memory position = _validateWithdrawal(
            asset_,
            amount_,
            borrower_,
            recipient_
        );
        IBurnerLoansRisk evaluator = IBurnerLoansRisk(_CORE.risk());
        IBurnerLoansCore.PriceSnapshot memory snapshot;
        // Debt-free exits remain available during price/cache outages.
        if (position.principalDue != 0) snapshot = evaluator.refreshSnapshot(asset_);
        uint128 remaining;
        (result.returnToken, result.returnAmount, remaining) = _CORE.settleWithdraw(
            IBurnerLoansCore.WithdrawRequest({
                asset: asset_,
                amount: amount_,
                borrower: borrower_,
                recipient: recipient_
            }),
            msg.sender,
            authContext
        );
        // Validate actual post-settlement state with the operation's captured prices. Failure
        // reverts Core's collateral debit, DepositManager redemption and recipient transfer.
        (, , position) = LoanPositions.forCore(_CORE, asset_, borrower_);
        position.collateral = remaining;
        result.resultingHealthFactor = LoanPositions.validateFinalHealth(
            evaluator,
            snapshot,
            position
        );
        result.remainingDepositedCollateral = remaining;
        emit IBurnerLoansCollateral.CollateralWithdrawn(
            msg.sender,
            asset_,
            borrower_,
            recipient_,
            amount_,
            result.returnToken,
            result.returnAmount
        );
    }

    /// @notice Advertises this public action interface and the inherited lifecycle interface.
    /// @dev Pure interface identifiers or inherited lifecycle identifiers only; no dependency calls.
    /// @param id_ Canonical interface or position identifier.
    /// @return bool Whether the interface identifier is supported.
    function supportsInterface(bytes4 id_) public view override returns (bool) {
        return id_ == type(IBurnerLoansCollateral).interfaceId || super.supportsInterface(id_);
    }

    /// @inheritdoc IBurnerLoansCollateral
    /// @dev Permissionless. Retains borrower/input, action/Core admission, settlement role,
    ///      custody, minimum-credit, overflow and health checks. Quotes do not
    ///      authenticate the viewer or check a prospective payer's balances or approvals.
    function previewDepositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    )
        external
        view
        override
        returns (uint256 credit, uint256 collateral, uint256 resultingHealthFactor)
    {
        _requirePreviewOperational();
        _validateBorrower(onBehalfOf_);
        IFLOANv1.Position memory p = _validateDeposit(asset_, amount_, onBehalfOf_);
        uint128 credited = LoanCustody.previewDepositAmount(
            IDepositManager(_CORE.depositManager()),
            asset_,
            amount_
        );
        if (credited == 0) revert IBurnerLoansCore.BurnerLoansCore_ZeroCollateralCredit();
        credit = credited;
        // Match FLOAN's checked uint128 addition, including its overflow error.
        p.collateral += credited;
        collateral = p.collateral;
        IBurnerLoansRisk evaluator = IBurnerLoansRisk(_CORE.risk());
        IBurnerLoansCore.PriceSnapshot memory snapshot;
        if (p.principalDue != 0) snapshot = evaluator.snapshot(asset_);
        resultingHealthFactor = LoanPositions.health(evaluator, snapshot, p);
    }

    /// @notice	Validates shared deposit inputs and returns the canonical position.
    /// @dev Reverts if:
    ///      - The amount is zero.
    ///      - The market is unregistered.
    ///      - Custody support is unavailable.
    ///      - The amount is below the configured minimum.
    ///
    /// @dev Collateral-only deposits do not require originations.
    ///
    /// @param	asset_	Underlying collateral token identifying the market.
    /// @param	amount_	Requested deposit in native asset units.
    /// @param	borrower_	Account whose canonical position receives collateral.
    /// @return	position	Existing canonical position or an empty position for a new borrower.
    function _validateDeposit(
        address asset_,
        uint128 amount_,
        address borrower_
    ) private view returns (IFLOANv1.Position memory position) {
        if (amount_ == 0) revert IBurnerLoansCore.BurnerLoansCore_ZeroAmount();
        LoanMarket.configuration(_CORE, asset_);
        (, , position) = LoanPositions.forCore(_CORE, asset_, borrower_);
        PolicyDependency.requireActive(_CORE.depositManager(), address(kernel));
        IDepositManager.AssetConfiguration memory payout = LoanCustody.validateCustodySupportFor(
            IDepositManager(_CORE.depositManager()),
            asset_,
            LoanParameters._DEPOSIT_PERIOD,
            true,
            address(_CORE)
        );
        LoanCustody.validateMinimumDeposit(asset_, payout, amount_);
    }

    /// @inheritdoc IBurnerLoansCollateral
    /// @dev Permissionless. Retains nonzero borrower, amount/recipient, action/Core admission,
    ///      settlement role, custody-exit and health checks. Execution validates actual
    ///      post-settlement health and separately authenticates its caller.
    function previewWithdrawCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_,
        address recipient_
    ) external view override returns (IBurnerLoansCollateral.WithdrawPreview memory result) {
        _requirePreviewOperational();
        _validateBorrower(onBehalfOf_);
        IFLOANv1.Position memory p = _validateWithdrawal(asset_, amount_, onBehalfOf_, recipient_);
        (, IBurnerLoansCore.AssetConfig memory cfg, ) = LoanMarket.configuration(_CORE, asset_);
        p.collateral -= amount_;
        result.remainingDepositedCollateral = p.collateral;
        IBurnerLoansRisk evaluator = IBurnerLoansRisk(_CORE.risk());
        IBurnerLoansCore.PriceSnapshot memory snapshot;
        if (p.principalDue != 0) snapshot = evaluator.snapshot(asset_);
        result.resultingHealthFactor = LoanPositions.validateFinalHealth(evaluator, snapshot, p);
        (result.returnToken, result.returnAmount) = LoanCustody.previewWithdrawAmount(
            IDepositManager(_CORE.depositManager()),
            asset_,
            amount_,
            cfg.withdrawAsShares
        );
        if (result.returnAmount == 0)
            revert IBurnerLoansCore.BurnerLoansCore_ZeroCollateralWithdrawal();
    }

    /// @notice	Validates withdrawal inputs before any mutating price refresh.
    /// @dev Reverts if:
    ///      - The amount is zero.
    ///      - The recipient is zero or an internal protocol address.
    ///      - The market is unregistered.
    ///      - The amount exceeds recorded collateral.
    ///      - DepositManager or the configured period cannot support the withdrawal.
    ///
    /// @dev Configured periods disabled for new deposits still permit exits. Dependency errors propagate.
    ///
    /// @param	asset_	Underlying collateral token identifying the market.
    /// @param	amount_	Requested collateral debit in native asset units.
    /// @param	borrower_	Account whose canonical position supplies collateral.
    /// @param	recipient_	Final recipient of the withdrawn tokens.
    /// @return	position	Canonical position before withdrawal.
    function _validateWithdrawal(
        address asset_,
        uint128 amount_,
        address borrower_,
        address recipient_
    ) private view returns (IFLOANv1.Position memory position) {
        if (amount_ == 0) revert IBurnerLoansCore.BurnerLoansCore_ZeroAmount();
        if (recipient_ == address(0)) revert IBurnerLoansErrors.BurnerLoans_ZeroAddress();
        // Internal balances may back separate payout obligations or be treated as recoverable surplus.
        if (
            recipient_ == address(_CORE) ||
            recipient_ == _CORE.payout() ||
            recipient_ == address(this)
        ) revert IBurnerLoansErrors.BurnerLoans_InvalidRecipient(recipient_);
        (, , position) = LoanPositions.forCore(_CORE, asset_, borrower_);
        if (amount_ > position.collateral)
            revert IBurnerLoansCollateral.BurnerLoans_InsufficientCollateral(
                amount_,
                position.collateral
            );
        LoanCustody.validateWithdrawalSupport(_CORE, asset_, address(kernel));
    }
}
