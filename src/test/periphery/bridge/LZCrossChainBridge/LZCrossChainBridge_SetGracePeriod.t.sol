// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

contract LZCrossChainBridgeTests_SetGracePeriod is LZCrossChainBridgeTestBase {
    // ========== SUCCESS ========== //

    function test_setGracePeriod_succeedsWhileEnabled() external {
        // The bridge is enabled by the test base. The setter must not require a
        // particular lifecycle state.
        assertTrue(bridge.isEnabled(), "Bridge should start enabled in the test base");

        uint32 newPeriod = GRACE_SECONDS * 2;

        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(newPeriod);
        bridge.setGracePeriod(newPeriod);

        assertEq(
            bridge.gracePeriod(),
            newPeriod,
            "gracePeriod should reflect the value set by the owner"
        );
    }

    function test_setGracePeriod_acceptsMinNonZeroPeriod() external {
        bridge.setGracePeriod(1);

        assertEq(bridge.gracePeriod(), 1, "gracePeriod should accept one second");
    }

    function test_setGracePeriod_acceptsMaxPeriod() external {
        bridge.setGracePeriod(type(uint32).max);

        assertEq(
            bridge.gracePeriod(),
            type(uint32).max,
            "gracePeriod should accept the uint32 maximum"
        );
    }

    function test_setGracePeriod_overwritesPreviousValue() external {
        bridge.setGracePeriod(GRACE_SECONDS * 2);
        bridge.setGracePeriod(GRACE_SECONDS * 3);

        assertEq(
            bridge.gracePeriod(),
            GRACE_SECONDS * 3,
            "gracePeriod should reflect the most recent value"
        );
    }

    function test_setGracePeriod_succeedsWhileDisabled() external {
        bridge.disable(bytes(""));
        assertFalse(bridge.isEnabled(), "Bridge should be disabled before the setter call");

        bridge.setGracePeriod(GRACE_SECONDS * 2);

        assertEq(
            bridge.gracePeriod(),
            GRACE_SECONDS * 2,
            "gracePeriod should be updatable while the bridge is disabled"
        );
    }

    /// @dev An increase in the grace period extends the deadline measured from
    ///      `lastTransitionAt`, so a re-enable that would have expired under the original
    ///      window succeeds after the increase.
    function test_setGracePeriod_extendedWindowAllowsLateReEnable() external {
        bridge.disable(bytes(""));
        uint48 disabledAt = bridge.lastTransitionAt();

        // Double the grace window before the original deadline.
        uint32 newPeriod = GRACE_SECONDS * 2;
        bridge.setGracePeriod(newPeriod);

        // Warp past the original deadline but inside the new one. Without the increase,
        // `reEnable` would revert with `GracePeriod_Expired`.
        vm.warp(uint256(disabledAt) + uint256(GRACE_SECONDS) + 1);

        vm.prank(reEnablerAddr);
        bridge.reEnable();

        assertTrue(bridge.isEnabled(), "Bridge should re-enable inside the extended window");
    }

    /// @dev A decrease in the grace period shortens the deadline measured from
    ///      `lastTransitionAt`, so a re-enable that would have succeeded under the
    ///      original window reverts after the decrease.
    function test_setGracePeriod_shortenedWindowRejectsLateReEnable() external {
        bridge.disable(bytes(""));
        uint48 disabledAt = bridge.lastTransitionAt();

        // Halve the grace window.
        uint32 newPeriod = GRACE_SECONDS / 2;
        bridge.setGracePeriod(newPeriod);

        // Warp past the new deadline but still inside the original one.
        uint48 newDeadline = disabledAt + newPeriod;
        vm.warp(uint256(newDeadline) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, newDeadline)
        );
        vm.prank(reEnablerAddr);
        bridge.reEnable();
    }

    // ========== REVERTS ========== //

    function test_setGracePeriod_revertsIfZeroPeriod() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        bridge.setGracePeriod(0);
    }

    function testFuzz_setGracePeriod_revertsIfNotOwner(address caller_) external {
        vm.assume(caller_ != owner);

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller_);
        bridge.setGracePeriod(GRACE_SECONDS * 2);
    }
}
