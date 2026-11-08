// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;
// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {BL_LIQUIDATION_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {LoanCustody} from "src/policies/burnerloans/libraries/LoanCustody.sol";
import {LoanMarket} from "src/policies/burnerloans/libraries/LoanMarket.sol";
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";
import {LoanSolvency} from "src/policies/burnerloans/libraries/LoanSolvency.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BaseBurnerLoansAction} from "src/policies/burnerloans/abstracts/BaseBurnerLoansAction.sol";

/// @notice Permissionless bounded liquidation entry point; settlement and payouts remain at Core.
/// @dev Anyone may identify eligible debt. This action validates every borrower against one price
///      snapshot; Core then defaults the batch, redeems collateral and credits the resulting payouts.
contract BurnerLoansSeize is BaseBurnerLoansAction, IBurnerLoansSeize {
    /// @notice Binds deployment dependencies and initializes the local contract state.
    /// @dev Reverts if:
    ///      - Core does not advertise IBurnerLoansCore and IEnabler through ERC165.
    ///      - Core reports a different Kernel.
    /// @param kernel_ Kernel supplying modules and governance authority.
    /// @param core_ Permanent accounting and DepositManager operator contract.
    constructor(
        Kernel kernel_,
        IBurnerLoansCore core_
    ) BaseBurnerLoansAction(kernel_, core_, BL_LIQUIDATION_POLICY_ROLE) {}

    /// @inheritdoc IBurnerLoansSeize
    /// @dev Reverts if:
    ///      - The action or Core is inactive or disabled, or Inventory is disabled.
    ///      - The batch is empty.
    ///      - A borrower is zero, duplicated or has no debt.
    ///      - A position is healthy and has not matured.
    ///      - Prices are unavailable or custody is insolvent.
    ///      - A positive keeper reward names zero or the selected Payout as its recipient.
    ///      - Core’s atomic default, redemption, receipt validation or payout credit fails.
    function seize(
        address asset_,
        address[] calldata borrowers_
    ) external override onlyOperational returns (address, uint256, uint256) {
        if (borrowers_.length == 0) revert IBurnerLoansSeize.BurnerLoans_InvalidBatch();
        _requireInventoryOperational();
        _requirePayoutOperational();
        IBurnerLoansRisk evaluator = IBurnerLoansRisk(_CORE.risk());
        IBurnerLoansCore.PriceSnapshot memory snapshot = evaluator.refreshSnapshot(asset_);
        // Admit the complete batch before the first default. One ineligible borrower rejects the
        // entire request instead of leaving the keeper with a partially executed selection.
        _validatePositions(evaluator, snapshot, asset_, borrowers_);
        IBurnerLoansCore.SeizePreview memory result = _CORE.settleSeize(
            asset_,
            borrowers_,
            msg.sender,
            snapshot
        );
        return (result.tokenOut, result.keeperReward, result.collateralToTreasury);
    }

    /// @notice Advertises this public action interface and the inherited lifecycle interface.
    /// @dev Pure interface identifiers or inherited lifecycle identifiers only; no dependency calls.
    /// @param id_ Canonical interface or position identifier.
    /// @return bool Whether the interface identifier is supported.
    function supportsInterface(bytes4 id_) public view override returns (bool) {
        return id_ == type(IBurnerLoansSeize).interfaceId || super.supportsInterface(id_);
    }

    /// @notice Quotes custody output and its keeper/Treasury allocation.
    /// @dev Reverts if:
    ///      - Custody withdrawal support or output preview fails.
    ///      - Reward eligibility or Risk's reward calculation fails.
    ///      - Risk allocates a reward larger than the quoted output.
    ///      - A positive keeper reward names zero or the selected Payout as its recipient.
    /// @param evaluator_ Risk implementation using the captured snapshot.
    /// @param snapshot_ Captured operation price/backing values, all in the same PRICE decimal scale.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param actor_ Keeper identity used to select protocol-caller rewards.
    /// @param result_ Aggregated batch debt, collateral and output allocation.
    /// @return IBurnerLoansCore.SeizePreview Batch amounts and output allocation calculated from selected positions.
    function _allocate(
        IBurnerLoansRisk evaluator_,
        IBurnerLoansCore.PriceSnapshot memory snapshot_,
        address asset_,
        address actor_,
        IBurnerLoansCore.SeizePreview memory result_
    ) private view returns (IBurnerLoansCore.SeizePreview memory) {
        LoanCustody.validateWithdrawalSupport(_CORE, asset_, address(kernel));
        uint256 output;
        (, IBurnerLoansCore.AssetConfig memory cfg, ) = LoanMarket.configuration(_CORE, asset_);
        (result_.tokenOut, output) = LoanCustody.previewWithdrawAmount(
            IDepositManager(_CORE.depositManager()),
            asset_,
            result_.seizedCollateral,
            cfg.withdrawAsShares
        );
        // Reward eligibility belongs to actor_, not the account asking for this preview. Protocol
        // tasks can therefore quote their own zero-reward execution without impersonating the caller.
        bool protocolCaller = _hasRole(actor_, BURNER_LOANS_SEIZER_ROLE) ||
            _hasRole(actor_, HEART_ROLE);
        result_.keeperReward = evaluator_.keeperReward(
            snapshot_,
            _CORE.marketId(asset_),
            result_.seizedDebtOhm,
            result_.seizedCollateral,
            output,
            protocolCaller
        );
        if (result_.keeperReward > output)
            revert IBurnerLoansCore.BurnerLoansCore_InvalidSettlement();
        if (result_.keeperReward != 0)
            IBurnerLoansPayout(_CORE.payout()).validatePayoutRecipient(actor_);
        result_.collateralToTreasury = output - result_.keeperReward;
        return result_;
    }

    /// @notice Quotes a bounded liquidation batch for an explicit keeper.
    /// @dev Reverts if:
    ///      - A batch is empty.
    ///      - This contract or a required dependency is disabled.
    ///      - A required address is zero.
    ///      - A borrower appears more than once in a seizure batch.
    ///      - A borrower has no debt or is healthy and unexpired.
    ///      - Custody is unavailable or insolvent, or pricing is unavailable, including an entirely expired batch.
    ///      - Risk allocates a reward larger than the quoted output.
    ///      - A positive keeper reward names zero or the selected Payout as its recipient.
    ///      Reads without state changes; errors from dependency views propagate.
    /// @param actor_ Keeper identity used to select protocol-caller rewards.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param borrowers_ Borrowers included in the bounded liquidation batch.
    /// @return result Batch debt/collateral, output and keeper/Treasury distribution estimates.
    function previewSeizeFor(
        address actor_,
        address asset_,
        address[] calldata borrowers_
    ) external view override returns (IBurnerLoansCore.SeizePreview memory result) {
        _requirePreviewOperational();
        if (borrowers_.length == 0) revert IBurnerLoansSeize.BurnerLoans_InvalidBatch();
        _requireInventoryOperational();
        _requirePayoutOperational();
        LoanSolvency.requireSolvent(
            IDepositManager(_CORE.depositManager()),
            asset_,
            address(_CORE)
        );
        IBurnerLoansRisk evaluator = IBurnerLoansRisk(_CORE.risk());
        IBurnerLoansCore.PriceSnapshot memory snapshot = evaluator.snapshot(asset_);
        _validateBorrowers(borrowers_);
        IFLOANv1 floan = IFLOANv1(_CORE.floan());
        uint32 market = _CORE.marketId(asset_);
        for (uint256 i; i < borrowers_.length; ++i) {
            IFLOANv1.Position memory p = _validateSeizablePosition(
                evaluator,
                snapshot,
                floan,
                market,
                borrowers_[i]
            );
            result.seizedDebtOhm += p.principalDue;
            result.seizedCollateral += p.collateral;
        }
        return _allocate(evaluator, snapshot, asset_, actor_, result);
    }

    /// @notice Rechecks the direct funding/default service before enabling this action.
    /// @dev Reverts if:
    ///      - The shared activation checks or Inventory readiness fails.
    function _validateActivation() internal view override {
        super._validateActivation();
        _requireInventoryOperational();
        _requirePayoutOperational();
    }

    /// @notice Validates every borrower before atomic Core settlement.
    /// @dev Reverts if:
    ///      - Borrowers are duplicated or zero, or debt is absent.
    ///      - Positions are ineligible, custody is unavailable or custody is insolvent.
    /// @param evaluator Risk calculator selected for this operation.
    /// @param snapshot Captured prices/backing in PRICE decimals.
    /// @param asset_ Configured underlying collateral asset.
    /// @param borrowers_ Complete bounded borrower list.
    function _validatePositions(
        IBurnerLoansRisk evaluator,
        IBurnerLoansCore.PriceSnapshot memory snapshot,
        address asset_,
        address[] calldata borrowers_
    ) private view {
        _validateBorrowers(borrowers_);
        LoanCustody.validateWithdrawalSupport(_CORE, asset_, address(kernel));
        IFLOANv1 floan = IFLOANv1(_CORE.floan());
        uint32 market = _CORE.marketId(asset_);
        for (uint256 i; i < borrowers_.length; ++i) {
            _validateSeizablePosition(evaluator, snapshot, floan, market, borrowers_[i]);
        }
        LoanSolvency.requireSolvent(
            IDepositManager(_CORE.depositManager()),
            asset_,
            address(_CORE)
        );
    }

    /// @notice	Loads and validates one borrower's canonical position for a seizure batch.
    /// @dev Reverts if:
    ///      - The position has no debt.
    ///      - The position is healthy and unexpired.
    ///      - A dependency view or Risk health evaluation fails.
    ///
    /// @param	evaluator_	Risk implementation using the captured snapshot.
    /// @param	snapshot_	Captured operation prices and backing, in PRICE decimals.
    /// @param	floan_	Canonical FLOAN module, resolved once for the batch.
    /// @param	market_	Canonical market, resolved once for the batch.
    /// @param	borrower_	Borrower whose position is evaluated.
    /// @return	position	Canonical debt-bearing position eligible for seizure.
    function _validateSeizablePosition(
        IBurnerLoansRisk evaluator_,
        IBurnerLoansCore.PriceSnapshot memory snapshot_,
        IFLOANv1 floan_,
        uint32 market_,
        address borrower_
    ) private view returns (IFLOANv1.Position memory position) {
        position = LoanPositions.getOrEmpty(floan_, market_, borrower_);
        // Each selected position must pass validation and settle atomically with the batch.
        // forge-lint: disable-next-line(require-revert-in-loop)
        if (position.principalDue == 0) revert IBurnerLoansCore.BurnerLoansCore_NoDebt();
        if (!LoanPositions.isSeizable(evaluator_, snapshot_, position.marketId, position))
            // Each selected position must pass validation and settle atomically with the batch.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert IBurnerLoansSeize.BurnerLoans_PositionNotSeizable(borrower_);
    }

    /// @notice Validates the complete bounded identity list before inspecting any position.
    /// @dev Reverts if:
    ///      - A borrower is zero or duplicated, including nonadjacent duplicates.
    /// @param borrowers_ Complete bounded borrower list.
    function _validateBorrowers(address[] calldata borrowers_) private pure {
        // Defaulting the same position twice must not inflate aggregate debt or collateral totals.
        // Duplicate detection is quadratic; callers choose a batch size that fits their gas budget.
        for (uint256 i; i < borrowers_.length; ++i) {
            // Reject zero or duplicate identities before any position is seized.
            // forge-lint: disable-next-line(require-revert-in-loop)
            if (borrowers_[i] == address(0)) revert IBurnerLoansErrors.BurnerLoans_ZeroAddress();
            for (uint256 j; j < i; ++j)
                if (borrowers_[i] == borrowers_[j])
                    // Reject zero or duplicate identities before any position is seized.
                    // forge-lint: disable-next-line(require-revert-in-loop)
                    revert IBurnerLoansSeize.BurnerLoans_DuplicateBorrower(borrowers_[i]);
        }
    }
}
