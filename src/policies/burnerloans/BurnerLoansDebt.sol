// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {BL_ACTION_BORROW, BL_ACTION_EXTEND} from "src/policies/burnerloans/libraries/LoanActions.sol";
import {LoanMarket} from "src/policies/burnerloans/libraries/LoanMarket.sol";
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";
import {LoanSolvency} from "src/policies/burnerloans/libraries/LoanSolvency.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BaseBurnerLoansAction} from "src/policies/burnerloans/abstracts/BaseBurnerLoansAction.sol";

/// @notice User-facing borrowing, repayment and maturity rules; economic calculations are selected through Core.
/// @dev Borrowing and extensions require borrower authority; repayment is permissionless. The actual
///      caller supplies fees and repayments, including when acting as an authorized borrower operator.
contract BurnerLoansDebt is BaseBurnerLoansAction, IBurnerLoansDebt {
    /// @notice Internal fee components passed separately to Core for settlement.
    /// @param protocolFee Protocol allocation, in collateral token decimals.
    /// @param referralFee Referrer allocation, in collateral token decimals.
    struct FeeAllocation {
        uint256 protocolFee;
        uint256 referralFee;
    }

    /// @notice Binds deployment dependencies and initializes the local contract state.
    /// @dev Reverts if:
    ///      - Core does not advertise IBurnerLoansCore and IEnabler through ERC165.
    ///      - Core reports a different Kernel.
    /// @param kernel_ Kernel supplying modules and governance authority.
    /// @param core_ Permanent accounting and DepositManager operator contract.
    constructor(
        Kernel kernel_,
        IBurnerLoansCore core_
    ) BaseBurnerLoansAction(kernel_, core_, BL_DEBT_POLICY_ROLE) {}

    /// @inheritdoc IBurnerLoansDebt
    /// @dev Reverts if:
    ///      - The action or Core is inactive or disabled.
    ///      - The borrower is zero, or the actual caller lacks a current borrower/operator authorization.
    ///      - The amount or recipient is zero.
    ///      - Originations or Inventory are disabled, or custody is insolvent.
    ///      - Collateral is absent or existing debt has matured.
    ///      - The requested principal exceeds the global or asset cap.
    ///      - Prices are unavailable or the current/resulting position is unhealthy.
    ///      - A positive referral allocation names the selected Payout as its recipient.
    ///      - The total fee (protocolFee + referralFee) exceeds maxFee, or mandatory fee/principal settlement fails.
    function borrow(
        address asset_,
        uint128 amount_,
        address borrower_,
        address recipient_,
        uint256 maxFee_,
        address referrer_
    ) external override onlyOperational returns (IBurnerLoansDebt.BorrowPreview memory) {
        IBurnerLoansCore.AuthorizationContext memory authContext = _captureBorrower(
            borrower_,
            BL_ACTION_BORROW
        );
        _validateBorrowInputs(amount_, recipient_);
        IBurnerLoansDebt.BorrowPreview memory result;
        FeeAllocation memory allocation;
        (result, allocation) = _refreshBorrowQuote(asset_, amount_, borrower_, referrer_);
        if (result.fee > maxFee_)
            revert IBurnerLoansDebt.BurnerLoans_FeeExceedsMax(result.fee, maxFee_);
        (uint128 principal, uint48 maturity) = _CORE.settleBorrow(
            IBurnerLoansCore.BorrowRequest({
                asset: asset_,
                borrower: borrower_,
                payer: msg.sender,
                recipient: recipient_,
                amount: amount_,
                maturity: result.maturity,
                protocolFee: allocation.protocolFee,
                referrer: referrer_,
                referralFee: allocation.referralFee
            }),
            msg.sender,
            authContext
        );
        result.resultingDebtOhm = principal;
        result.maturity = maturity;
        emit IBurnerLoansDebt.Borrowed(
            msg.sender,
            asset_,
            borrower_,
            recipient_,
            amount_,
            allocation.protocolFee,
            referrer_,
            allocation.referralFee
        );
        return result;
    }

    /// @notice	Validates borrow exposure and returns the position and resulting maturity.
    /// @dev Reverts if:
    ///      - The market is not configured.
    ///      - Originations are disabled.
    ///      - Inventory is unavailable.
    ///      - DepositManager custody is insolvent.
    ///      - Collateral is absent.
    ///      - An existing debt position has matured.
    ///      - The requested principal exceeds global capacity.
    ///      - The requested principal exceeds the asset debt cap.
    ///      - The initial maturity cannot be represented as uint48.
    ///
    /// @param	asset_	Underlying collateral token identifying the market.
    /// @param	borrower_	Account whose canonical position is queried or changed.
    /// @param	amount_	Token amount in the operation's documented token units.
    /// @return	market	Canonical FLOAN market identifier.
    /// @return	position	Canonical position validated against the exposure limits.
    /// @return	maturity	Resulting maturity timestamp in seconds.
    function _prepareBorrow(
        address asset_,
        address borrower_,
        uint128 amount_
    ) private view returns (uint32 market, IFLOANv1.Position memory position, uint48 maturity) {
        IBurnerLoansCore.AssetConfig memory cfg;
        (market, cfg, ) = LoanMarket.configuration(_CORE, asset_);
        if (!cfg.originationsEnabled)
            revert IBurnerLoansCore.BurnerLoansCore_AssetOriginationsDisabled(asset_);
        IBurnerLoansInventory inventory = IBurnerLoansInventory(_CORE.inventory());
        _requireInventoryOperational();
        LoanSolvency.requireSolvent(
            IDepositManager(_CORE.depositManager()),
            asset_,
            address(_CORE)
        );
        (, , position) = LoanPositions.forCore(_CORE, asset_, borrower_);
        if (position.collateral == 0) revert IBurnerLoansDebt.BurnerLoans_NoCollateral();
        // Chain time defines this maturity/freshness boundary; its equality behavior is intentional.
        // forge-lint: disable-next-line(block-timestamp)
        if (position.principalDue != 0 && block.timestamp >= position.maturity)
            revert IBurnerLoansDebt.BurnerLoans_PositionExpired(position.maturity);
        uint256 globalRoom = inventory.availableCapacity();
        if (amount_ > globalRoom)
            revert IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity(
                amount_,
                globalRoom
            );
        uint256 assetDebt = IFLOANv1(_CORE.floan()).getMarketPrincipalDue(market);
        uint256 room = assetDebt < cfg.debtCap ? cfg.debtCap - assetDebt : 0;
        if (amount_ > room)
            revert IBurnerLoansDebt.BurnerLoans_AssetDebtCapExceeded(asset_, amount_, room);
        // A top-up keeps the current debt episode's deadline; only the first draw starts a term.
        maturity = position.principalDue == 0
            ? SafeCast.toUint48(block.timestamp + cfg.termLength)
            : position.maturity;
    }

    /// @inheritdoc IBurnerLoansDebt
    /// @dev Reverts if:
    ///      - The action or Core is inactive or disabled.
    ///      - The amount or borrower is zero, or Inventory is disabled.
    ///      - The position is absent, debt is zero or repayment exceeds principal.
    ///      - Repayment occurs in the latest borrow block.
    ///      - A partial repayment cannot obtain prices to report resulting health.
    ///      - Exact OHM collection, FLOAN reduction or Inventory settlement fails.
    function repay(
        address asset_,
        uint128 amount_,
        address borrower_
    ) external override onlyOperational returns (uint128 principal, uint256 resultingHealthFactor) {
        IFLOANv1.Position memory position = _quoteRepay(asset_, amount_, borrower_);
        IBurnerLoansRisk evaluator = IBurnerLoansRisk(_CORE.risk());
        IBurnerLoansCore.PriceSnapshot memory snapshot;
        // Clearing all principal needs no price quote. Partial repayment reports health but never
        // requires the borrower to cure an already unhealthy position before reducing debt.
        if (position.principalDue != 0) {
            snapshot = evaluator.refreshSnapshot(asset_);
            // A mutating price refresh can change debt; validate the live position again.
            position = _quoteRepay(asset_, amount_, borrower_);
        }
        resultingHealthFactor = LoanPositions.health(evaluator, snapshot, position);
        principal = _CORE.settleRepay(asset_, amount_, msg.sender, borrower_);
        emit IBurnerLoansDebt.Repaid(msg.sender, asset_, borrower_, amount_, principal);
    }

    /// @notice Advertises this public action interface and the inherited lifecycle interface.
    /// @dev Pure interface identifiers or inherited lifecycle identifiers only; no dependency calls.
    /// @param id_ Canonical interface or position identifier.
    /// @return bool Whether the interface identifier is supported.
    function supportsInterface(bytes4 id_) public view override returns (bool) {
        return id_ == type(IBurnerLoansDebt).interfaceId || super.supportsInterface(id_);
    }

    /// @inheritdoc IBurnerLoansDebt
    /// @dev Permissionless: execution alone authenticates the caller and collects the total fee (protocolFee + referralFee).
    /// @dev Reverts if:
    ///      - Debt or Core is Kernel-inactive or locally disabled.
    ///      - Debt lacks its required Core settlement role.
    ///      - The borrower address is invalid.
    ///      - The market configuration or pricing snapshot is invalid.
    ///      - Originations are disabled.
    ///      - DepositManager custody is insolvent.
    ///      - Risk rejects the referrer or fee calculation.
    ///      - A nonzero total fee requires an unavailable Payout dependency.
    ///      - A positive referral allocation names the selected Payout as its recipient.
    ///      - The total fee (protocolFee + referralFee) exceeds maxFee_.
    ///      - The amount is zero.
    ///      - The recipient is invalid.
    ///      - Inventory is unavailable.
    ///      - The borrower has no collateral.
    ///      - An existing debt position has matured.
    ///      - The requested principal exceeds global capacity.
    ///      - The requested principal exceeds the asset debt cap.
    ///      - The current or resulting position fails its required health threshold.
    ///      - The resulting maturity cannot be represented as uint48.
    function previewBorrow(
        address asset_,
        uint128 amount_,
        address onBehalfOf_,
        address recipient_,
        uint256 maxFee_,
        address referrer_
    ) external view override returns (IBurnerLoansDebt.BorrowPreview memory result) {
        _requirePreviewOperational();
        _validateBorrower(onBehalfOf_);
        _validateBorrowInputs(amount_, recipient_);
        (result, ) = _quoteBorrow(
            asset_,
            amount_,
            onBehalfOf_,
            IBurnerLoansRisk(_CORE.risk()).snapshot(asset_),
            referrer_
        );
        if (result.fee > maxFee_)
            revert IBurnerLoansDebt.BurnerLoans_FeeExceedsMax(result.fee, maxFee_);
    }

    /// @notice Quotes remaining principal and resulting health for a repayment.
    /// @param asset_ Configured collateral token identifying the borrower's market.
    /// @param amount_ Principal to repay, in OHM units.
    /// @param borrower_ Account whose principal would be reduced.
    /// @return remainingPrincipal Outstanding principal after repayment, in OHM units.
    /// @return resultingHealthFactor WAD-scaled health, or uint256.max for full repayment.
    /// @dev Reverts if:
    ///      - An operation was requested with a zero token amount.
    ///      - This contract or a required dependency is disabled.
    ///      - The borrower has no collateral position for the asset.
    ///      - The borrower has no outstanding debt for the asset.
    ///      - A repayment exceeds the borrower's outstanding principal.
    ///      - A repayment was attempted in the same block as the position's latest borrow.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function previewRepay(
        address asset_,
        uint128 amount_,
        address borrower_
    ) external view override returns (uint128 remainingPrincipal, uint256 resultingHealthFactor) {
        _requirePreviewOperational();
        IFLOANv1.Position memory position = _quoteRepay(asset_, amount_, borrower_);
        remainingPrincipal = position.principalDue;
        IBurnerLoansRisk evaluator = IBurnerLoansRisk(_CORE.risk());
        IBurnerLoansCore.PriceSnapshot memory snapshot;
        if (remainingPrincipal != 0) snapshot = evaluator.snapshot(asset_);
        resultingHealthFactor = LoanPositions.health(evaluator, snapshot, position);
    }

    /// @inheritdoc IBurnerLoansDebt
    /// @dev Reverts if:
    ///      - The action or Core is inactive or disabled.
    ///      - The borrower is zero, or the actual caller lacks a current borrower/operator authorization.
    ///      - The number of terms is zero or originations are disabled.
    ///      - Debt is absent or custody is insolvent.
    ///      - Resulting maturity is not in the future or exceeds the configured horizon.
    ///      - Prices are unavailable or the position is unhealthy.
    ///      - A positive referral allocation names the selected Payout as its recipient.
    ///      - The total fee (protocolFee + referralFee) exceeds maxFee or mandatory collection/settlement fails.
    function extend(
        address asset_,
        address borrower_,
        uint16 terms_,
        uint256 maxFee_,
        address referrer_
    ) external override onlyOperational returns (IBurnerLoansDebt.ExtendPreview memory result) {
        IBurnerLoansCore.AuthorizationContext memory authContext = _captureBorrower(
            borrower_,
            BL_ACTION_EXTEND
        );
        if (terms_ == 0) revert IBurnerLoansCore.BurnerLoansCore_ZeroAmount();
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansRisk(_CORE.risk())
            .refreshSnapshot(asset_);
        FeeAllocation memory allocation;
        (result, allocation) = _quoteExtend(asset_, borrower_, terms_, snapshot, referrer_);
        if (result.fee > maxFee_)
            revert IBurnerLoansDebt.BurnerLoans_FeeExceedsMax(result.fee, maxFee_);
        result.maturity = _CORE.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: asset_,
                borrower: borrower_,
                payer: msg.sender,
                maturity: result.maturity,
                protocolFee: allocation.protocolFee,
                referrer: referrer_,
                referralFee: allocation.referralFee
            }),
            msg.sender,
            authContext
        );
        emit IBurnerLoansDebt.Extended(
            msg.sender,
            asset_,
            borrower_,
            result.maturity,
            allocation.protocolFee,
            referrer_,
            allocation.referralFee
        );
    }

    /// @inheritdoc IBurnerLoansDebt
    /// @dev Permissionless: execution alone authenticates the caller and collects the total fee (protocolFee + referralFee).
    /// @dev Reverts if:
    ///      - Debt or Core is Kernel-inactive or locally disabled.
    ///      - Debt lacks its required Core settlement role.
    ///      - The borrower address is invalid.
    ///      - The market configuration or pricing snapshot is invalid.
    ///      - Originations are disabled.
    ///      - DepositManager custody is insolvent.
    ///      - Risk rejects the referrer or fee calculation.
    ///      - A nonzero total fee requires an unavailable Payout dependency.
    ///      - A positive referral allocation names the selected Payout as its recipient.
    ///      - The total fee (protocolFee + referralFee) exceeds maxFee_.
    ///      - The number of terms is zero.
    ///      - The borrower has no debt.
    ///      - The resulting maturity is not in the future.
    ///      - The resulting maturity exceeds the permitted horizon.
    ///      - The position fails its required health threshold.
    function previewExtend(
        address asset_,
        address onBehalfOf_,
        uint16 terms_,
        uint256 maxFee_,
        address referrer_
    ) external view override returns (IBurnerLoansDebt.ExtendPreview memory result) {
        _requirePreviewOperational();
        _validateBorrower(onBehalfOf_);
        if (terms_ == 0) revert IBurnerLoansCore.BurnerLoansCore_ZeroAmount();
        (result, ) = _quoteExtend(
            asset_,
            onBehalfOf_,
            terms_,
            IBurnerLoansRisk(_CORE.risk()).snapshot(asset_),
            referrer_
        );
        if (result.fee > maxFee_)
            revert IBurnerLoansDebt.BurnerLoans_FeeExceedsMax(result.fee, maxFee_);
    }

    /// @notice Rechecks the direct funding/default service before enabling this action.
    /// @dev Reverts if:
    ///      - The shared activation checks or Inventory readiness fails.
    function _validateActivation() internal view override {
        super._validateActivation();
        _requireInventoryOperational();
    }

    /// @notice Validates public borrowing inputs before any price refresh or settlement.
    /// @dev Reverts if:
    ///      - The amount or address is zero, or the output destination is internal.
    /// @param amount_ Requested OHM principal in native OHM units.
    /// @param recipient_ Account receiving the principal.
    function _validateBorrowInputs(uint128 amount_, address recipient_) private view {
        if (amount_ == 0) revert IBurnerLoansCore.BurnerLoansCore_ZeroAmount();
        if (recipient_ == address(0)) revert IBurnerLoansErrors.BurnerLoans_ZeroAddress();
        if (
            recipient_ == address(this) ||
            recipient_ == address(_CORE) ||
            recipient_ == _CORE.payout()
        ) revert IBurnerLoansErrors.BurnerLoans_InvalidParam();
    }

    /// @notice Shared borrow validation for execution and preview using the operation's snapshot.
    /// @dev Reverts if:
    ///      - Exposure is unsupported or custody is insolvent.
    ///      - The current or final position is unhealthy.
    /// @param asset_ Configured underlying collateral asset.
    /// @param amount_ Requested OHM principal in native OHM units.
    /// @param borrower_ Borrower whose canonical position is evaluated.
    /// @param snapshot_ Prices captured once for this operation, in PRICE decimals.
    /// @param referrer_ Recipient used by Risk for this operation's fee allocation.
    /// @return result Total fee (protocolFee + referralFee), resulting principal, expiry and WAD health.
    /// @return allocation Separate protocol and referral fees for internal settlement.
    function _quoteBorrow(
        address asset_,
        uint128 amount_,
        address borrower_,
        IBurnerLoansCore.PriceSnapshot memory snapshot_,
        address referrer_
    )
        private
        view
        returns (IBurnerLoansDebt.BorrowPreview memory result, FeeAllocation memory allocation)
    {
        uint32 market;
        IFLOANv1.Position memory position;
        (market, position, result.maturity) = _prepareBorrow(asset_, borrower_, amount_);
        IBurnerLoansRisk evaluator = IBurnerLoansRisk(_CORE.risk());
        // This validates the existing position; final health is quoted separately below.
        // This multiline operation needs a range; the suppression ends immediately after it.
        // forge-lint: disable-start(unused-return)
        evaluator.validateHealth(
            snapshot_,
            market,
            position.collateral,
            position.principalDue,
            false
        );
        // forge-lint: disable-end(unused-return)
        result.resultingDebtOhm = uint256(position.principalDue) + amount_;
        result.resultingHealthFactor = evaluator.validateHealth(
            snapshot_,
            market,
            position.collateral,
            result.resultingDebtOhm,
            true
        );
        (allocation.protocolFee, allocation.referralFee) = evaluator.fee(
            snapshot_,
            market,
            amount_,
            1,
            referrer_
        );
        result.fee = allocation.protocolFee + allocation.referralFee;
        // A zero-fee operation creates no payout obligation, so Payout availability is irrelevant.
        _requireFeePayoutOperational(allocation, referrer_);
    }

    /// @notice Refreshes one operation-local snapshot before quoting the borrow.
    /// @dev Reverts if snapshot refresh or the ordinary borrow quote checks fail. The caller
    ///      captures authorization first. Resolve Risk and FLOAN again inside _quoteBorrow after
    ///      the mutable refresh, so callbacks cannot leave a cached economic dependency or position.
    /// @param asset_ Configured underlying collateral asset.
    /// @param amount_ Requested principal in raw 9-decimal OHM units.
    /// @param borrower_ Account whose canonical position is evaluated.
    /// @param referrer_ Recipient used by Risk to allocate this operation's fee.
    /// @return Borrow fee, maturity, resulting principal and health.
    /// @return Separate protocol and referral fee allocations.
    function _refreshBorrowQuote(
        address asset_,
        uint128 amount_,
        address borrower_,
        address referrer_
    ) private returns (IBurnerLoansDebt.BorrowPreview memory, FeeAllocation memory) {
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansRisk(_CORE.risk())
            .refreshSnapshot(asset_);
        return _quoteBorrow(asset_, amount_, borrower_, snapshot, referrer_);
    }

    /// @notice Shared extension validation; Inventory is not consumed by this operation.
    /// @dev Reverts if:
    ///      - Debt is absent or originations are disabled.
    ///      - Custody is insolvent, expiry is invalid or debt is unhealthy.
    /// @param asset_ Configured underlying collateral asset.
    /// @param borrower_ Borrower whose canonical position is evaluated.
    /// @param terms_ Whole configured terms added to the stored expiry.
    /// @param snapshot_ Prices captured once for this operation, in PRICE decimals.
    /// @param referrer_ Recipient used by Risk for this operation's fee allocation.
    /// @return result Total fee (protocolFee + referralFee), resulting expiry and WAD health.
    /// @return allocation Separate protocol and referral fees for internal settlement.
    function _quoteExtend(
        address asset_,
        address borrower_,
        uint16 terms_,
        IBurnerLoansCore.PriceSnapshot memory snapshot_,
        address referrer_
    )
        private
        view
        returns (IBurnerLoansDebt.ExtendPreview memory result, FeeAllocation memory allocation)
    {
        uint32 market;
        IFLOANv1.Position memory position;
        (market, position, result.maturity) = _prepareExtend(asset_, borrower_, terms_);
        IBurnerLoansRisk evaluator = IBurnerLoansRisk(_CORE.risk());
        result.healthFactor = evaluator.validateHealth(
            snapshot_,
            market,
            position.collateral,
            position.principalDue,
            false
        );
        (allocation.protocolFee, allocation.referralFee) = evaluator.fee(
            snapshot_,
            market,
            position.principalDue,
            terms_,
            referrer_
        );
        result.fee = allocation.protocolFee + allocation.referralFee;
        _requireFeePayoutOperational(allocation, referrer_);
    }

    /// @notice Resolves the extension position and validates its absolute maturity.
    /// @dev Reverts in the existing order for disabled originations, insolvent custody, absent
    ///      debt, a maturity not in the future, or a maturity beyond the configured horizon.
    ///      Return the market already resolved by configuration for subsequent health/fee checks.
    /// @param asset_ Configured underlying collateral asset.
    /// @param borrower_ Account whose canonical debt position is evaluated.
    /// @param terms_ Whole configured terms added to the stored maturity.
    /// @return market Canonical FLOAN market identifier.
    /// @return position Current canonical debt position, read after any external snapshot refresh.
    /// @return maturity Validated resulting absolute maturity timestamp in seconds.
    function _prepareExtend(
        address asset_,
        address borrower_,
        uint16 terms_
    ) private view returns (uint32 market, IFLOANv1.Position memory position, uint48 maturity) {
        IBurnerLoansCore.AssetConfig memory cfg;
        (market, cfg, ) = LoanMarket.configuration(_CORE, asset_);
        if (!cfg.originationsEnabled)
            revert IBurnerLoansCore.BurnerLoansCore_AssetOriginationsDisabled(asset_);
        LoanSolvency.requireSolvent(
            IDepositManager(_CORE.depositManager()),
            asset_,
            address(_CORE)
        );
        (, , position) = LoanPositions.forCore(_CORE, asset_, borrower_);
        if (position.principalDue == 0) revert IBurnerLoansCore.BurnerLoansCore_NoDebt();
        // Extend from the stored deadline, not from now. An expired loan may be extended only if
        // the purchased terms reach the future and stay within the horizon measured from now.
        uint256 nextMaturity = uint256(position.maturity) + uint256(cfg.termLength) * terms_;
        // Chain time defines this maturity/freshness boundary; its equality behavior is intentional.
        // forge-lint: disable-next-line(block-timestamp)
        if (nextMaturity <= block.timestamp)
            revert IBurnerLoansDebt.BurnerLoans_ExtensionMaturityNotFuture(
                nextMaturity,
                block.timestamp
            );
        uint256 maximum = block.timestamp + uint256(cfg.maxMaturityHorizon);
        // Chain time defines this maturity/freshness boundary; its equality behavior is intentional.
        // forge-lint: disable-next-line(block-timestamp)
        if (maximum > type(uint48).max) maximum = type(uint48).max;
        // Chain time defines this maturity/freshness boundary; its equality behavior is intentional.
        // forge-lint: disable-next-line(block-timestamp)
        if (nextMaturity > maximum)
            revert IBurnerLoansDebt.BurnerLoans_MaturityHorizonExceeded(nextMaturity, maximum);
        maturity = SafeCast.toUint48(nextMaturity);
    }

    /// @notice Validates the payout service and referral destination shared by quotes and execution.
    /// @dev Zero allocations require no payout service or destination admission.
    /// @dev Reverts if:
    ///      - The selected Payout for a positive allocation is inactive, paused or uses another Kernel.
    ///      - Payout rejects a positive referral allocation's recipient.
    /// @param allocation_ Risk-approved protocol and referral fees in raw collateral units.
    /// @param referrer_ Fixed recipient of the referral allocation.
    function _requireFeePayoutOperational(
        FeeAllocation memory allocation_,
        address referrer_
    ) private view {
        if (allocation_.protocolFee == 0 && allocation_.referralFee == 0) return;
        _requirePayoutOperational();
        if (allocation_.referralFee != 0)
            IBurnerLoansPayout(_CORE.payout()).validatePayoutRecipient(referrer_);
    }

    /// @notice Quotes a repayment position against the current principal and latest borrow block.
    /// @dev Reverts if:
    ///      - The input is zero, Inventory is unavailable or collateral is absent.
    ///      - Repayment exceeds debt or occurs in the same block as borrowing.
    /// @param asset_ Configured underlying collateral asset.
    /// @param amount_ OHM principal repaid in native OHM units.
    /// @param borrower_ Borrower whose canonical position is evaluated.
    /// @return position Projected canonical position after subtracting the requested principal.
    function _quoteRepay(
        address asset_,
        uint128 amount_,
        address borrower_
    ) private view returns (IFLOANv1.Position memory position) {
        if (amount_ == 0) revert IBurnerLoansCore.BurnerLoansCore_ZeroAmount();
        if (borrower_ == address(0)) revert IBurnerLoansErrors.BurnerLoans_ZeroAddress();
        _requireInventoryOperational();
        bool exists;
        (exists, , position) = LoanPositions.forCore(_CORE, asset_, borrower_);
        if (!exists) revert IBurnerLoansDebt.BurnerLoans_NoCollateral();
        if (amount_ > position.principalDue)
            revert IBurnerLoansDebt.BurnerLoans_RepayExceedsDebt(amount_, position.principalDue);
        if (block.number <= position.lastBorrowBlock)
            revert IBurnerLoansDebt.BurnerLoans_SameBlockRepay(position.lastBorrowBlock);
        position.principalDue -= amount_;
    }
}
