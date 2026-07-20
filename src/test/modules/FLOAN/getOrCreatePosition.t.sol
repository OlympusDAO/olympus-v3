// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {Module} from "src/Kernel.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetOrCreatePositionTest is FLOANTest {
    function test_givenCallerWithoutKernelPermission_getOrCreatePosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.getOrCreatePosition(marketId, borrower);
    }

    function test_givenPermissionedNonFacility_getOrCreatePosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.getOrCreatePosition(marketId, borrower);
    }

    function test_givenZeroBorrower_getOrCreatePosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.getOrCreatePosition(marketId, address(0));
    }

    function test_getOrCreatePosition_returnsCanonicalPositionForPair() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 firstPositionId = floan.getOrCreatePosition(marketId, borrower);
        uint64 secondPositionId = floan.getOrCreatePosition(marketId, borrower);
        vm.stopPrank();

        (bool exists, uint64 lookupId) = floan.getPositionId(marketId, borrower);
        assertTrue(exists, "default position exists");
        assertEq(firstPositionId, secondPositionId, "same position returned");
        assertEq(lookupId, firstPositionId, "lookup position id");
        assertEq(floan.positionCount(), 1, "one position created");
    }
}
