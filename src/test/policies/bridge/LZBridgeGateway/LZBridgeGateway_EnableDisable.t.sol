// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {Vm} from "forge-std/Vm.sol";

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Enable/disable lifecycle.
contract LZBridgeGatewayTests_EnableDisable is LZBridgeGatewayTestBase {
    function test_enable_updatesLastTransitionAt() external {
        vm.startPrank(admin);
        gateway.disable(bytes(""));
        uint48 disabledAt = gateway.lastTransitionAt();
        assertGt(uint256(disabledAt), 0, "lastTransitionAt should be non-zero after disable");

        vm.warp(vm.getBlockTimestamp() + 30);
        gateway.enable(bytes(""));
        assertEq(
            uint256(gateway.lastTransitionAt()),
            uint256(uint48(vm.getBlockTimestamp())),
            "lastTransitionAt should be refreshed on enable"
        );
        vm.stopPrank();
    }

    function test_enable_emitsTransitionEvent() external {
        vm.startPrank(admin);
        gateway.disable(bytes(""));

        vm.expectEmit(true, true, false, true);
        emit IEnablerV2.Transition(admin, true, bytes(""), uint48(vm.getBlockTimestamp()));
        gateway.enable(bytes(""));
        vm.stopPrank();
    }

    function test_enable() external {
        vm.startPrank(admin);
        gateway.disable(bytes(""));
        assertFalse(gateway.isEnabled(), "Should be disabled");

        gateway.enable(bytes(""));
        assertTrue(gateway.isEnabled(), "Should be enabled");
        vm.stopPrank();
    }

    function test_enable_setsIsReceiveEnabledTrue() external {
        vm.startPrank(admin);
        gateway.disable(bytes(""));
        assertFalse(gateway.isReceiveEnabled(), "isReceiveEnabled should be false after disable");

        gateway.enable(bytes(""));
        assertTrue(gateway.isReceiveEnabled(), "enable should set isReceiveEnabled to true");
        vm.stopPrank();
    }

    function test_enable_skipsIsReceiveEnabledEventIfAlreadyTrue() external {
        vm.startPrank(admin);
        gateway.disable(bytes(""));
        gateway.setIsReceiveEnabled(true);
        assertTrue(gateway.isReceiveEnabled(), "isReceiveEnabled should be true after manual set");

        // enable() should NOT emit IsReceiveEnabledSet because it is already true
        vm.recordLogs();
        gateway.enable(bytes(""));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSig = ILZBridgeGateway.IsReceiveEnabledSet.selector;
        for (uint256 i = 0; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != eventSig, "Should not emit IsReceiveEnabledSet");
        }
        assertTrue(gateway.isReceiveEnabled(), "isReceiveEnabled should remain true after enable");
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

    function test_disable_setsIsReceiveEnabledFalse() external {
        assertTrue(gateway.isReceiveEnabled(), "isReceiveEnabled should be true after setUp");

        vm.startPrank(admin);

        // Enable receive while disabled
        gateway.disable(bytes(""));
        gateway.setIsReceiveEnabled(true);
        assertTrue(gateway.isReceiveEnabled(), "isReceiveEnabled should be true");

        // Re-enable, then disable again, isReceiveEnabled should be reset
        gateway.enable(bytes(""));
        gateway.disable(bytes(""));
        assertFalse(gateway.isReceiveEnabled(), "disable should reset isReceiveEnabled");

        vm.stopPrank();
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
