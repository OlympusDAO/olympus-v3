// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Module} from "src/Kernel.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

import {FLOANTest} from "./FLOANTest.sol";

contract FLOANExtendMaturityTest is FLOANTest {
    function test_givenCallerWithoutKernelPermission_extendMaturity_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.extendMaturity(positionId, uint48(block.timestamp + 60 days));
    }

    function test_givenPermissionedNonFacility_extendMaturity_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.extendMaturity(positionId, uint48(block.timestamp + 60 days));
    }

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

    function test_givenNoDebt_extendMaturity_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);

        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.extendMaturity(positionId, uint48(block.timestamp + 30 days));
    }

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
