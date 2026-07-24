// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";

/// @title Burner Loans Position Lookup
/// @notice Resolves the first position created for a borrower in a market.
/// @dev FLOAN permits multiple positions. Burner Loans intentionally operates only on the first
///      indexed position and leaves any later positions to their originating facility implementation.
library BurnerLoansPositions {
    using SafeCast for uint256;

    /// @notice Finds the first position for a borrower in a market.
    /// @param floan_ FLOAN module to query.
    /// @param marketId_ FLOAN market identifier.
    /// @param borrower_ Position borrower.
    /// @return exists Whether a matching position exists.
    /// @return positionId First matching position identifier, or zero when absent.
    function find(
        IFLOANv1 floan_,
        uint32 marketId_,
        address borrower_
    ) internal view returns (bool exists, uint64 positionId) {
        uint256[] memory positionIds = floan_.getPositionIdsForMarketAndBorrower(
            marketId_,
            borrower_
        );
        if (positionIds.length == 0) return (false, 0);

        return (true, positionIds[0].toUint64());
    }

    /// @notice Returns the first borrower position or an empty position for the market.
    /// @param floan_ FLOAN module to query.
    /// @param marketId_ FLOAN market identifier.
    /// @param borrower_ Position borrower.
    /// @return position Existing first position or a zero-valued position preserving identity.
    function getOrEmpty(
        IFLOANv1 floan_,
        uint32 marketId_,
        address borrower_
    ) internal view returns (IFLOANv1.Position memory position) {
        (bool exists, uint64 positionId) = find(floan_, marketId_, borrower_);
        if (exists) return floan_.getPosition(positionId);

        return
            IFLOANv1.Position({
                borrower: borrower_,
                marketId: marketId_,
                collateral: 0,
                principalDrawn: 0,
                principalDue: 0,
                interestDue: 0,
                maturity: 0,
                lastBorrowBlock: 0,
                defaulted: false
            });
    }

    /// @notice Returns the first borrower position ID, creating a position when absent.
    /// @dev Reverts with the underlying FLOAN error if position creation is not permitted.
    /// @param floan_ FLOAN module to mutate.
    /// @param marketId_ FLOAN market identifier.
    /// @param borrower_ Position borrower.
    /// @return positionId Existing or newly created position identifier.
    function getOrCreate(
        IFLOANv1 floan_,
        uint32 marketId_,
        address borrower_
    ) internal returns (uint64 positionId) {
        (bool exists, uint64 existingPositionId) = find(floan_, marketId_, borrower_);
        return exists ? existingPositionId : floan_.createPosition(marketId_, borrower_);
    }
}
