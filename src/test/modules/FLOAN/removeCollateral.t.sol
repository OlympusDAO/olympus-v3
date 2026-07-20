// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {Module} from "src/Kernel.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANRemoveCollateralTest is FLOANTest {
    function test_givenCallerWithoutKernelPermission_removeCollateral_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.removeCollateral(positionId, 1);
    }

    function testFuzz_givenAmountAtOrBelowBalance_removeCollateral_decreasesExactly(
        uint128 amount_
    ) public {
        amount_ = uint128(bound(amount_, 1, 1_000e18));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.startPrank(facility);
        floan.addCollateral(positionId, 1_000e18);
        uint128 remaining = floan.removeCollateral(positionId, amount_);
        vm.stopPrank();

        assertEq(remaining, 1_000e18 - amount_, "returned collateral");
        assertEq(floan.getPosition(positionId).collateral, remaining, "stored collateral");
    }

    function test_givenZeroOrOneAboveBalance_removeCollateral_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.startPrank(facility);
        floan.addCollateral(positionId, 100);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.removeCollateral(positionId, 0);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.removeCollateral(positionId, 101);
        vm.stopPrank();
        assertEq(floan.getPosition(positionId).collateral, 100, "collateral unchanged");
    }

    function test_givenPermissionedNonFacility_removeCollateral_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.removeCollateral(positionId, 1);
    }
}
