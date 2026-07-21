// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Position Lookup
/// @notice Applies Burner Loans' one-position-per-market-and-borrower rule over generic FLOAN indexes.
library BurnerLoansPositions {
    function find(
        IFLOANv1 floan_,
        uint32 marketId_,
        address borrower_
    ) internal view returns (bool exists, uint64 positionId) {
        uint256 count;
        (count, positionId) = floan_.getPositionIdForMarketAndBorrower(marketId_, borrower_);
        if (count > 1) {
            revert IBurnerLoans.BurnerLoans_AmbiguousPosition(marketId_, borrower_, count);
        }
        if (count == 0) return (false, 0);

        return (true, positionId);
    }

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

    function getOrCreate(
        IFLOANv1 floan_,
        uint32 marketId_,
        address borrower_
    ) internal returns (uint64 positionId) {
        (bool exists, uint64 existingPositionId) = find(floan_, marketId_, borrower_);
        return exists ? existingPositionId : floan_.createPosition(marketId_, borrower_);
    }
}
