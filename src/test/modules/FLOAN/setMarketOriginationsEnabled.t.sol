// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketOriginationsEnabledTest is FLOANTest {
    // setMarketOriginationsEnabled
    // given the caller lacks Kernel permission
    //  when originations are set
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _expectKernelPermissionRevert(caller_);
        floan.setMarketOriginationsEnabled(marketId, false);
    }

    // setMarketOriginationsEnabled
    // given invalid market ID
    //  when originations are set
    //   then it reverts
    function test_givenInvalidMarket_reverts(uint32 marketId_) public {
        vm.assume(marketId_ != 0);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, marketId_));
        floan.setMarketOriginationsEnabled(marketId_, false);
    }

    // setMarketOriginationsEnabled
    // given a Kernel-permissioned caller that is not the market manager
    //  when originations are set
    //   then it reverts
    function test_givenCallerIsNotMarketManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(otherManager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, otherManager)
        );
        floan.setMarketOriginationsEnabled(marketId, false);
    }

    // setMarketOriginationsEnabled
    // given caller is the facility but not the market manager
    //  when originations are set
    //   then it reverts
    function test_givenCallerIsMarketFacilityButNotManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, facility)
        );
        floan.setMarketOriginationsEnabled(marketId, false);
    }

    // setMarketOriginationsEnabled
    // given enabled market
    //  when the manager enables originations again
    //   then it succeeds and emits the resulting state
    function test_givenAlreadyEnabled_succeeds() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.MarketOriginationsSet(marketId, true);
        vm.prank(manager);
        floan.setMarketOriginationsEnabled(marketId, true);

        assertTrue(floan.getMarket(marketId).originationsEnabled, "originations enabled");
    }

    // setMarketOriginationsEnabled
    // given disabled market
    //  when the manager disables originations again
    //   then it succeeds and emits the resulting state
    function test_givenAlreadyDisabled_succeeds() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);

        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.MarketOriginationsSet(marketId, false);
        vm.prank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);

        assertFalse(floan.getMarket(marketId).originationsEnabled, "originations disabled");
    }

    // setMarketOriginationsEnabled
    // given a market
    //  when the manager changes originations in either direction
    //   then only originations state changes
    function test_givenManager_updatesStateBothWays() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        IFLOANv1.Market memory expected = floan.getMarket(marketId);

        vm.startPrank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);
        assertFalse(floan.getMarket(marketId).originationsEnabled, "originations disabled");
        floan.setMarketOriginationsEnabled(marketId, true);
        vm.stopPrank();

        _assertMarket(marketId, expected);
    }
}
