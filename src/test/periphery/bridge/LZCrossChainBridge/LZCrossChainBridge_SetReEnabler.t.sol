// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

contract LZCrossChainBridgeTests_SetReEnabler is LZCrossChainBridgeTestBase {
    function test_setReEnabler_succeedsForOwner() external {
        address newReEnabler = makeAddr("newReEnabler");

        vm.expectEmit(true, false, false, true);
        emit ILZCrossChainBridge.ReEnablerSet(newReEnabler);
        bridge.setReEnabler(newReEnabler);

        assertEq(bridge.reEnabler(), newReEnabler, "ReEnabler should be updated");
    }

    function test_setReEnabler_acceptsZero() external {
        // Owner is allowed to clear the re-enabler. While cleared, `reEnable()` reverts.
        bridge.setReEnabler(address(0));
        assertEq(bridge.reEnabler(), address(0), "ReEnabler should be cleared");
    }

    function testFuzz_setReEnabler_revertsIfNotOwner(address caller_) external {
        vm.assume(caller_ != owner);

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller_);
        bridge.setReEnabler(makeAddr("anything"));
    }
}
