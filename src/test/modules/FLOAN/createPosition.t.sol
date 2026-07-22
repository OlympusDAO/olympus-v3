// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANCreatePositionTest is FLOANTest {
    // createPosition getters
    // given no stored position
    //  when getPosition is called
    //   then it reverts
    function test_givenMissingPosition_getterReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidPosition.selector, 0));
        floan.getPosition(0);
    }

    // createPosition indexes
    // given no stored market
    //  when market position indexes are read
    //   then they return empty arrays
    function test_givenMissingMarket_indexGettersReturnEmptyArrays() public view {
        assertEq(floan.getPositionIdsForMarket(0).length, 0, "missing market positions");
        assertEq(
            floan.getPositionIdsForMarketAndBorrower(0, borrower).length,
            0,
            "missing market borrower positions"
        );
    }

    // createPosition
    // given caller without kernel permission
    //  when createPosition is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _expectKernelPermissionRevert(caller_);
        floan.createPosition(marketId, borrower);
    }

    // createPosition
    // given invalid market ID
    //  when createPosition is called
    //   then it reverts
    function test_givenInvalidMarket_reverts_fuzz(uint32 marketId_) public {
        vm.assume(marketId_ != 0);
        vm.prank(facility);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, marketId_));
        floan.createPosition(marketId_, borrower);
    }

    // createPosition
    // given caller is not the market facility
    //  when createPosition is called
    //   then it reverts
    function test_givenCallerIsNotMarketFacility_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.createPosition(marketId, borrower);
    }

    // createPosition
    // given caller is the market manager but not its facility
    //  when createPosition is called
    //   then it reverts
    function test_givenCallerIsMarketManagerButNotFacility_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, manager)
        );
        floan.createPosition(marketId, borrower);
    }

    // createPosition
    // given zero borrower
    //  when createPosition is called
    //   then it reverts
    function test_givenZeroBorrower_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.createPosition(marketId, address(0));
    }

    // createPosition
    // given market originations are disabled
    //  when createPosition is called
    //   then it reverts without consuming a position ID or updating indexes
    function test_givenOriginationsDisabled_revertsWithoutStateChange() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_OriginationsDisabled.selector, marketId)
        );
        floan.createPosition(marketId, borrower);

        assertEq(floan.getPositionCount(), 0, "position count");
        assertEq(floan.getPositionIdsForBorrower(borrower).length, 0, "borrower positions");
        assertEq(floan.getPositionIdsForMarket(marketId).length, 0, "market positions");
        assertEq(
            floan.getPositionIdsForMarketAndBorrower(marketId, borrower).length,
            0,
            "market borrower positions"
        );
    }

    // createPosition
    // given a single borrower and market
    //  when createPosition is called
    //   then it stores an empty position and every index
    //   then it emits PositionCreated
    function test_givenSingleBorrower_storesPositionAndIndexes() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        assertEq(floan.getPositionCount(), 0, "initial position count");

        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.PositionCreated(0, marketId, borrower);
        vm.prank(facility);
        uint64 positionId = floan.createPosition(marketId, borrower);

        IFLOANv1.Position memory expected = IFLOANv1.Position({
            borrower: borrower,
            marketId: marketId,
            collateral: 0,
            principalDrawn: 0,
            principalDue: 0,
            interestDue: 0,
            maturity: 0,
            lastBorrowBlock: 0,
            defaulted: false
        });
        assertEq(positionId, 0, "position ID");
        _assertPosition(positionId, expected);
        _assertPositionIndexes(positionId, marketId, borrower, 1, 1, 1, 1);
        assertEq(floan.getActiveBorrowerCount(marketId), 0, "active borrower count");
    }

    // createPosition
    // given the market manager is also its facility
    //  when createPosition is called by that address
    //   then it creates and indexes the position
    function test_givenManagerIsFacility_succeeds() public {
        uint32 marketId = _createMarket(manager, manager, collateralToken, debtToken, 1_000e9);

        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.PositionCreated(0, marketId, borrower);
        vm.prank(manager);
        uint64 positionId = floan.createPosition(marketId, borrower);

        assertEq(positionId, 0, "position ID");
        assertEq(floan.getPosition(positionId).borrower, borrower, "borrower");
        _assertPositionIndexes(positionId, marketId, borrower, 1, 1, 1, 1);
    }

    // createPosition
    // given an existing market and borrower
    //  when createPosition is called
    //   then it allows multiple positions and indexes each
    function test_allowsMultiplePositionsAndIndexesEach() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 firstPositionId = floan.createPosition(marketId, borrower);
        uint64 secondPositionId = floan.createPosition(marketId, borrower);
        vm.stopPrank();

        uint256[] memory borrowerIds = floan.getPositionIdsForBorrower(borrower);
        uint256[] memory marketIds = floan.getPositionIdsForMarket(marketId);
        uint256[] memory pairIds = floan.getPositionIdsForMarketAndBorrower(marketId, borrower);
        assertEq(firstPositionId, 0, "first position id");
        assertEq(secondPositionId, 1, "second position id");
        assertEq(floan.getPositionCount(), 2, "position count");
        assertEq(floan.getActiveBorrowerCount(marketId), 0, "active borrower count");
        assertEq(borrowerIds.length, 2, "borrower index length");
        assertEq(marketIds.length, 2, "market index length");
        assertEq(pairIds.length, 2, "pair index length");
        assertEq(pairIds[0], firstPositionId, "first pair position");
        assertEq(pairIds[1], secondPositionId, "second pair position");
    }

    // createPosition
    // given multiple markets and borrowers
    //  when positions are created
    //   then global IDs remain sequential and each index is isolated
    function test_givenMultipleMarkets_storesSequentialIdsAndIsolatedIndexes() public {
        uint32 firstMarket = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 secondMarket = _createMarket(
            otherManager,
            otherFacility,
            otherCollateralToken,
            otherDebtToken,
            2_000e9
        );

        uint64 firstPosition = _createPosition(firstMarket, facility, borrower);
        uint64 secondPosition = _createPosition(secondMarket, otherFacility, borrower);
        uint64 thirdPosition = _createPosition(secondMarket, otherFacility, otherBorrower);

        assertEq(firstPosition, 0, "first position ID");
        assertEq(secondPosition, 1, "second position ID");
        assertEq(thirdPosition, 2, "third position ID");
        _assertPositionIndexes(firstPosition, firstMarket, borrower, 3, 2, 1, 1);
        _assertPositionIndexes(secondPosition, secondMarket, borrower, 3, 2, 2, 1);
        _assertPositionIndexes(thirdPosition, secondMarket, otherBorrower, 3, 1, 2, 1);
        assertEq(floan.getPosition(firstPosition).marketId, firstMarket, "first market ID");
        assertEq(floan.getPosition(secondPosition).marketId, secondMarket, "second market ID");
        assertEq(floan.getPosition(thirdPosition).borrower, otherBorrower, "third borrower");
        assertEq(floan.getPositionIdsForBorrower(otherFacility).length, 0, "empty borrower index");
    }
}
