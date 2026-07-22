// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

import {FLOANTest} from "./FLOANTest.sol";

contract FLOANExtendMaturityTest is FLOANTest {
    // extendMaturity
    // given caller without kernel permission
    //  when extendMaturity is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        _expectKernelPermissionRevert(caller_);
        floan.extendMaturity(positionId, uint48(block.timestamp + 60 days));
    }

    // extendMaturity
    // given caller is not the position market facility
    //  when extendMaturity is called
    //   then it reverts
    function test_givenCallerIsNotPositionMarketFacility_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.extendMaturity(positionId, uint48(block.timestamp + 60 days));
    }

    // extendMaturity
    // given originations disabled
    //  when extendMaturity is called
    //   then it reverts without state change
    function test_givenOriginationsDisabled_revertsWithoutStateChange() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        uint48 maturity = floan.getPosition(positionId).maturity;
        vm.prank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_OriginationsDisabled.selector, marketId)
        );
        floan.extendMaturity(positionId, maturity + 30 days);
        assertEq(floan.getPosition(positionId).maturity, maturity, "maturity unchanged");
    }

    // extendMaturity
    // given a defaulted position
    //  when extendMaturity is called
    //   then it reverts
    function test_givenDefaultedPosition_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.startPrank(facility);
        floan.defaultPosition(positionId);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_PositionDefaulted.selector, positionId)
        );
        floan.extendMaturity(positionId, uint48(block.timestamp + 60 days));
        vm.stopPrank();
    }

    // extendMaturity
    // given no debt
    //  when extendMaturity is called
    //   then it reverts
    function test_givenNoDebt_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);

        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.extendMaturity(positionId, uint48(block.timestamp + 30 days));
    }

    // extendMaturity
    // given maturity does not increase
    //  when extendMaturity is called
    //   then it reverts
    function test_givenMaturityDoesNotIncrease_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        uint48 maturity = floan.getPosition(positionId).maturity;

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMaturity.selector, maturity, maturity)
        );
        floan.extendMaturity(positionId, maturity);
    }

    // extendMaturity
    // given a market with a finite maturity horizon
    //  when the facility extends exactly to the rolling horizon
    //   then the extension succeeds at the inclusive boundary
    function test_givenMaturityAtHorizon_succeeds() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        uint48 maximumMaturity = uint48(block.timestamp + 365 days);

        vm.prank(facility);
        IFLOANv1.Position memory position = floan.extendMaturity(positionId, maximumMaturity);

        assertEq(position.maturity, maximumMaturity, "maturity");
    }

    // extendMaturity
    // given a market with a finite maturity horizon
    //  when the facility extends one second beyond the rolling horizon
    //   then the call reverts and preserves maturity
    function test_givenMaturityAboveHorizon_revertsWithoutStateChange() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        uint48 oldMaturity = floan.getPosition(positionId).maturity;
        uint48 maximumMaturity = uint48(block.timestamp + 365 days);
        uint48 requestedMaturity = maximumMaturity + 1;

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFLOANv1.FLOAN_MaturityHorizonExceeded.selector,
                requestedMaturity,
                maximumMaturity
            )
        );
        floan.extendMaturity(positionId, requestedMaturity);

        assertEq(floan.getPosition(positionId).maturity, oldMaturity, "maturity unchanged");
    }

    // extendMaturity
    // given a market whose maturity horizon uses the unlimited sentinel
    //  when the facility extends to the maximum uint48 timestamp
    //   then no rolling-horizon limit is applied
    function test_givenUnlimitedMaturityHorizon_succeeds() public {
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        market.maxMaturityHorizon = type(uint48).max;
        vm.prank(manager);
        uint32 marketId = floan.createMarket(_marketInput(market), abi.encode(uint256(123)));
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(facility);
        IFLOANv1.Position memory position = floan.extendMaturity(positionId, type(uint48).max);

        assertEq(position.maturity, type(uint48).max, "maturity");
    }

    // extendMaturity
    // given active debt
    //  when extendMaturity is called
    //   then it updates only maturity
    function test_givenActiveDebt_updatesOnlyMaturity() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        IFLOANv1.Position memory beforePosition = floan.getPosition(positionId);
        uint48 newMaturity = beforePosition.maturity + 30 days;

        vm.prank(facility);
        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.PositionMaturityExtended(positionId, beforePosition.maturity, newMaturity);
        IFLOANv1.Position memory afterPosition = floan.extendMaturity(positionId, newMaturity);

        assertEq(afterPosition.maturity, newMaturity, "maturity");
        assertEq(afterPosition.collateral, beforePosition.collateral, "collateral");
        assertEq(afterPosition.principalDrawn, beforePosition.principalDrawn, "drawn");
        assertEq(afterPosition.principalDue, beforePosition.principalDue, "principal due");
        assertEq(afterPosition.interestDue, beforePosition.interestDue, "interest due");
        assertEq(afterPosition.lastBorrowBlock, beforePosition.lastBorrowBlock, "borrow block");
        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "market principal");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 100e9, "facility principal");
    }

    // extendMaturity
    // given a position with interest due but no principal due
    //  when extendMaturity is called
    //   then it extends the active interest-only debt episode
    function test_givenInterestOnlyDebt_succeeds() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 positionId = floan.createPosition(marketId, borrower);
        uint48 oldMaturity = uint48(block.timestamp + 30 days);
        floan.increaseDebt(positionId, 100e9, 25e9, oldMaturity);
        floan.decreaseDebt(positionId, 100e9, 0);
        uint48 newMaturity = oldMaturity + 30 days;
        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.PositionMaturityExtended(positionId, oldMaturity, newMaturity);
        IFLOANv1.Position memory position = floan.extendMaturity(positionId, newMaturity);
        vm.stopPrank();

        assertEq(position.principalDue, 0, "principal due");
        assertEq(position.interestDue, 25e9, "interest due");
        assertEq(position.maturity, newMaturity, "maturity");
    }

    // extendMaturity
    // given active debt and a debt-token extension charge
    //  when interest is accrued before extending maturity
    //   then both operations are recorded without changing principal
    function test_givenExtensionInterest_recordsInterestAndMaturity() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        IFLOANv1.Position memory before_ = floan.getPosition(positionId);
        uint48 newMaturity = before_.maturity + 30 days;

        vm.startPrank(facility);
        floan.increaseDebt(positionId, 0, 10e9, before_.maturity);
        floan.extendMaturity(positionId, newMaturity);
        vm.stopPrank();

        IFLOANv1.Position memory after_ = floan.getPosition(positionId);
        assertEq(after_.principalDrawn, 100e9, "principal drawn");
        assertEq(after_.principalDue, 100e9, "principal due");
        assertEq(after_.interestDue, 10e9, "interest due");
        assertEq(after_.maturity, newMaturity, "maturity");
        assertEq(after_.lastBorrowBlock, before_.lastBorrowBlock, "last principal increase block");
        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "market principal");
        assertEq(floan.getMarketInterestDue(marketId), 10e9, "market interest");
    }
}
