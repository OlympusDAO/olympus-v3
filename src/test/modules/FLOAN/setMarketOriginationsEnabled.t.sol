// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {Module} from "src/Kernel.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketOriginationsEnabledTest is FLOANTest {
    // setMarketOriginationsEnabled
    // given caller without kernel permission
    //  when setMarketOriginationsEnabled is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_setMarketOriginationsEnabled_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.setMarketOriginationsEnabled(marketId, false);
    }

    // setMarketOriginationsEnabled
    // given manager
    //  when setMarketOriginationsEnabled is called
    //   then it updates state both ways
    function test_givenManager_setMarketOriginationsEnabled_updatesStateBothWays() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.startPrank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);
        assertFalse(floan.getMarket(marketId).originationsEnabled, "originations disabled");
        floan.setMarketOriginationsEnabled(marketId, true);
        vm.stopPrank();
        assertTrue(floan.getMarket(marketId).originationsEnabled, "originations enabled");
    }

    // setMarketOriginationsEnabled
    // given permissioned non manager
    //  when setMarketOriginationsEnabled is called
    //   then it reverts
    function test_givenPermissionedNonManager_setMarketOriginationsEnabled_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(otherManager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, otherManager)
        );
        floan.setMarketOriginationsEnabled(marketId, false);
    }
}
