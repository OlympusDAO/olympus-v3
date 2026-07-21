// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Module} from "src/Kernel.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

import {FLOANTest} from "./FLOANTest.sol";

contract FLOANExtendMaturityTest is FLOANTest {
    // extendMaturity
    // given caller without kernel permission
    //  when extendMaturity is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_extendMaturity_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.extendMaturity(positionId, uint48(block.timestamp + 60 days));
    }

    // extendMaturity
    // given permissioned non facility
    //  when extendMaturity is called
    //   then it reverts
    function test_givenPermissionedNonFacility_extendMaturity_reverts() public {
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
    function test_givenOriginationsDisabled_extendMaturity_revertsWithoutStateChange() public {
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
    // given no debt
    //  when extendMaturity is called
    //   then it reverts
    function test_givenNoDebt_extendMaturity_reverts() public {
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
    function test_givenMaturityDoesNotIncrease_extendMaturity_reverts() public {
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
    function test_givenMaturityAtHorizon_extendMaturity_succeeds() public {
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
    function test_givenMaturityAboveHorizon_extendMaturity_revertsWithoutStateChange() public {
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
    function test_givenUnlimitedMaturityHorizon_extendMaturity_succeeds() public {
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        market.maxMaturityHorizon = type(uint48).max;
        vm.prank(manager);
        uint32 marketId = floan.createMarket(market, abi.encode(uint256(123)));
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(facility);
        IFLOANv1.Position memory position = floan.extendMaturity(positionId, type(uint48).max);

        assertEq(position.maturity, type(uint48).max, "maturity");
    }

    // extendMaturity
    // given active debt
    //  when extendMaturity is called
    //   then it updates only maturity
    function test_givenActiveDebt_extendMaturity_updatesOnlyMaturity() public {
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
        assertEq(floan.marketPrincipalDue(marketId), 100e9, "market principal");
        assertEq(floan.facilityPrincipalDue(facility, debtToken), 100e9, "facility principal");
    }
}
