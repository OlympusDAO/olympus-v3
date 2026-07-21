// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANActiveBorrowerAtTest is FLOANTest {
    // activeBorrowerAt
    // given an active borrower at the requested index
    //  when activeBorrowerAt is called
    //   then it returns borrower at index
    function test_activeBorrowerAt_returnsBorrowerAtIndex() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createPositionWithDebt(marketId, facility, borrower, 100e9);
        _createPositionWithDebt(marketId, facility, otherBorrower, 200e9);

        assertEq(floan.activeBorrowerAt(marketId, 0), borrower, "first borrower");
        assertEq(floan.activeBorrowerAt(marketId, 1), otherBorrower, "second borrower");
    }

    // activeBorrowerAt
    // given index out of bounds
    //  when activeBorrowerAt is called
    //   then it reverts
    function test_givenIndexOutOfBounds_activeBorrowerAt_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.expectRevert();
        floan.activeBorrowerAt(marketId, 0);
    }
}
