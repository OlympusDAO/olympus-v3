// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";

/// @dev `setGracePeriod` is gated to the configurator. The enabled-state precondition from
///      `ReEnablerGracePeriod` still applies.
contract LZCrossChainBridgeTests_SetGracePeriod is LZCrossChainBridgeTestBase {
    // ========== SUCCESS ========== //

    function test_setGracePeriod_configuratorCanCallWhileEnabled() external {
        assertTrue(bridge.isEnabled(), "Bridge should start enabled in the test base");

        uint32 newPeriod = GRACE_SECONDS * 2;

        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(newPeriod);
        vm.prank(bridgeConfiguratorContract);
        bridge.setGracePeriod(newPeriod);

        assertEq(
            bridge.gracePeriod(),
            newPeriod,
            "gracePeriod should reflect the value set by the configurator"
        );
    }

    function test_setGracePeriod_acceptsMinNonZeroPeriod() external {
        vm.prank(bridgeConfiguratorContract);
        bridge.setGracePeriod(1);

        assertEq(bridge.gracePeriod(), 1, "gracePeriod should accept one second");
    }

    function test_setGracePeriod_acceptsMaxPeriod() external {
        vm.prank(bridgeConfiguratorContract);
        bridge.setGracePeriod(type(uint32).max);

        assertEq(
            bridge.gracePeriod(),
            type(uint32).max,
            "gracePeriod should accept the uint32 maximum"
        );
    }

    function test_setGracePeriod_overwritesPreviousValue() external {
        vm.startPrank(bridgeConfiguratorContract);
        bridge.setGracePeriod(GRACE_SECONDS * 2);
        bridge.setGracePeriod(GRACE_SECONDS * 3);
        vm.stopPrank();

        assertEq(
            bridge.gracePeriod(),
            GRACE_SECONDS * 3,
            "gracePeriod should reflect the most recent value"
        );
    }

    // ========== REVERTS ========== //

    function test_setGracePeriod_revertsIfZeroPeriod() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(bridgeConfiguratorContract);
        bridge.setGracePeriod(0);
    }

    function test_setGracePeriod_revertsIfOwner() external {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, owner, "configurator")
        );
        vm.prank(owner);
        bridge.setGracePeriod(GRACE_SECONDS * 2);
    }

    function testFuzz_setGracePeriod_revertsIfNotConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfiguratorContract);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, caller_, "configurator")
        );
        vm.prank(caller_);
        bridge.setGracePeriod(GRACE_SECONDS * 2);
    }

    function test_setGracePeriod_revertsWhileDisabled() external {
        vm.prank(owner);
        bridge.disable(bytes(""));
        assertFalse(bridge.isEnabled(), "Bridge should be disabled before the setter call");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(bridgeConfiguratorContract);
        bridge.setGracePeriod(GRACE_SECONDS * 2);
    }
}
