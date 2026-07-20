// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetPositionForBorrowerTest is FLOANTest {
    function test_givenNoDefaultPosition_getPositionForBorrower_returnsEmptyTypedPosition() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        IFLOANv1.Position memory position = floan.getPositionForBorrower(marketId, borrower);
        assertEq(position.borrower, borrower, "borrower");
        assertEq(position.marketId, marketId, "market id");
        assertEq(position.principalDue, 0, "principal due");
    }

    function test_givenDefaultPosition_getPositionForBorrower_returnsStoredPosition() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        assertEq(
            abi.encode(floan.getPositionForBorrower(marketId, borrower)),
            abi.encode(floan.getPosition(positionId)),
            "borrower position"
        );
    }
}
