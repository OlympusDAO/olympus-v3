// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetPositionIdTest is FLOANTest {
    function test_givenNoDefaultPosition_getPositionId_returnsFalseAndZero() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        (bool exists, uint64 positionId) = floan.getPositionId(marketId, borrower);
        assertFalse(exists, "position should not exist");
        assertEq(positionId, 0, "position id");
    }

    function test_givenDefaultAndExplicitPositions_getPositionId_returnsOnlyDefault() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createPosition(marketId, facility, borrower);
        vm.prank(facility);
        uint64 expected = floan.getOrCreatePosition(marketId, borrower);

        (bool exists, uint64 positionId) = floan.getPositionId(marketId, borrower);
        assertTrue(exists, "position should exist");
        assertEq(positionId, expected, "default position id");
    }

    function test_givenMissingMarket_getPositionId_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, 0));
        floan.getPositionId(0, borrower);
    }
}
