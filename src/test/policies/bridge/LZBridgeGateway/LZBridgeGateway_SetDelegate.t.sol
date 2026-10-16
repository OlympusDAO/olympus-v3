// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Constants
import {BRIDGE_CONFIGURATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev LZ endpoint delegate assignment. Gated to `bridge_configurator`; admin, bridge_admin,
///      and any other role have no direct path.
contract LZBridgeGatewayTests_SetDelegate is LZBridgeGatewayTestBase {
    function test_setDelegate_bridgeConfiguratorCanCall() external {
        address newDelegate = makeAddr("newDelegate");

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.DelegateSet(newDelegate);

        vm.prank(bridgeConfigurator);
        gateway.setDelegate(newDelegate);
    }

    function test_setDelegate_revertsIfAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(admin);
        gateway.setDelegate(makeAddr("delegate2"));
    }

    function test_setDelegate_revertsIfBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(bridgeAdmin);
        gateway.setDelegate(makeAddr("delegate2"));
    }

    function testFuzz_setDelegate_revertsIfNotBridgeConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfigurator);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        gateway.setDelegate(makeAddr("delegate2"));
    }

    function test_setDelegate_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "delegate"
            )
        );
        vm.prank(bridgeConfigurator);
        gateway.setDelegate(address(0));
    }
}
