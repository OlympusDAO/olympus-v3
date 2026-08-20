// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANRemoveCollateralTest is FLOANTest {
    // removeCollateral
    // given caller without kernel permission
    //  when removeCollateral is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        _expectKernelPermissionRevert(caller_);
        floan.removeCollateral(positionId, 1);
    }

    // removeCollateral
    // given amount at or below balance
    //  when removeCollateral is called
    //   then it decreases exactly
    function test_givenAmountAtOrBelowBalance_decreasesExactly(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 1_000e18));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.startPrank(facility);
        floan.addCollateral(positionId, 1_000e18);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionCollateralChanged(positionId, 1_000e18 - amount_);
        uint128 remaining = floan.removeCollateral(positionId, amount_);
        vm.stopPrank();

        assertEq(remaining, 1_000e18 - amount_, "returned collateral");
        assertEq(floan.getPosition(positionId).collateral, remaining, "stored collateral");
        assertEq(floan.getMarketCollateral(marketId), remaining, "market collateral");
    }

    // removeCollateral
    // given multiple positions in one market
    //  when collateral is removed from one position
    //   then it decrements only that position and the market aggregate
    function test_givenMultiplePositions_decrementsPositionAndMarketAggregate(
        uint128 amount_
    ) public {
        amount_ = uint128(bound(amount_, 1, 100e18));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 firstPositionId = _createPosition(marketId, facility, borrower);
        uint64 secondPositionId = _createPosition(marketId, facility, otherBorrower);

        vm.startPrank(facility);
        floan.addCollateral(firstPositionId, 100e18);
        floan.addCollateral(secondPositionId, 250e18);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionCollateralChanged(firstPositionId, 100e18 - amount_);
        floan.removeCollateral(firstPositionId, amount_);
        vm.stopPrank();

        assertEq(
            floan.getPosition(firstPositionId).collateral,
            100e18 - amount_,
            "first position collateral"
        );
        assertEq(
            floan.getPosition(secondPositionId).collateral,
            250e18,
            "second position collateral"
        );
        assertEq(floan.getMarketCollateral(marketId), 350e18 - amount_, "market collateral");
    }

    // removeCollateral
    // given market originations are disabled
    //  when removeCollateral is called
    //   then it still decreases collateral
    function test_givenOriginationsDisabled_stillSucceeds() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);

        vm.prank(facility);
        floan.addCollateral(positionId, 100);
        vm.prank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);

        vm.prank(facility);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionCollateralChanged(positionId, 60);
        uint128 remaining = floan.removeCollateral(positionId, 40);

        assertEq(remaining, 60, "returned collateral");
        assertEq(floan.getPosition(positionId).collateral, 60, "stored collateral");
        assertEq(floan.getMarketCollateral(marketId), 60, "market collateral");
    }

    // removeCollateral
    // given zero amount
    //  when removeCollateral is called
    //   then it reverts
    function test_givenZeroAmount_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.startPrank(facility);
        floan.addCollateral(positionId, 100);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.removeCollateral(positionId, 0);
        vm.stopPrank();
        assertEq(floan.getPosition(positionId).collateral, 100, "collateral unchanged");
        assertEq(floan.getMarketCollateral(marketId), 100, "market collateral unchanged");
    }

    // removeCollateral
    // given amount above balance
    //  when removeCollateral is called
    //   then it reverts
    function test_givenAmountAboveBalance_reverts(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 101, type(uint128).max));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.startPrank(facility);
        floan.addCollateral(positionId, 100);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.removeCollateral(positionId, amount_);
        vm.stopPrank();
        assertEq(floan.getPosition(positionId).collateral, 100, "collateral unchanged");
        assertEq(floan.getMarketCollateral(marketId), 100, "market collateral unchanged");
    }

    // removeCollateral
    // given invalid position id
    //  when removeCollateral is called
    //   then it reverts
    function test_givenInvalidPositionId_reverts(uint64 positionId_) public {
        positionId_ = uint64(bound(positionId_, floan.getPositionCount(), type(uint64).max));
        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidPosition.selector, positionId_)
        );
        floan.removeCollateral(positionId_, 1);
    }

    // removeCollateral
    // given caller is not the position market facility
    //  when removeCollateral is called
    //   then it reverts
    function test_givenCallerIsNotPositionMarketFacility_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.removeCollateral(positionId, 1);
    }

    // removeCollateral
    // given caller is the position market manager but not its facility
    //  when removeCollateral is called
    //   then it reverts
    function test_givenCallerIsPositionMarketManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, manager)
        );
        floan.removeCollateral(positionId, 1);
    }
}
