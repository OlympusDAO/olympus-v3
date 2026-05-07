// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/interfaces/IReEnabler.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";

// Contracts
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";

contract LZCrossChainBridgeTests_ReEnable is LZCrossChainBridgeTestBase {
    function test_reEnable_succeedsForReEnablerWithinGrace() external {
        bridge.disable(bytes(""));
        assertFalse(bridge.isEnabled(), "Bridge should be disabled");

        vm.warp(block.timestamp + (GRACE_SECONDS - 1));

        vm.prank(reEnablerAddr);
        bridge.reEnable();

        assertTrue(bridge.isEnabled(), "Bridge should be enabled after reEnable");
        assertEq(
            uint256(bridge.lastTransitionAt()),
            uint256(uint48(block.timestamp)),
            "lastTransitionAt should be refreshed by reEnable"
        );
    }

    function test_reEnable_succeedsAtExactDeadline() external {
        bridge.disable(bytes(""));
        uint48 disabledAt = bridge.lastTransitionAt();

        vm.warp(uint256(disabledAt) + GRACE_SECONDS);

        vm.prank(reEnablerAddr);
        bridge.reEnable();

        assertTrue(bridge.isEnabled(), "Bridge should be enabled after reEnable at exact deadline");
        assertEq(
            uint256(bridge.lastTransitionAt()),
            uint256(uint48(block.timestamp)),
            "lastTransitionAt should be refreshed by reEnable at exact deadline"
        );
    }

    function test_reEnable_emitsLegacyAndTransitionEvents() external {
        bridge.disable(bytes(""));

        vm.warp(block.timestamp + 1);

        vm.expectEmit(false, false, false, false);
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true);
        emit IEnablerV2.Transition(reEnablerAddr, true, bytes(""), uint48(block.timestamp));
        vm.prank(reEnablerAddr);
        bridge.reEnable();
    }

    function test_reEnable_secondCycleSucceeds() external {
        // First disable + reEnable
        bridge.disable(bytes(""));
        vm.warp(block.timestamp + 10);
        vm.prank(reEnablerAddr);
        bridge.reEnable();
        assertTrue(bridge.isEnabled(), "Bridge should be enabled after first reEnable");

        // Disable again, then reEnable again — confirms repeated re-enable cycles.
        bridge.disable(bytes(""));
        assertFalse(bridge.isEnabled(), "Bridge should be disabled after second disable");

        vm.warp(block.timestamp + 10);
        vm.prank(reEnablerAddr);
        bridge.reEnable();
        assertTrue(bridge.isEnabled(), "Bridge should be enabled after second reEnable");
    }

    function test_reEnable_revertsIfAlreadyEnabled() external {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
        vm.prank(reEnablerAddr);
        bridge.reEnable();
    }

    function testFuzz_reEnable_revertsIfNotReEnabler(address caller_) external {
        vm.assume(caller_ != reEnablerAddr);
        bridge.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(Errors.Unauthorized.selector, caller_, "reEnabler"));
        vm.prank(caller_);
        bridge.reEnable();
    }

    function test_reEnable_revertsIfReEnablerCleared() external {
        bridge.disable(bytes(""));
        bridge.setReEnabler(address(0));

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, reEnablerAddr, "reEnabler")
        );
        vm.prank(reEnablerAddr);
        bridge.reEnable();
    }

    function test_reEnable_succeedsAtGraceDeadline() external {
        bridge.disable(bytes(""));
        uint48 disabledAt = bridge.lastTransitionAt();
        uint48 deadline = disabledAt + GRACE_SECONDS;

        vm.warp(uint256(deadline));

        vm.prank(reEnablerAddr);
        bridge.reEnable();

        assertTrue(bridge.isEnabled(), "Bridge should be enabled after reEnable at grace deadline");
        assertEq(
            uint256(bridge.lastTransitionAt()),
            uint256(uint48(block.timestamp)),
            "lastTransitionAt should be refreshed by reEnable at grace deadline"
        );
    }

    function test_reEnable_revertsAfterGraceExpires() external {
        bridge.disable(bytes(""));
        uint48 disabledAt = bridge.lastTransitionAt();
        uint48 deadline = disabledAt + GRACE_SECONDS;

        vm.warp(uint256(deadline) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(reEnablerAddr);
        bridge.reEnable();
    }

    function test_reEnable_revertsIfNeverEnabled() external {
        // Fresh bridge that has never been enabled.
        LZCrossChainBridge fresh = new LZCrossChainBridge(
            address(ohm),
            owner,
            address(gateway),
            reEnablerAddr,
            GRACE_SECONDS
        );

        vm.expectRevert(abi.encodeWithSelector(IReEnabler.NeverEnabled.selector));
        vm.prank(reEnablerAddr);
        fresh.reEnable();
    }

    function test_reEnable_isNotCallableByOwner() external {
        // Owner holds enable/disable authority but is not the configured re-enabler.
        bridge.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(Errors.Unauthorized.selector, owner, "reEnabler"));
        bridge.reEnable();
    }
}
