// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketFacilityTest is FLOANTest {
    function test_setMarketFacility_movesLookupAuthorityAndPrincipal() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(manager);
        floan.setMarketFacility(marketId, otherFacility);

        (bool oldExists, ) = floan.getMarketId(facility, collateralToken, debtToken);
        (bool newExists, uint32 newMarketId) = floan.getMarketId(
            otherFacility,
            collateralToken,
            debtToken
        );
        assertFalse(oldExists, "old lookup should be cleared");
        assertTrue(newExists, "new lookup should exist");
        assertEq(newMarketId, marketId, "new lookup market id");
        assertEq(floan.facilityPrincipalDue(facility, debtToken), 0, "old facility principal");
        assertEq(
            floan.facilityPrincipalDue(otherFacility, debtToken),
            100e9,
            "new facility principal"
        );
        assertEq(floan.marketPrincipalDue(marketId), 100e9, "market principal");
        assertEq(floan.debtTokenPrincipalDue(debtToken), 100e9, "debt token principal");

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, facility)
        );
        floan.addCollateral(positionId, 1);

        vm.prank(otherFacility);
        assertEq(floan.addCollateral(positionId, 1), 1, "new facility collateral mutation");
    }

    function test_setMarketFacility_givenDuplicateTargetPair_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createMarket(manager, otherFacility, collateralToken, debtToken, 1_000e9);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFLOANv1.FLOAN_MarketAlreadyExists.selector,
                otherFacility,
                collateralToken,
                debtToken
            )
        );
        floan.setMarketFacility(marketId, otherFacility);
    }

    function test_setMarketFacility_givenZeroPrincipal_movesLookupWithoutDebtDust() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(manager);
        floan.setMarketFacility(marketId, otherFacility);

        assertEq(floan.facilityPrincipalDue(facility, debtToken), 0, "old facility principal");
        assertEq(floan.facilityPrincipalDue(otherFacility, debtToken), 0, "new facility principal");
        assertEq(floan.debtTokenPrincipalDue(debtToken), 0, "debt token principal");
    }

    function test_setMarketFacility_givenUnauthorizedManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(otherManager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, otherManager)
        );
        floan.setMarketFacility(marketId, otherFacility);
    }

    function test_setMarketFacility_givenZeroFacility_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.setMarketFacility(marketId, address(0));
    }
}
