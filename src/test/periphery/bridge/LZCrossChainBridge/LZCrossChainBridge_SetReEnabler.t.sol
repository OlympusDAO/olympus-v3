// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";

/// @dev `setReEnabler` is gated to the configurator.
contract LZCrossChainBridgeTests_SetReEnabler is LZCrossChainBridgeTestBase {
    function test_setReEnabler_configuratorCanCall() external {
        address newReEnabler = makeAddr("newReEnabler");

        vm.expectEmit(true, false, false, true);
        emit ILZCrossChainBridge.ReEnablerSet(newReEnabler);
        vm.prank(bridgeConfiguratorContract);
        bridge.setReEnabler(newReEnabler);

        assertEq(bridge.reEnabler(), newReEnabler, "ReEnabler should be updated");
    }

    function test_setReEnabler_acceptsZero() external {
        // The configurator is allowed to clear the re-enabler. While cleared, `reEnable()`
        // reverts.
        vm.prank(bridgeConfiguratorContract);
        bridge.setReEnabler(address(0));
        assertEq(bridge.reEnabler(), address(0), "ReEnabler should be cleared");
    }

    function test_setReEnabler_revertsIfOwner() external {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, owner, "configurator")
        );
        vm.prank(owner);
        bridge.setReEnabler(makeAddr("anything"));
    }

    function testFuzz_setReEnabler_revertsIfNotConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfiguratorContract);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, caller_, "configurator")
        );
        vm.prank(caller_);
        bridge.setReEnabler(makeAddr("anything"));
    }
}
