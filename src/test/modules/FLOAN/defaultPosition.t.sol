// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANDefaultPositionTest is FLOANTest {
    // defaultPosition
    // given caller without kernel permission
    //  when defaultPosition is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        _expectKernelPermissionRevert(caller_);
        floan.defaultPosition(positionId);
    }

    // defaultPosition
    // given invalid position ID
    //  when defaultPosition is called
    //   then it reverts without changing accounting
    function test_givenInvalidPosition_reverts_fuzz(uint64 positionId_) public {
        vm.assume(positionId_ != 0);
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidPosition.selector, positionId_)
        );
        floan.defaultPosition(positionId_);

        assertEq(floan.getPositionCount(), 0, "position count");
        assertEq(floan.getMarketPrincipalDue(marketId), 0, "market principal");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 0, "facility principal");
        assertEq(floan.getActiveBorrowerCount(marketId), 0, "active borrower count");
    }

    // defaultPosition
    // given caller is not the position market facility
    //  when defaultPosition is called
    //   then it reverts
    function test_givenCallerIsNotPositionMarketFacility_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.defaultPosition(positionId);
    }

    // defaultPosition
    // given debt free position
    //  when defaultPosition is called
    //   then it reverts without state change
    function test_givenDebtFreePosition_revertsWithoutStateChange() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);

        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.defaultPosition(positionId);

        assertFalse(floan.getPosition(positionId).defaulted, "position not defaulted");
    }

    // defaultPosition
    // given an already-defaulted position
    //  when defaultPosition is called
    //   then it reverts
    function test_givenAlreadyDefaultedPosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.startPrank(facility);
        floan.defaultPosition(positionId);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_PositionDefaulted.selector, positionId)
        );
        floan.defaultPosition(positionId);
        vm.stopPrank();
    }

    // defaultPosition
    // given a position with collateral, principal, and interest due
    //  when defaultPosition is called
    //   then it closes debt and collateral and preserves episode history
    function test_closesDebtAndCollateralAndPreservesEpisodeHistory() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint48 maturity = uint48(block.timestamp + 30 days);

        vm.startPrank(facility);
        uint64 positionId = floan.createPosition(marketId, borrower);
        floan.addCollateral(positionId, 150e18);
        floan.increaseDebt(positionId, 100e9, 25e9, maturity);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionDebtDecreased(positionId, 0, 0);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionCollateralChanged(positionId, 0);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionDefaulted(positionId, 100e9, 25e9, 150e18);
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
        assertEq(floan.getMarketCollateral(marketId), 0, "market collateral cleared");
        assertEq(position.maturity, maturity, "maturity preserved");
        assertTrue(position.defaulted, "position defaulted");
        assertEq(floan.getActiveBorrowers(marketId).length, 0, "active borrower removed");
        assertEq(floan.getActiveBorrowerCount(marketId), 0, "active borrower count");
        assertEq(floan.getMarketPrincipalDue(marketId), 0, "market principal cleared");
        assertEq(floan.getMarketInterestDue(marketId), 0, "market interest cleared");
        assertEq(
            floan.getFacilityPrincipalDue(facility, debtToken),
            0,
            "facility principal cleared"
        );
        assertEq(floan.getMarketPrincipalDefaulted(marketId), 100e9, "market principal defaulted");
    }

    // defaultPosition
    // given principal is due without interest
    //  when defaultPosition is called by the market facility
    //   then it records only principal as defaulted
    function test_givenPrincipalOnly_recordsPrincipalDefault() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(facility);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionDefaulted(positionId, 100e9, 0, 0);
        (uint128 principalDefaulted, uint128 interestDefaulted, ) = floan.defaultPosition(
            positionId
        );

        assertEq(principalDefaulted, 100e9, "principal defaulted");
        assertEq(interestDefaulted, 0, "interest defaulted");
        assertEq(floan.getMarketPrincipalDefaulted(marketId), 100e9, "market defaulted principal");
    }

    // defaultPosition
    // given interest is due without principal
    //  when defaultPosition is called
    //   then it records only interest as defaulted
    function test_givenInterestOnly_recordsInterestDefault() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 positionId = floan.createPosition(marketId, borrower);
        floan.increaseDebt(positionId, 100e9, 25e9, uint48(block.timestamp + 30 days));
        floan.decreaseDebt(positionId, 100e9, 0);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionDefaulted(positionId, 0, 25e9, 0);
        (uint128 principalDefaulted, uint128 interestDefaulted, ) = floan.defaultPosition(
            positionId
        );
        vm.stopPrank();

        assertEq(principalDefaulted, 0, "principal defaulted");
        assertEq(interestDefaulted, 25e9, "interest defaulted");
        assertEq(floan.getMarketPrincipalDefaulted(marketId), 0, "market defaulted principal");
        assertEq(floan.getMarketInterestDue(marketId), 0, "market interest cleared");
    }

    // defaultPosition
    // given market originations are disabled
    //  when defaultPosition is called
    //   then servicing still succeeds
    function test_givenOriginationsDisabled_stillSucceeds() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);
        vm.prank(facility);
        floan.defaultPosition(positionId);

        assertTrue(floan.getPosition(positionId).defaulted, "position defaulted");
        assertEq(floan.getMarketPrincipalDue(marketId), 0, "market principal cleared");
        assertEq(
            floan.getFacilityPrincipalDue(facility, debtToken),
            0,
            "facility principal cleared"
        );
    }

    // defaultPosition
    // given another active position
    //  when defaultPosition is called
    //   then it keeps borrower active
    function test_givenAnotherActivePosition_keepsBorrowerActive() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 firstPositionId = floan.createPosition(marketId, borrower);
        uint64 secondPositionId = floan.createPosition(marketId, borrower);
        floan.addCollateral(firstPositionId, 150e18);
        floan.addCollateral(secondPositionId, 250e18);
        uint48 maturity = uint48(block.timestamp + 30 days);
        floan.increaseDebt(firstPositionId, 100e9, 0, maturity);
        floan.increaseDebt(secondPositionId, 200e9, 0, maturity);
        floan.defaultPosition(firstPositionId);
        vm.stopPrank();

        address[] memory activeBorrowers = floan.getActiveBorrowers(marketId);
        assertEq(activeBorrowers.length, 1, "borrower remains active");
        assertEq(activeBorrowers[0], borrower, "active borrower");
        assertEq(floan.getActiveBorrowerCount(marketId), 1, "active borrower count");
        assertEq(floan.getActiveBorrowerAt(marketId, 0), borrower, "active borrower by index");
        assertEq(floan.getMarketPrincipalDue(marketId), 200e9, "remaining market principal");
        assertEq(floan.getMarketCollateral(marketId), 250e18, "remaining market collateral");
    }
}
