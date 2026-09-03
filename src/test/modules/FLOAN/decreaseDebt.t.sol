// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANDecreaseDebtTest is FLOANTest {
    // decreaseDebt
    // given caller without kernel permission
    //  when decreaseDebt is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        _expectKernelPermissionRevert(caller_);
        floan.decreaseDebt(positionId, 1, 0);
    }

    // decreaseDebt
    // given an invalid position ID
    //  when decreaseDebt is called
    //   then it reverts
    function test_givenInvalidPosition_reverts(uint64 positionId_) public {
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
    function test_givenPrincipalAboveDue_revertsWithoutStateChange(uint128 excess_) public {
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
    function test_givenInterestAboveDue_revertsWithoutStateChange(uint128 excess_) public {
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
    //   then it emits history, clears the episode, and allows the position ID to be reused
    function test_givenFullClosure_clearsEpisodeAndAllowsPositionReuse() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint48 maturity = uint48(block.timestamp + 30 days);

        vm.startPrank(facility);
        uint64 positionId = floan.createPosition(marketId, borrower);
        floan.addCollateral(positionId, 50e18);
        floan.increaseDebt(positionId, 100e9, 25e9, maturity);
        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.PositionClosed(
            positionId,
            marketId,
            borrower,
            50e18,
            100e9,
            maturity,
            uint32(block.number)
        );
        floan.decreaseDebt(positionId, 100e9, 25e9);
        vm.stopPrank();

        _assertPosition(
            positionId,
            IFLOANv1.Position({
                borrower: borrower,
                marketId: marketId,
                collateral: 50e18,
                principalDrawn: 0,
                principalDue: 0,
                interestDue: 0,
                maturity: 0,
                lastBorrowBlock: 0
            })
        );
        assertEq(floan.getActiveBorrowers(marketId).length, 0, "active borrower removed");
        assertEq(floan.getActiveBorrowerCount(marketId), 0, "active borrower count");
        assertEq(floan.getMarketPrincipalDue(marketId), 0, "market principal cleared");
        assertEq(floan.getMarketInterestDue(marketId), 0, "market interest cleared");
        assertEq(floan.getMarketCollateral(marketId), 50e18, "market collateral retained");
        assertEq(
            floan.getFacilityPrincipalDue(facility, debtToken),
            0,
            "facility principal cleared"
        );

        uint48 newMaturity = uint48(block.timestamp + 60 days);
        vm.prank(facility);
        floan.increaseDebt(positionId, 150e9, 10e9, newMaturity);

        IFLOANv1.Position memory position = floan.getPosition(positionId);
        assertEq(floan.getPositionCount(), 1, "position ID reused");
        assertEq(position.principalDrawn, 150e9, "new episode principal drawn");
        assertEq(position.principalDue, 150e9, "new episode principal due");
        assertEq(position.interestDue, 10e9, "new episode interest due");
        assertEq(position.maturity, newMaturity, "new episode maturity");
        assertEq(floan.getActiveBorrowerCount(marketId), 1, "borrower reactivated");
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
