// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {Module} from "src/Kernel.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANCreateMarketTest is FLOANTest {
    // createMarket
    // given caller without kernel permission
    //  when createMarket is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_createMarket_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.createMarket(_market(manager, facility, collateralToken, debtToken, 1_000e9), hex"");
    }

    // createMarket
    // given a valid market configuration
    //  when createMarket is called
    //   then it stores market config and lookup
    function test_createMarket_storesMarketConfigAndLookup() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        IFLOANv1.Market memory market = floan.getMarket(marketId);
        uint256[] memory lookupIds = floan.getMarketIds(facility, collateralToken, debtToken);

        assertEq(market.facility, facility, "facility");
        assertEq(market.manager, manager, "manager");
        assertEq(abi.decode(floan.getMarketConfigData(marketId), (uint256)), 123, "config data");
        assertEq(lookupIds.length, 1, "lookup market count");
        assertEq(lookupIds[0], marketId, "lookup market id");
    }

    // createMarket
    // given duplicate facility and pair
    //  when createMarket is called
    //   then it stores both markets
    function test_createMarket_givenDuplicateFacilityAndPair_storesBothMarkets() public {
        uint32 first = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 second = _createMarket(manager, facility, collateralToken, debtToken, 2_000e9);

        uint256[] memory lookupIds = floan.getMarketIds(facility, collateralToken, debtToken);

        assertEq(lookupIds.length, 2, "lookup market count");
        assertEq(lookupIds[0], first, "first lookup market id");
        assertEq(lookupIds[1], second, "second lookup market id");
    }

    // createMarket
    // given different facility or token
    //  when createMarket is called
    //   then it succeeds
    function test_createMarket_givenDifferentFacilityOrToken_succeeds() public {
        uint32 first = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 second = _createMarket(manager, otherFacility, collateralToken, debtToken, 1_000e9);
        uint32 third = _createMarket(manager, facility, otherCollateralToken, debtToken, 1_000e9);

        assertEq(first, 0, "first market id");
        assertEq(second, 1, "second market id");
        assertEq(third, 2, "third market id");
    }

    // createMarket
    // given zero identity address
    //  when createMarket is called
    //   then it reverts
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

    // createMarket
    // given invalid fixed term config
    //  when createMarket is called
    //   then it reverts
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
