// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/interfaces/IReEnabler.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Constants
import {MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev `reEnable()` lifecycle and access control.
contract LZBridgeGatewayTests_ReEnable is LZBridgeGatewayTestBase {
    function test_reEnable_succeedsForManagerWithinGrace() external {
        vm.prank(admin);
        gateway.disable(bytes(""));
        assertFalse(gateway.isEnabled(), "Gateway should be disabled");
        assertFalse(gateway.isReceiveEnabled(), "isReceiveEnabled should be false after disable");

        vm.warp(block.timestamp + (GRACE_SECONDS - 1));

        vm.prank(manager);
        gateway.reEnable();

        assertTrue(gateway.isEnabled(), "Gateway should be enabled after reEnable");
        assertTrue(
            gateway.isReceiveEnabled(),
            "isReceiveEnabled should be restored after reEnable"
        );
        assertEq(
            uint256(gateway.lastTransitionAt()),
            uint256(uint48(block.timestamp)),
            "lastTransitionAt should be refreshed by reEnable"
        );
    }

    function test_reEnable_emitsLegacyAndTransitionEvents() external {
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.warp(block.timestamp + 1);

        vm.expectEmit(false, false, false, false);
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true);
        emit IEnablerV2.Transition(manager, true, bytes(""), uint48(block.timestamp));
        vm.prank(manager);
        gateway.reEnable();
    }

    function test_reEnable_secondCycleSucceeds() external {
        // First disable + reEnable
        vm.prank(admin);
        gateway.disable(bytes(""));
        vm.warp(block.timestamp + 10);
        vm.prank(manager);
        gateway.reEnable();
        assertTrue(gateway.isEnabled(), "Gateway should be enabled after first reEnable");

        // Disable again, then reEnable again — confirms the contract supports
        // repeated re-enable cycles.
        vm.prank(admin);
        gateway.disable(bytes(""));
        assertFalse(gateway.isEnabled(), "Gateway should be disabled after second disable");

        vm.warp(block.timestamp + 10);
        vm.prank(manager);
        gateway.reEnable();
        assertTrue(gateway.isEnabled(), "Gateway should be enabled after second reEnable");
        assertTrue(
            gateway.isReceiveEnabled(),
            "isReceiveEnabled should be restored after second reEnable"
        );
    }

    function test_reEnable_revertsIfAlreadyEnabled() external {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
        vm.prank(manager);
        gateway.reEnable();
    }

    function testFuzz_reEnable_revertsIfNotManager(address caller_) external {
        vm.assume(caller_ != manager);
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, MANAGER_ROLE));
        vm.prank(caller_);
        gateway.reEnable();
    }

    function test_reEnable_revertsAfterGraceExpires() external {
        vm.prank(admin);
        gateway.disable(bytes(""));
        uint48 disabledAt = gateway.lastTransitionAt();
        uint48 deadline = disabledAt + GRACE_SECONDS;

        // Move strictly past the deadline.
        vm.warp(uint256(deadline) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(manager);
        gateway.reEnable();
    }

    function test_reEnable_revertsIfNeverEnabled() external {
        // Fresh gateway that has never been enabled.
        LZBridgeGateway fresh = new LZBridgeGateway(
            kernel,
            address(endpointSetup.endpointList[0]),
            true,
            GRACE_SECONDS
        );

        vm.expectRevert(abi.encodeWithSelector(IReEnabler.NeverEnabled.selector));
        vm.prank(manager);
        fresh.reEnable();
    }

    function test_reEnable_isNotCallableByAdmin() external {
        // Admin holds enable/disable authority but is intentionally not authorised
        // for `reEnable` (admin can already invoke `enable("")`).
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, MANAGER_ROLE));
        vm.prank(admin);
        gateway.reEnable();
    }
}
