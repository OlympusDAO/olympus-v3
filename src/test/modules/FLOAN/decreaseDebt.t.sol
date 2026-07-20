// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {Module} from "src/Kernel.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANDecreaseDebtTest is FLOANTest {
    function test_givenCallerWithoutKernelPermission_decreaseDebt_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.decreaseDebt(positionId, 1, 0);
    }

    function test_givenPermissionedNonFacility_decreaseDebt_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.decreaseDebt(positionId, 1, 0);
    }

    function test_givenOriginationsDisabled_decreaseDebt_stillSucceeds() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        vm.prank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);
        vm.prank(facility);
        floan.decreaseDebt(positionId, 40e9, 0);

        assertEq(floan.getPosition(positionId).principalDue, 60e9, "principal due");
    }

    function test_givenZeroOrExcessiveAmount_decreaseDebt_revertsWithoutStateChange() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        vm.startPrank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.decreaseDebt(positionId, 0, 0);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.decreaseDebt(positionId, 100e9 + 1, 0);
        vm.stopPrank();

        assertEq(floan.getPosition(positionId).principalDue, 100e9, "principal unchanged");
        assertEq(floan.marketPrincipalDue(marketId), 100e9, "market principal unchanged");
    }

    function test_updatesMarketFacilityAndTokenPrincipalTotals() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(facility);
        floan.decreaseDebt(positionId, 40e9, 0);

        assertEq(floan.marketPrincipalDue(marketId), 60e9, "market principal");
        assertEq(floan.facilityPrincipalDue(facility, debtToken), 60e9, "facility principal");
        assertEq(floan.debtTokenPrincipalDue(debtToken), 60e9, "token principal");
    }

    function test_interestOnlyDecrease_doesNotChangePrincipalTotals() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 positionId = floan.getOrCreatePosition(marketId, borrower);
        floan.increaseDebt(positionId, 100e9, 25e9, uint48(block.timestamp + 30 days));
        floan.decreaseDebt(positionId, 0, 10e9);
        vm.stopPrank();

        assertEq(floan.marketPrincipalDue(marketId), 100e9, "market principal");
        assertEq(floan.facilityPrincipalDue(facility, debtToken), 100e9, "facility principal");
        assertEq(floan.debtTokenPrincipalDue(debtToken), 100e9, "token principal");
    }

    function test_decreaseDebt_givenFullClosure_clearsEpisodeAndActiveBorrower() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 positionId = floan.getOrCreatePosition(marketId, borrower);
        floan.increaseDebt(positionId, 100e9, 25e9, uint48(block.timestamp + 30 days));
        floan.decreaseDebt(positionId, 100e9, 25e9);
        vm.stopPrank();

        IFLOANv1.Position memory position = floan.getPosition(positionId);
        assertEq(position.principalDrawn, 0, "principal drawn cleared");
        assertEq(position.principalDue, 0, "principal due cleared");
        assertEq(position.interestDue, 0, "interest due cleared");
        assertEq(position.maturity, 0, "maturity cleared");
        assertEq(position.lastBorrowBlock, 0, "last borrow block cleared");
        assertEq(floan.getActiveBorrowers(marketId).length, 0, "active borrower removed");
        assertEq(floan.marketPrincipalDue(marketId), 0, "market principal cleared");
        assertEq(floan.facilityPrincipalDue(facility, debtToken), 0, "facility principal cleared");
        assertEq(floan.debtTokenPrincipalDue(debtToken), 0, "token principal cleared");
    }

    function test_decreaseDebt_givenAnotherActivePosition_keepsBorrowerActive() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 firstPositionId = floan.createPosition(marketId, borrower);
        uint64 secondPositionId = floan.createPosition(marketId, borrower);
        uint48 maturity = uint48(block.timestamp + 30 days);
        floan.increaseDebt(firstPositionId, 100e9, 0, maturity);
        floan.increaseDebt(secondPositionId, 200e9, 0, maturity);
        floan.decreaseDebt(firstPositionId, 100e9, 0);
        vm.stopPrank();

        address[] memory activeBorrowers = floan.getActiveBorrowers(marketId);
        assertEq(activeBorrowers.length, 1, "borrower remains active");
        assertEq(activeBorrowers[0], borrower, "active borrower");
        assertEq(floan.marketPrincipalDue(marketId), 200e9, "remaining market principal");
    }
}
