// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {Module} from "src/Kernel.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketConfigTest is FLOANTest {
    // setMarketConfig
    // given caller without kernel permission
    //  when setMarketConfig is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_setMarketConfig_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        IFLOANv1.Market memory market = floan.getMarket(marketId);
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.setMarketConfig(marketId, market, hex"");
    }

    // setMarketConfig
    // given manager
    //  when setMarketConfig is called
    //   then it updates mutable fields and opaque data
    function test_givenManager_setMarketConfig_updatesMutableFieldsAndOpaqueData() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        IFLOANv1.Market memory updated = floan.getMarket(marketId);
        updated.principalCap = 2_000e9;
        updated.termLength = 60 days;
        updated.maxMaturityHorizon = type(uint48).max;
        updated.collateralFactorBps = 8_000;
        updated.minCollateralRatioBps = 15_000;
        updated.baseFeeBps = 250;
        bytes memory configData = abi.encode("updated");

        vm.prank(manager);
        floan.setMarketConfig(marketId, updated, configData);

        assertEq(abi.encode(floan.getMarket(marketId)), abi.encode(updated), "market config");
        assertEq(floan.getMarketConfigData(marketId), configData, "config data");
    }

    // setMarketConfig
    // given originations disabled
    //  when setMarketConfig is called
    //   then it preserves disabled state
    function test_givenOriginationsDisabled_setMarketConfig_preservesDisabledState() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.startPrank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);
        IFLOANv1.Market memory updated = floan.getMarket(marketId);
        updated.originationsEnabled = true;
        updated.baseFeeBps = 200;
        floan.setMarketConfig(marketId, updated, hex"12");
        vm.stopPrank();

        assertFalse(floan.getMarket(marketId).originationsEnabled, "originations state");
    }

    // setMarketConfig
    // given cap at live principal
    //  when setMarketConfig is called
    //   then it succeeds and one below reverts
    function test_givenCapAtLivePrincipal_setMarketConfig_succeedsAndOneBelowReverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createPositionWithDebt(marketId, facility, borrower, 100e9);
        IFLOANv1.Market memory updated = floan.getMarket(marketId);
        updated.principalCap = 100e9;
        vm.prank(manager);
        floan.setMarketConfig(marketId, updated, hex"");

        updated.principalCap = 100e9 - 1;
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.setMarketConfig(marketId, updated, hex"");
        assertEq(floan.getMarket(marketId).principalCap, 100e9, "principal cap unchanged");
    }

    // setMarketConfig
    // given changed identity
    //  when setMarketConfig is called
    //   then it reverts
    function test_givenChangedIdentity_setMarketConfig_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        IFLOANv1.Market memory updated = floan.getMarket(marketId);
        updated.collateralToken = otherCollateralToken;

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.setMarketConfig(marketId, updated, hex"");
    }

    // setMarketConfig
    // given permissioned non manager
    //  when setMarketConfig is called
    //   then it reverts
    function test_givenPermissionedNonManager_setMarketConfig_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        IFLOANv1.Market memory updated = floan.getMarket(marketId);

        vm.prank(otherManager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, otherManager)
        );
        floan.setMarketConfig(marketId, updated, hex"");
    }
}
