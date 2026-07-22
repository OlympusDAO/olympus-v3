// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANDecreaseDebtTest is FLOANTest {
    // decreaseDebt
    // given caller without kernel permission
    //  when decreaseDebt is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        _expectKernelPermissionRevert(caller_);
        floan.decreaseDebt(positionId, 1, 0);
    }

    // decreaseDebt
    // given an invalid position ID
    //  when decreaseDebt is called
    //   then it reverts
    function test_givenInvalidPosition_reverts_fuzz(uint64 positionId_) public {
        positionId_ = uint64(bound(positionId_, floan.getPositionCount(), type(uint64).max));
        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidPosition.selector, positionId_)
        );
        floan.decreaseDebt(positionId_, 1, 0);
    }

    // decreaseDebt
    // given caller is not the position market facility
    //  when decreaseDebt is called
    //   then it reverts
    function test_givenCallerIsNotPositionMarketFacility_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.decreaseDebt(positionId, 1, 0);
    }

    // decreaseDebt
    // given originations disabled
    //  when decreaseDebt is called
    //   then it still succeeds
    function test_givenOriginationsDisabled_stillSucceeds() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        vm.prank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);
        vm.prank(facility);
        floan.decreaseDebt(positionId, 40e9, 0);

        assertEq(floan.getPosition(positionId).principalDue, 60e9, "principal due");
        assertEq(floan.getActiveBorrowerCount(marketId), 1, "active borrower count");
        assertEq(floan.getActiveBorrowerAt(marketId, 0), borrower, "active borrower");
    }

    // decreaseDebt
    // given a defaulted position
    //  when decreaseDebt is called
    //   then it reverts
    function test_givenDefaultedPosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.startPrank(facility);
        floan.defaultPosition(positionId);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_PositionDefaulted.selector, positionId)
        );
        floan.decreaseDebt(positionId, 1, 0);
        vm.stopPrank();
    }

    // decreaseDebt
    // given a position without principal or interest due
    //  when decreaseDebt is called
    //   then it reverts
    function test_givenDebtFreePosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);

        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.decreaseDebt(positionId, 1, 0);
    }

    // decreaseDebt
    // given zero principal and interest decrease
    //  when decreaseDebt is called
    //   then it reverts without state change
    function test_givenZeroAmount_revertsWithoutStateChange() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.decreaseDebt(positionId, 0, 0);

        assertEq(floan.getPosition(positionId).principalDue, 100e9, "principal unchanged");
        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "market principal unchanged");
    }

    // decreaseDebt
    // given principal decrease above principal due
    //  when decreaseDebt is called
    //   then it reverts without state change
    function test_givenPrincipalAboveDue_revertsWithoutStateChange_fuzz(uint128 excess_) public {
        excess_ = uint128(bound(excess_, 1, type(uint128).max - 100e9));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.decreaseDebt(positionId, uint128(100e9 + excess_), 0);

        assertEq(floan.getPosition(positionId).principalDue, 100e9, "principal unchanged");
        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "market principal unchanged");
    }

    // decreaseDebt
    // given interest decrease above interest due
    //  when decreaseDebt is called
    //   then it reverts without state change
    function test_givenInterestAboveDue_revertsWithoutStateChange_fuzz(uint128 excess_) public {
        excess_ = uint128(bound(excess_, 1, type(uint128).max - 25e9));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 positionId = floan.createPosition(marketId, borrower);
        floan.increaseDebt(positionId, 100e9, 25e9, uint48(block.timestamp + 30 days));
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.decreaseDebt(positionId, 0, uint128(25e9 + excess_));
        vm.stopPrank();

        assertEq(floan.getPosition(positionId).interestDue, 25e9, "interest unchanged");
        assertEq(floan.getMarketInterestDue(marketId), 25e9, "market interest unchanged");
    }

    // decreaseDebt
    // given principal debt across a market and facility
    //  when decreaseDebt is called
    //   then it updates market and facility principal totals
    function test_updatesMarketAndFacilityPrincipalTotals() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(facility);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionDebtDecreased(positionId, 60e9, 0);
        floan.decreaseDebt(positionId, 40e9, 0);

        assertEq(floan.getMarketPrincipalDue(marketId), 60e9, "market principal");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 60e9, "facility principal");
    }

    // decreaseDebt
    // given interest only decrease
    //  when decreaseDebt is called
    //   then it does not change principal totals
    function test_givenDeferredInterestPayment_updatesOnlyInterestTotals() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 positionId = floan.createPosition(marketId, borrower);
        floan.increaseDebt(positionId, 100e9, 25e9, uint48(block.timestamp + 30 days));
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionDebtDecreased(positionId, 100e9, 15e9);
        floan.decreaseDebt(positionId, 0, 10e9);
        vm.stopPrank();

        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "market principal");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 100e9, "facility principal");
        assertEq(floan.getMarketInterestDue(marketId), 15e9, "market interest");
    }

    // decreaseDebt
    // given full closure
    //  when decreaseDebt is called
    //   then it clears episode and active borrower
    function test_givenFullClosure_clearsEpisodeAndActiveBorrower() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 positionId = floan.createPosition(marketId, borrower);
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
        assertEq(floan.getActiveBorrowerCount(marketId), 0, "active borrower count");
        assertEq(floan.getMarketPrincipalDue(marketId), 0, "market principal cleared");
        assertEq(floan.getMarketInterestDue(marketId), 0, "market interest cleared");
        assertEq(
            floan.getFacilityPrincipalDue(facility, debtToken),
            0,
            "facility principal cleared"
        );
    }

    // decreaseDebt
    // given another active position
    //  when decreaseDebt is called
    //   then it keeps borrower active
    function test_givenAnotherActivePosition_keepsBorrowerActive() public {
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
        assertEq(floan.getActiveBorrowerCount(marketId), 1, "active borrower count");
        assertEq(floan.getActiveBorrowerAt(marketId, 0), borrower, "active borrower by index");
        assertEq(floan.getMarketPrincipalDue(marketId), 200e9, "remaining market principal");
    }
}
