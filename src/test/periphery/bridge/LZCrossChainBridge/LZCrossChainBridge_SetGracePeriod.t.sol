// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

contract LZCrossChainBridgeTests_SetGracePeriod is LZCrossChainBridgeTestBase {
    // ========== SUCCESS ========== //

    function test_setGracePeriod_succeedsWhileEnabled() external {
        // The bridge is enabled by the test base. The setter requires the bridge
        // to be in the enabled state.
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

    function test_setGracePeriod_revertsWhileDisabled() external {
        bridge.disable(bytes(""));
        assertFalse(bridge.isEnabled(), "Bridge should be disabled before the setter call");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        bridge.setGracePeriod(GRACE_SECONDS * 2);
    }
}
