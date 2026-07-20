// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {Module} from "src/Kernel.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANDefaultPositionTest is FLOANTest {
    function test_givenCallerWithoutKernelPermission_defaultPosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.defaultPosition(positionId);
    }

    function test_givenPermissionedNonFacility_defaultPosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.defaultPosition(positionId);
    }

    function test_givenDebtFreePosition_defaultPosition_revertsWithoutStateChange() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);

        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.defaultPosition(positionId);

        assertFalse(floan.isPositionDefaulted(positionId), "position not defaulted");
    }

    function test_defaultPosition_closesDebtAndCollateralAndPreservesEpisodeHistory() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint48 maturity = uint48(block.timestamp + 30 days);

        vm.startPrank(facility);
        uint64 positionId = floan.getOrCreatePosition(marketId, borrower);
        floan.addCollateral(positionId, 150e18);
        floan.increaseDebt(positionId, 100e9, 25e9, maturity);
        (uint128 principalDefaulted, uint128 interestDefaulted, uint128 collateralSeized) = floan
            .defaultPosition(positionId);
        vm.stopPrank();

        assertEq(principalDefaulted, 100e9, "principal defaulted");
        assertEq(interestDefaulted, 25e9, "interest defaulted");
        assertEq(collateralSeized, 150e18, "collateral seized");

        IFLOANv1.Position memory position = floan.getPosition(positionId);
        assertEq(position.principalDrawn, 100e9, "original principal preserved");
        assertEq(position.principalDue, 0, "principal due cleared");
        assertEq(position.interestDue, 0, "interest due cleared");
        assertEq(position.collateral, 0, "collateral cleared");
        assertEq(position.maturity, maturity, "maturity preserved");
        assertTrue(floan.isPositionDefaulted(positionId), "position defaulted");
        assertEq(floan.getActiveBorrowers(marketId).length, 0, "active borrower removed");
        assertEq(floan.marketPrincipalDue(marketId), 0, "market principal cleared");
        assertEq(floan.facilityPrincipalDue(facility, debtToken), 0, "facility principal cleared");
        assertEq(floan.debtTokenPrincipalDue(debtToken), 0, "token principal cleared");
    }

    function test_givenDefaultedPosition_mutatingFunctionsRevert() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 positionId = floan.getOrCreatePosition(marketId, borrower);
        floan.addCollateral(positionId, 150e18);
        floan.increaseDebt(positionId, 100e9, 0, uint48(block.timestamp + 30 days));
        floan.defaultPosition(positionId);

        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_PositionDefaulted.selector, positionId)
        );
        floan.addCollateral(positionId, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_PositionDefaulted.selector, positionId)
        );
        floan.increaseDebt(positionId, 1, 0, uint48(block.timestamp + 30 days));
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_PositionDefaulted.selector, positionId)
        );
        floan.extendMaturity(positionId, uint48(block.timestamp + 60 days));
        vm.stopPrank();
    }

    function test_defaultPosition_givenAnotherActivePosition_keepsBorrowerActive() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 firstPositionId = floan.createPosition(marketId, borrower);
        uint64 secondPositionId = floan.createPosition(marketId, borrower);
        uint48 maturity = uint48(block.timestamp + 30 days);
        floan.increaseDebt(firstPositionId, 100e9, 0, maturity);
        floan.increaseDebt(secondPositionId, 200e9, 0, maturity);
        floan.defaultPosition(firstPositionId);
        vm.stopPrank();

        address[] memory activeBorrowers = floan.getActiveBorrowers(marketId);
        assertEq(activeBorrowers.length, 1, "borrower remains active");
        assertEq(activeBorrowers[0], borrower, "active borrower");
        assertEq(floan.marketPrincipalDue(marketId), 200e9, "remaining market principal");
    }
}
