// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

/// @title Burner Loans Position Lookup
/// @notice	Resolves the first position created for a borrower in a market.
/// @dev	FLOAN permits multiple positions. Burner Loans intentionally operates only on the first
/// @dev	indexed position and leaves any later positions to their originating facility implementation.
library LoanPositions {
    /// @notice	Reports a position's health without requiring an unhealthy position to be cured.
    /// @dev Reverts if:
    ///      - Risk health evaluation fails for a debt-bearing position.
    ///
    /// @param	evaluator_	Risk implementation using the captured snapshot.
    /// @param	snapshot_	Captured prices and backing, in PRICE decimals.
    /// @param	position_	Actual or projected canonical position being evaluated.
    /// @return	uint256	Health in WAD, rounded down, or uint256.max for a debt-free position.
    function health(
        IBurnerLoansRisk evaluator_,
        IBurnerLoansCore.PriceSnapshot memory snapshot_,
        IFLOANv1.Position memory position_
    ) internal view returns (uint256) {
        if (position_.principalDue == 0) return type(uint256).max;
        return
            evaluator_.health(
                snapshot_,
                position_.marketId,
                position_.collateral,
                position_.principalDue
            );
    }

    /// @notice	Validates the health of an actual or projected final position.
    /// @dev Reverts if:
    ///      - Risk health evaluation fails.
    ///      - The debt-bearing final position is unhealthy.
    ///
    /// @param	evaluator_	Risk implementation using the captured snapshot.
    /// @param	snapshot_	Captured prices and backing, in PRICE decimals.
    /// @param	position_	Actual or projected canonical position being evaluated.
    /// @return	uint256	Accepted health in WAD, or uint256.max for a debt-free position.
    function validateFinalHealth(
        IBurnerLoansRisk evaluator_,
        IBurnerLoansCore.PriceSnapshot memory snapshot_,
        IFLOANv1.Position memory position_
    ) internal view returns (uint256) {
        if (position_.principalDue == 0) return type(uint256).max;
        return
            evaluator_.validateHealth(
                snapshot_,
                position_.marketId,
                position_.collateral,
                position_.principalDue,
                true
            );
    }

    /// @notice	Checks whether a debt-bearing position is matured or unhealthy.
    /// @dev Reverts if:
    ///      - Risk health evaluation fails for an unexpired debt-bearing position.
    ///
    /// @param	evaluator_	Risk implementation using the captured snapshot.
    /// @param	snapshot_	Captured prices and backing, in PRICE decimals.
    /// @param	market_	Canonical FLOAN market identifier.
    /// @param	position_	Canonical position being evaluated.
    /// @return	bool	Whether the position can be seized under the captured snapshot.
    function isSeizable(
        IBurnerLoansRisk evaluator_,
        IBurnerLoansCore.PriceSnapshot memory snapshot_,
        uint32 market_,
        IFLOANv1.Position memory position_
    ) internal view returns (bool) {
        // Each selected borrower needs its own canonical position or health read.
        // This multiline operation needs a range; the suppression ends immediately after it.
        // forge-lint: disable-start(calls-loop)
        return
            position_.principalDue != 0 &&
            // Expiry equality qualifies the stored debt episode.
            // forge-lint: disable-next-line(block-timestamp)
            (block.timestamp >= position_.maturity ||
                evaluator_.health(
                    snapshot_,
                    market_,
                    position_.collateral,
                    position_.principalDue
                ) <
                1e18);
        // forge-lint: disable-end(calls-loop)
    }

    /// @notice Reads the Core's canonical FLOAN market without adding a position ABI to Core.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param core_ Permanent accounting and DepositManager operator contract.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param borrower_ Account whose canonical position is queried or changed.
    /// @return bool Whether the position exists.
    /// @return uint64 Canonical FLOAN position ID, or zero when absent.
    /// @return IFLOANv1.Position Canonical position, or zero fields when absent.
    function forCore(
        IBurnerLoansCore core_,
        address asset_,
        address borrower_
    ) internal view returns (bool, uint64, IFLOANv1.Position memory) {
        // Resolve the current Core/module/market binding for each canonical position lookup.
        // forge-lint: disable-next-line(calls-loop)
        return getWithIdOrEmpty(IFLOANv1(core_.floan()), core_.marketId(asset_), borrower_);
    }

    /// @notice Finds the first position for a borrower in a market.
    /// @param floan_ FLOAN module to query.
    /// @param marketId_ FLOAN market identifier.
    /// @param borrower_ Position borrower.
    /// @return bool Whether a matching position exists.
    /// @return uint64 First matching position identifier, or zero when absent.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function find(
        IFLOANv1 floan_,
        uint32 marketId_,
        address borrower_
    ) internal view returns (bool, uint64) {
        // Each selected borrower needs its own canonical position or health read.
        // forge-lint: disable-next-line(calls-loop)
        return floan_.getPositionIdForMarketAndBorrowerAt(marketId_, borrower_, 0);
    }

    /// @notice Returns the first borrower position or an empty position for the market.
    /// @param floan_ FLOAN module to query.
    /// @param marketId_ FLOAN market identifier.
    /// @param borrower_ Position borrower.
    /// @return position Existing first position or a zero-valued position preserving identity.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function getOrEmpty(
        IFLOANv1 floan_,
        uint32 marketId_,
        address borrower_
    ) internal view returns (IFLOANv1.Position memory position) {
        (, , position) = getWithIdOrEmpty(floan_, marketId_, borrower_);
    }

    /// @notice Returns the first borrower position and its identifier, or an empty position.
    /// @param floan_ FLOAN module to query.
    /// @param marketId_ FLOAN market identifier.
    /// @param borrower_ Position borrower.
    /// @return exists Whether a matching position exists.
    /// @return positionId First matching position identifier, or zero when absent.
    /// @return position Existing first position or a zero-valued position preserving identity.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function getWithIdOrEmpty(
        IFLOANv1 floan_,
        uint32 marketId_,
        address borrower_
    ) internal view returns (bool exists, uint64 positionId, IFLOANv1.Position memory position) {
        (exists, positionId) = find(floan_, marketId_, borrower_);
        // The true literal explicitly marks the populated tuple returned with its position data.
        // forge-lint: disable-next-line(boolean-cst)
        // Each selected borrower needs its own canonical position or health read.
        // forge-lint: disable-next-line(calls-loop)
        if (exists) return (true, positionId, floan_.getPosition(positionId));

        // Absence is separate from a zero-valued stored position. Quotes can project a first deposit
        // without creating state; settlement uses exists to decide whether FLOAN must create an ID.
        position = IFLOANv1.Position({
            borrower: borrower_,
            marketId: marketId_,
            collateral: 0,
            principalDrawn: 0,
            principalDue: 0,
            interestDue: 0,
            maturity: 0,
            lastBorrowBlock: 0
        });
    }
}
