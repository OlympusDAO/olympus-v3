// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {Module} from "src/Kernel.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetOrCreatePositionTest is FLOANTest {
    function test_givenCallerWithoutKernelPermission_createPosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.createPosition(marketId, borrower);
    }

    function test_givenPermissionedNonFacility_createPosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.createPosition(marketId, borrower);
    }

    function test_givenZeroBorrower_createPosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.createPosition(marketId, address(0));
    }

    function test_createPosition_allowsMultiplePositionsForPair() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 firstPositionId = floan.createPosition(marketId, borrower);
        uint64 secondPositionId = floan.createPosition(marketId, borrower);
        vm.stopPrank();

        assertEq(firstPositionId, 0, "first position");
        assertEq(secondPositionId, 1, "second position");
        assertEq(floan.positionCount(), 2, "two positions created");
        (uint256 count, ) = floan.getPositionIdForMarketAndBorrower(marketId, borrower);
        assertEq(count, 2, "pair count");
    }
}
