// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {EnablerV2TestBase} from "src/test/bases/EnablerV2/EnablerV2TestBase.sol";
import {EnablerV2Harness} from "src/test/bases/EnablerV2/EnablerV2Harness.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {StaticCallProbe} from "src/test/bases/EnablerV2/StaticCallProbe.sol";

/// @dev Tests for `EnablerV2.disable`.
contract EnablerV2Tests_Disable is EnablerV2TestBase {
    bytes internal constant SAMPLE_DATA = hex"cafef00d";

    modifier givenEnabled() {
        _enableAs(caller, hex"01");
        _;
    }

    // ========== SUCCESS ========== //

    function test_disable_setsState() external givenEnabled {
        skip(500);
        _disableAs(caller, SAMPLE_DATA);

        _assertState(false, uint48(vm.getBlockTimestamp()), "post-disable");
    }

    function test_disable_invokesAuthorizeBeforeBeforeHook() external givenEnabled {
        vm.expectCall(address(probe), abi.encodeCall(StaticCallProbe.note, ()), 1);
        _disableAs(caller, SAMPLE_DATA);

        assertEq(harness.beforeDisableCount(), 1, "before invoked once");
        assertEq(harness.lastBeforeDisableData(), SAMPLE_DATA, "data forwarded to before hook");
    }

    function test_disable_emitsLegacyAndTransitionEvents() external givenEnabled {
        vm.expectEmit(true, true, true, true, address(harness));
        emit Disabled();
        vm.expectEmit(true, true, true, true, address(harness));
        emit Transition(caller, false, SAMPLE_DATA, uint48(vm.getBlockTimestamp()));

        vm.prank(caller);
        harness.disable(SAMPLE_DATA);
    }

    function test_disable_succeedsWithEmptyData() external givenEnabled {
        _disableAs(caller, "");

        _assertState(false, uint48(vm.getBlockTimestamp()), "post-disable");
        assertEq(harness.lastBeforeDisableData(), "", "empty data forwarded");
    }

    function test_disable_succeedsAtUint48Max() external givenEnabled {
        vm.warp(UINT48_MAX);

        _disableAs(caller, SAMPLE_DATA);

        _assertState(false, UINT48_MAX, "boundary timestamp");
    }

    function test_disable_sharesTimestampWithEnableInSameBlock() external {
        _enableAs(caller, hex"01");
        uint48 atEnable = harness.lastTransitionAt();
        _disableAs(caller, SAMPLE_DATA);

        _assertState(false, atEnable, "same-block disable shares timestamp");
    }

    // ========== SUCCESS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_disable_forwardsArbitraryDataToBeforeHook(bytes calldata data_) external {
        _enableAs(caller, "");

        vm.prank(caller);
        harness.disable(data_);

        assertEq(harness.lastBeforeDisableData(), data_, "before-disable data fidelity");
        assertFalse(harness.isEnabled(), "post-state isEnabled");
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_disable_emitsTransitionWithAnyCaller(address caller_) external {
        _enableAs(caller, "");

        vm.expectEmit(true, true, true, true, address(harness));
        emit Disabled();
        vm.expectEmit(true, true, true, true, address(harness));
        emit Transition(caller_, false, "", uint48(vm.getBlockTimestamp()));

        vm.prank(caller_);
        harness.disable("");
    }

    // ========== REVERTS ========== //

    function test_disable_revertsIfCurrentlyDisabled() external {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller);
        harness.disable(SAMPLE_DATA);
    }

    function test_disable_revertsIfAuthorizeReverts() external givenEnabled {
        uint48 atEnable = harness.lastTransitionAt();

        harness.setAuthorizeDisableShouldRevert(true);

        vm.expectRevert(EnablerV2Harness.MockUnauthorizedDisable.selector);
        vm.prank(caller);
        harness.disable(SAMPLE_DATA);

        _assertState(true, atEnable, "post-revert");
    }

    function test_disable_revertsIfBeforeReverts() external givenEnabled {
        uint48 atEnable = harness.lastTransitionAt();

        harness.setBeforeDisableShouldRevert(true);

        vm.expectRevert(EnablerV2Harness.MockBeforeDisableReverted.selector);
        vm.prank(caller);
        harness.disable(SAMPLE_DATA);

        _assertState(true, atEnable, "post-revert");
    }

    /// @notice With both hooks toggled to revert, the surviving selector
    ///         tells us which hook ran first. The authorize hook must run
    ///         before the before hook, so the selector must be the authorize
    ///         one.
    function test_disable_runsAuthorizeBeforeBeforeHook() external givenEnabled {
        harness.setAuthorizeDisableShouldRevert(true);
        harness.setBeforeDisableShouldRevert(true);

        vm.expectRevert(EnablerV2Harness.MockUnauthorizedDisable.selector);
        vm.prank(caller);
        harness.disable(SAMPLE_DATA);
    }
}
