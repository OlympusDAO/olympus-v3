// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Tests for `LZBridgeGateway.setGracePeriod`. The setter is restricted to the
///      admin role and rejects a zero window through the parent's `_setGracePeriod`
///      helper.
contract LZBridgeGatewayTests_SetGracePeriod is LZBridgeGatewayTestBase {
    // ========== SUCCESS ========== //

    function test_setGracePeriod_succeedsWhileEnabled() external {
        // The gateway is enabled by the test base. The setter must not require a
        // particular lifecycle state.
        assertTrue(gateway.isEnabled(), "Gateway should start enabled in the test base");

        uint32 newPeriod = GRACE_SECONDS * 2;

        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(newPeriod);
        vm.prank(admin);
        gateway.setGracePeriod(newPeriod);

        assertEq(
            gateway.gracePeriod(),
            newPeriod,
            "gracePeriod should reflect the value set by the admin"
        );
    }

    function test_setGracePeriod_acceptsMinNonZeroPeriod() external {
        vm.prank(admin);
        gateway.setGracePeriod(1);

        assertEq(gateway.gracePeriod(), 1, "gracePeriod should accept one second");
    }

    function test_setGracePeriod_acceptsMaxPeriod() external {
        vm.prank(admin);
        gateway.setGracePeriod(type(uint32).max);

        assertEq(
            gateway.gracePeriod(),
            type(uint32).max,
            "gracePeriod should accept the uint32 maximum"
        );
    }

    function test_setGracePeriod_overwritesPreviousValue() external {
        vm.startPrank(admin);
        gateway.setGracePeriod(GRACE_SECONDS * 2);
        gateway.setGracePeriod(GRACE_SECONDS * 3);
        vm.stopPrank();

        assertEq(
            gateway.gracePeriod(),
            GRACE_SECONDS * 3,
            "gracePeriod should reflect the most recent value"
        );
    }

    function test_setGracePeriod_succeedsWhileDisabled() external {
        vm.prank(admin);
        gateway.disable(bytes(""));
        assertFalse(gateway.isEnabled(), "Gateway should be disabled before the setter call");

        vm.prank(admin);
        gateway.setGracePeriod(GRACE_SECONDS * 2);

        assertEq(
            gateway.gracePeriod(),
            GRACE_SECONDS * 2,
            "gracePeriod should be updatable while the gateway is disabled"
        );
    }

    /// @dev An increase in the grace period extends the deadline measured from
    ///      `lastTransitionAt`, so a re-enable that would have expired under the
    ///      original window succeeds after the increase.
    function test_setGracePeriod_extendedWindowAllowsLateReEnable() external {
        vm.prank(admin);
        gateway.disable(bytes(""));
        uint48 disabledAt = gateway.lastTransitionAt();

        // Double the grace window before the original deadline.
        uint32 newPeriod = GRACE_SECONDS * 2;
        vm.prank(admin);
        gateway.setGracePeriod(newPeriod);

        // Warp past the original deadline but inside the new one. Without the increase,
        // `reEnable` would revert with `GracePeriod_Expired`.
        vm.warp(uint256(disabledAt) + uint256(GRACE_SECONDS) + 1);

        vm.prank(manager);
        gateway.reEnable();

        assertTrue(gateway.isEnabled(), "Gateway should re-enable inside the extended window");
    }

    /// @dev A decrease in the grace period shortens the deadline measured from
    ///      `lastTransitionAt`, so a re-enable that would have succeeded under the
    ///      original window reverts after the decrease.
    function test_setGracePeriod_shortenedWindowRejectsLateReEnable() external {
        vm.prank(admin);
        gateway.disable(bytes(""));
        uint48 disabledAt = gateway.lastTransitionAt();

        // Halve the grace window.
        uint32 newPeriod = GRACE_SECONDS / 2;
        vm.prank(admin);
        gateway.setGracePeriod(newPeriod);

        // Warp past the new deadline but still inside the original one.
        uint48 newDeadline = disabledAt + newPeriod;
        vm.warp(uint256(newDeadline) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, newDeadline)
        );
        vm.prank(manager);
        gateway.reEnable();
    }

    // ========== REVERTS ========== //

    function test_setGracePeriod_revertsIfZeroPeriod() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        gateway.setGracePeriod(0);
    }

    function testFuzz_setGracePeriod_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        gateway.setGracePeriod(GRACE_SECONDS * 2);
    }

    function test_setGracePeriod_isNotCallableByBridgeAdmin() external {
        // The bridge_admin role is intentionally not authorised for setGracePeriod —
        // only the admin role is.
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(bridgeAdmin);
        gateway.setGracePeriod(GRACE_SECONDS * 2);
    }

    function test_setGracePeriod_isNotCallableByManager() external {
        // The manager role authorises `reEnable` but is intentionally not authorised
        // for setGracePeriod — only the admin role is.
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(manager);
        gateway.setGracePeriod(GRACE_SECONDS * 2);
    }
}
