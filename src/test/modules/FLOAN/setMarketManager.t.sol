// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {Module} from "src/Kernel.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketManagerTest is FLOANTest {
    function test_givenCallerWithoutKernelPermission_setMarketManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.setMarketManager(marketId, otherManager);
    }

    function test_givenCurrentManager_setMarketManager_transfersConfigurationAuthority() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(manager);
        floan.setMarketManager(marketId, otherManager);

        assertEq(floan.getMarket(marketId).manager, otherManager, "manager");
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, manager)
        );
        floan.setMarketManager(marketId, manager);
        vm.prank(otherManager);
        floan.setMarketManager(marketId, manager);
        assertEq(floan.getMarket(marketId).manager, manager, "restored manager");
    }

    function test_givenZeroManager_setMarketManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.setMarketManager(marketId, address(0));
    }

    function test_givenPermissionedNonManager_setMarketManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(otherManager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, otherManager)
        );
        floan.setMarketManager(marketId, otherManager);
    }
}
