// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANPositionCountTest is FLOANTest {
    function test_givenNoPositions_positionCount_returnsZero() public view {
        assertEq(floan.positionCount(), 0, "position count");
    }

    function test_givenExplicitAndDefaultPositions_positionCount_returnsCreatedCount() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createPosition(marketId, facility, borrower);
        vm.prank(facility);
        floan.getOrCreatePosition(marketId, otherBorrower);

        assertEq(floan.positionCount(), 2, "position count");
    }
}
