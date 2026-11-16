// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

// Constants
import {BRIDGE_CONFIGURATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Tests for `LZBridgeGateway.setGracePeriod`. The setter is gated to the
///      `bridge_configurator` role, requires the gateway to be enabled, and rejects a zero
///      window through the parent's `_setGracePeriod` helper.
contract LZBridgeGatewayTests_SetGracePeriod is LZBridgeGatewayTestBase {
    // ========== SUCCESS ========== //

    function test_setGracePeriod_succeedsWhileEnabled() external {
        // The gateway is enabled by the test base, which is the lifecycle state the setter
        // requires.
        assertTrue(gateway.isEnabled(), "Gateway should start enabled in the test base");

        uint32 newPeriod = GRACE_SECONDS * 2;

        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(newPeriod);
        vm.prank(bridgeConfigurator);
        gateway.setGracePeriod(newPeriod);

        assertEq(
            gateway.gracePeriod(),
            newPeriod,
            "gracePeriod should reflect the value set by the configurator"
        );
    }

    function test_setGracePeriod_acceptsMinNonZeroPeriod() external {
        vm.prank(bridgeConfigurator);
        gateway.setGracePeriod(1);

        assertEq(gateway.gracePeriod(), 1, "gracePeriod should accept one second");
    }

    function test_setGracePeriod_acceptsMaxPeriod() external {
        vm.prank(bridgeConfigurator);
        gateway.setGracePeriod(type(uint32).max);

        assertEq(
            gateway.gracePeriod(),
            type(uint32).max,
            "gracePeriod should accept the uint32 maximum"
        );
    }

    function test_setGracePeriod_overwritesPreviousValue() external {
        vm.startPrank(bridgeConfigurator);
        gateway.setGracePeriod(GRACE_SECONDS * 2);
        gateway.setGracePeriod(GRACE_SECONDS * 3);
        vm.stopPrank();

        assertEq(
            gateway.gracePeriod(),
            GRACE_SECONDS * 3,
            "gracePeriod should reflect the most recent value"
        );
    }

    /// @dev An increase in the grace period extends the deadline measured from
    ///      `lastTransitionAt`, so a re-enable that would have expired under the original
    ///      window succeeds after the increase. The window is set while the gateway is
    ///      enabled and then carried into the disabled state by the subsequent `disable`.
    function test_setGracePeriod_extendedWindowAllowsLateReEnable() external {
        uint32 newPeriod = GRACE_SECONDS * 2;
        vm.prank(bridgeConfigurator);
        gateway.setGracePeriod(newPeriod);

        vm.prank(admin);
        gateway.disable(bytes(""));
        uint48 disabledAt = gateway.lastTransitionAt();

        // Warp past the original deadline but inside the new one. Without the increase,
        // `reEnable` would revert with `GracePeriod_Expired`.
        vm.warp(uint256(disabledAt) + uint256(GRACE_SECONDS) + 1);

        vm.prank(manager);
        gateway.reEnable();

        assertTrue(gateway.isEnabled(), "Gateway should re-enable inside the extended window");
    }

    /// @dev A decrease in the grace period shortens the deadline measured from
    ///      `lastTransitionAt`, so a re-enable that would have succeeded under the original
    ///      window reverts after the decrease. The window is set while the gateway is
    ///      enabled and then carried into the disabled state by the subsequent `disable`.
    function test_setGracePeriod_shortenedWindowRejectsLateReEnable() external {
        uint32 newPeriod = GRACE_SECONDS / 2;
        vm.prank(bridgeConfigurator);
        gateway.setGracePeriod(newPeriod);

        vm.prank(admin);
        gateway.disable(bytes(""));
        uint48 disabledAt = gateway.lastTransitionAt();

        uint48 newDeadline = disabledAt + newPeriod;
        vm.warp(uint256(newDeadline) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, newDeadline)
        );
        vm.prank(manager);
        gateway.reEnable();
    }

    // ========== REVERTS ========== //

    function test_setGracePeriod_revertsWhileDisabled() external {
        vm.prank(admin);
        gateway.disable(bytes(""));
        assertFalse(gateway.isEnabled(), "Gateway should be disabled before the setter call");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(bridgeConfigurator);
        gateway.setGracePeriod(GRACE_SECONDS * 2);
    }

    function test_setGracePeriod_revertsIfZeroPeriod() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(bridgeConfigurator);
        gateway.setGracePeriod(0);
    }

    function testFuzz_setGracePeriod_revertsIfNotBridgeConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfigurator);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        gateway.setGracePeriod(GRACE_SECONDS * 2);
    }

    function test_setGracePeriod_isNotCallableByAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(admin);
        gateway.setGracePeriod(GRACE_SECONDS * 2);
    }

    function test_setGracePeriod_isNotCallableByBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(bridgeAdmin);
        gateway.setGracePeriod(GRACE_SECONDS * 2);
    }

    function test_setGracePeriod_isNotCallableByManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(manager);
        gateway.setGracePeriod(GRACE_SECONDS * 2);
    }
}
