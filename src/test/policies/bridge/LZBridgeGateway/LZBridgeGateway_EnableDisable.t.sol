// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Enable/disable lifecycle.
contract LZBridgeGatewayTests_EnableDisable is LZBridgeGatewayTestBase {
    function test_enable() external {
        vm.startPrank(admin);
        gateway.disable(bytes(""));
        assertFalse(gateway.isEnabled(), "Should be disabled");

        gateway.enable(bytes(""));
        assertTrue(gateway.isEnabled(), "Should be enabled");
        vm.stopPrank();
    }

    function test_enable_revertsIfAlreadyEnabled() external {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
        vm.prank(admin);
        gateway.enable(bytes(""));
    }

    function testFuzz_enable_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        // Disable first so enable is valid
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        gateway.enable(bytes(""));
    }

    function test_disable() external {
        vm.prank(admin);
        gateway.disable(bytes(""));
        assertFalse(gateway.isEnabled(), "Should be disabled");
    }

    function test_disable_revertsIfAlreadyDisabled() external {
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(admin);
        gateway.disable(bytes(""));
    }

    function testFuzz_disable_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.disable(bytes(""));
    }
}
