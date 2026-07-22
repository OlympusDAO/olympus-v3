// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANActiveBorrowerCountTest is FLOANTest {
    function test_activeBorrowerCount_tracksDistinctBorrowersWithDebt() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createPositionWithDebt(marketId, facility, borrower, 100e9);
        _createPositionWithDebt(marketId, facility, otherBorrower, 200e9);

        assertEq(floan.activeBorrowerCount(marketId), 2, "active borrower count");
    }

    function test_givenInvalidMarket_activeBorrowerCount_reverts() public {
        vm.expectRevert();
        floan.activeBorrowerCount(0);
    }
}
