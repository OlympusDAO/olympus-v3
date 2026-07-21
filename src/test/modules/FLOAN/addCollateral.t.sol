// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {Module} from "src/Kernel.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANAddCollateralTest is FLOANTest {
    // addCollateral
    // given caller without kernel permission
    //  when addCollateral is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_addCollateral_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.addCollateral(positionId, 1);
    }

    // addCollateral
    // given valid amount
    //  when addCollateral is called
    //   then it updates only collateral
    function testFuzz_givenValidAmount_addCollateral_updatesOnlyCollateral(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);

        vm.prank(facility);
        uint128 collateral = floan.addCollateral(positionId, amount_);

        IFLOANv1.Position memory position = floan.getPosition(positionId);
        assertEq(collateral, amount_, "returned collateral");
        assertEq(position.collateral, amount_, "stored collateral");
        assertEq(position.principalDue, 0, "principal unchanged");
        assertEq(position.maturity, 0, "maturity unchanged");
    }

    // addCollateral
    // given zero amount
    //  when addCollateral is called
    //   then it reverts
    function test_givenZeroAmount_addCollateral_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.addCollateral(positionId, 0);
    }

    // addCollateral
    // given permissioned non facility
    //  when addCollateral is called
    //   then it reverts
    function test_givenPermissionedNonFacility_addCollateral_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.addCollateral(positionId, 1);
    }
}
