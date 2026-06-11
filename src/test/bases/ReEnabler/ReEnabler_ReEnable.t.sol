// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {ReEnablerTestBase} from "src/test/bases/ReEnabler/ReEnablerTestBase.sol";
import {ReEnablerHarness, ReEnablerDefaultBeforeHarness} from "src/test/bases/ReEnabler/ReEnablerHarness.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";

// Contracts
import {StaticCallProbe} from "src/test/bases/EnablerV2/StaticCallProbe.sol";

/// @dev Tests for `ReEnabler.reEnable`.
contract ReEnablerTests_ReEnable is ReEnablerTestBase {
    // ========== SUCCESS ========== //

    function test_reEnable_setsState() external givenEnabledThenDisabled {
        skip(1234);
        vm.prank(caller);
        harness.reEnable();

        assertTrue(harness.isEnabled(), "isEnabled true");
        assertEq(
            harness.lastTransitionAt(),
            uint48(vm.getBlockTimestamp()),
            "lastTransitionAt refreshed"
        );
    }

    function test_reEnable_invokesAuthorizeBeforeBeforeHook() external givenEnabledThenDisabled {
        vm.expectCall(address(probe), abi.encodeCall(StaticCallProbe.note, ()), 1);
        vm.prank(caller);
        harness.reEnable();

        assertEq(harness.beforeReEnableCount(), 1, "before invoked once");
    }

    function test_reEnable_emitsLegacyAndTransitionEventsWithEmptyData()
        external
        givenEnabledThenDisabled
    {
        vm.expectEmit(true, true, true, true, address(harness));
        emit Enabled();
        vm.expectEmit(true, true, true, true, address(harness));
        emit Transition(caller, true, "", uint48(vm.getBlockTimestamp()));

        vm.prank(caller);
        harness.reEnable();
    }

    function test_reEnable_succeedsAtUint48Max() external givenEnabledThenDisabled {
        vm.warp(UINT48_MAX);
        vm.prank(caller);
        harness.reEnable();

        assertEq(harness.lastTransitionAt(), UINT48_MAX, "boundary timestamp");
    }

    /// @notice Exercises the default no-op body of `_beforeReEnable` via a
    ///         companion harness that does not override the hook.
    function test_reEnable_invokesDefaultBeforeHookAsNoOp() external {
        ReEnablerDefaultBeforeHarness defaultHarness = new ReEnablerDefaultBeforeHarness();
        vm.label(address(defaultHarness), "ReEnablerDefaultBeforeHarness");

        vm.prank(caller);
        defaultHarness.enable("");
        vm.prank(caller);
        defaultHarness.disable("");
        skip(50);

        vm.prank(caller);
        defaultHarness.reEnable();

        assertTrue(defaultHarness.isEnabled(), "isEnabled true");
        assertEq(
            defaultHarness.lastTransitionAt(),
            uint48(vm.getBlockTimestamp()),
            "lastTransitionAt refreshed"
        );
    }

    function test_reEnable_succeedsAcrossMultipleCycles() external {
        _enableAs(caller);
        _disableAs(caller);

        skip(100);
        vm.prank(caller);
        harness.reEnable();
        assertTrue(harness.isEnabled(), "first re-enable");

        skip(100);
        _disableAs(caller);

        skip(100);
        vm.prank(caller);
        harness.reEnable();
        assertTrue(harness.isEnabled(), "second re-enable");
        assertEq(harness.lastTransitionAt(), uint48(vm.getBlockTimestamp()), "latest timestamp");
    }

    // ========== SUCCESS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_reEnable_emitsTransitionWithAnyCallerAndEmptyData(
        address caller_
    ) external givenEnabledThenDisabled {
        vm.expectEmit(true, true, true, true, address(harness));
        emit Enabled();
        vm.expectEmit(true, true, true, true, address(harness));
        emit Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));

        vm.prank(caller_);
        harness.reEnable();
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_reEnable_recordsExactTimestamp(uint48 ts_) external givenEnabledThenDisabled {
        ts_ = uint48(bound(uint256(ts_), uint256(harness.lastTransitionAt()), uint256(UINT48_MAX)));
        vm.warp(uint256(ts_));

        vm.prank(caller);
        harness.reEnable();

        assertTrue(harness.isEnabled(), "isEnabled true");
        assertEq(harness.lastTransitionAt(), ts_, "lastTransitionAt matches block.timestamp");
    }

    // ========== REVERTS ========== //

    function test_reEnable_revertsIfNeverEnabled() external {
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller);
        harness.reEnable();
    }

    function test_reEnable_revertsIfCurrentlyEnabled() external {
        _enableAs(caller);

        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller);
        harness.reEnable();
    }

    function test_reEnable_revertsIfAuthorizeReverts() external givenEnabledThenDisabled {
        uint48 atDisable = harness.lastTransitionAt();

        harness.setAuthorizeReEnableShouldRevert(true);

        vm.expectRevert(ReEnablerHarness.MockUnauthorizedReEnable.selector);
        vm.prank(caller);
        harness.reEnable();

        assertFalse(harness.isEnabled(), "still disabled after revert");
        assertEq(harness.lastTransitionAt(), atDisable, "lastTransitionAt unchanged");
    }

    function test_reEnable_revertsIfBeforeReverts() external givenEnabledThenDisabled {
        uint48 atDisable = harness.lastTransitionAt();

        harness.setBeforeReEnableShouldRevert(true);

        vm.expectRevert(ReEnablerHarness.MockBeforeReEnableReverted.selector);
        vm.prank(caller);
        harness.reEnable();

        assertFalse(harness.isEnabled(), "still disabled after revert");
        assertEq(harness.lastTransitionAt(), atDisable, "lastTransitionAt unchanged");
    }

    /// @notice With both hooks toggled to revert, the surviving selector
    ///         tells us which hook ran first. The authorize hook must run
    ///         before the before hook, so the selector must be the authorize
    ///         one.
    function test_reEnable_runsAuthorizeBeforeBeforeHook() external givenEnabledThenDisabled {
        harness.setAuthorizeReEnableShouldRevert(true);
        harness.setBeforeReEnableShouldRevert(true);

        vm.expectRevert(ReEnablerHarness.MockUnauthorizedReEnable.selector);
        vm.prank(caller);
        harness.reEnable();
    }
}
