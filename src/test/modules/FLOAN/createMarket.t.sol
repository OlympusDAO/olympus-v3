// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANCreateMarketTest is FLOANTest {
    function test_createMarket_storesMarketConfigAndLookup() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        IFLOANv1.Market memory market = floan.getMarket(marketId);
        (bool exists, uint32 lookupId) = floan.getMarketId(facility, collateralToken, debtToken);

        assertEq(market.facility, facility, "facility");
        assertEq(market.manager, manager, "manager");
        assertEq(abi.decode(floan.getMarketConfigData(marketId), (uint256)), 123, "config data");
        assertTrue(exists, "market should exist");
        assertEq(lookupId, marketId, "lookup market id");
    }

    function test_createMarket_givenDuplicateFacilityAndPair_reverts() public {
        _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFLOANv1.FLOAN_MarketAlreadyExists.selector,
                facility,
                collateralToken,
                debtToken
            )
        );
        _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
    }

    function test_createMarket_givenDifferentFacilityOrToken_succeeds() public {
        uint32 first = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 second = _createMarket(manager, otherFacility, collateralToken, debtToken, 1_000e9);
        uint32 third = _createMarket(manager, facility, otherCollateralToken, debtToken, 1_000e9);

        assertEq(first, 0, "first market id");
        assertEq(second, 1, "second market id");
        assertEq(third, 2, "third market id");
    }

    function test_createMarket_givenZeroIdentityAddress_reverts() public {
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );

        market.collateralToken = address(0);
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.createMarket(market, "");

        market.collateralToken = collateralToken;
        market.debtToken = address(0);
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.createMarket(market, "");

        market.debtToken = debtToken;
        market.manager = address(0);
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.createMarket(market, "");

        market.manager = manager;
        market.facility = address(0);
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.createMarket(market, "");
    }

    function test_createMarket_givenInvalidFixedTermConfig_reverts() public {
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );

        market.termLength = 0;
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.createMarket(market, "");

        market.termLength = 30 days;
        market.maxMaturityHorizon = 30 days;
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.createMarket(market, "");
    }
}
