// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract LZCrossChainBridgeTests_EnableDisable is LZCrossChainBridgeTestBase {
    function test_enable() external {
        // Disable first
        bridge.disable(bytes(""));
        assertFalse(bridge.isEnabled(), "Should be disabled");

        bridge.enable(bytes(""));
        assertTrue(bridge.isEnabled(), "Should be enabled");
    }

    function testFuzz_enable_revertsIfAlreadyEnabled(address caller_) external {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
        vm.prank(caller_);
        bridge.enable(bytes(""));
    }

    function test_enable_revertsIfNotOwner() external {
        bridge.disable(bytes(""));

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(user);
        bridge.enable(bytes(""));
    }

    function test_disable() external {
        bridge.disable(bytes(""));
        assertFalse(bridge.isEnabled(), "Should be disabled");
    }

    function test_disable_revertsIfAlreadyDisabled() external {
        bridge.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        bridge.disable(bytes(""));
    }

    function testFuzz_disable_revertsIfNotOwner(address caller_) external {
        vm.assume(caller_ != owner);

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller_);
        bridge.disable(bytes(""));
    }
}
