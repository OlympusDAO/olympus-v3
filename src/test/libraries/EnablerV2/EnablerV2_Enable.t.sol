// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {EnablerV2TestBase} from "src/test/libraries/EnablerV2/EnablerV2TestBase.sol";
import {EnablerV2Harness} from "src/test/libraries/EnablerV2/EnablerV2Harness.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @dev Tests for `EnablerV2.enable`.
contract EnablerV2Tests_Enable is EnablerV2TestBase {
    bytes internal constant SAMPLE_DATA = hex"deadbeef";

    // ========== SUCCESS ========== //

    function test_enable_setsState() external {
        vm.warp(uint256(START_TIMESTAMP) + 1234);
        _enableAs(caller, SAMPLE_DATA);

        _assertState(true, uint48(START_TIMESTAMP) + 1234, "post-enable");
    }

    function test_enable_invokesAuthorizeBeforeBeforeHook() external {
        _enableAs(caller, SAMPLE_DATA);

        assertEq(harness.authorizeEnableCount(), 1, "authorize invoked once");
        assertEq(harness.beforeEnableCount(), 1, "before invoked once");
        assertEq(harness.lastBeforeEnableData(), SAMPLE_DATA, "data forwarded to before hook");
    }

    function test_enable_emitsLegacyAndTransitionEvents() external {
        vm.expectEmit(true, true, true, true, address(harness));
        emit Enabled();
        vm.expectEmit(true, true, true, true, address(harness));
        emit Transition(caller, true, SAMPLE_DATA, uint48(block.timestamp));

        vm.prank(caller);
        harness.enable(SAMPLE_DATA);
    }

    function test_enable_succeedsWithEmptyData() external {
        _enableAs(caller, "");

        _assertState(true, uint48(block.timestamp), "post-enable");
        assertEq(harness.lastBeforeEnableData(), "", "empty data forwarded");
    }

    function test_enable_succeedsAtUint48Max() external {
        vm.warp(UINT48_MAX);

        _enableAs(caller, SAMPLE_DATA);

        _assertState(true, UINT48_MAX, "boundary timestamp");
    }

    function test_enable_advancesLastTransitionAtAfterDisable() external {
        _enableAs(caller, SAMPLE_DATA);
        skip(100);
        _disableAs(caller, SAMPLE_DATA);
        uint48 atDisable = uint48(block.timestamp);

        skip(200);
        _enableAs(caller, SAMPLE_DATA);

        _assertState(true, uint48(block.timestamp), "post re-enable through enable");
        assertGt(harness.lastTransitionAt(), atDisable, "transition timestamp advanced");
    }

    function test_enable_emitsTransitionWithCallerAddress() external {
        vm.expectEmit(true, true, true, true, address(harness));
        emit Enabled();
        vm.expectEmit(true, true, true, true, address(harness));
        emit Transition(otherCaller, true, SAMPLE_DATA, uint48(block.timestamp));

        vm.prank(otherCaller);
        harness.enable(SAMPLE_DATA);
    }

    // ========== SUCCESS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_enable_forwardsArbitraryDataToBeforeHook(bytes calldata data_) external {
        vm.prank(caller);
        harness.enable(data_);

        assertEq(harness.lastBeforeEnableData(), data_, "before-enable data fidelity");
        assertTrue(harness.isEnabled(), "post-state isEnabled");
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_enable_emitsTransitionWithAnyCaller(address caller_) external {
        vm.expectEmit(true, true, true, true, address(harness));
        emit Enabled();
        vm.expectEmit(true, true, true, true, address(harness));
        emit Transition(caller_, true, "", uint48(block.timestamp));

        vm.prank(caller_);
        harness.enable("");
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_enable_recordsExactTimestamp(uint48 ts_) external {
        ts_ = uint48(bound(uint256(ts_), uint256(START_TIMESTAMP), uint256(UINT48_MAX)));
        vm.warp(uint256(ts_));

        _enableAs(caller, "");

        assertEq(harness.lastTransitionAt(), ts_, "lastTransitionAt matches block.timestamp");
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_scenario_lastTransitionAtMatchesLatestStep(
        uint48 enableTs_,
        uint48 disableTs_,
        uint48 reEnableTs_
    ) external {
        // Ordered, monotonically non-decreasing timestamps within range.
        enableTs_ = uint48(
            bound(uint256(enableTs_), uint256(START_TIMESTAMP), uint256(UINT48_MAX) - 2)
        );
        disableTs_ = uint48(
            bound(uint256(disableTs_), uint256(enableTs_) + 1, uint256(UINT48_MAX) - 1)
        );
        reEnableTs_ = uint48(
            bound(uint256(reEnableTs_), uint256(disableTs_) + 1, uint256(UINT48_MAX))
        );

        vm.warp(uint256(enableTs_));
        _enableAs(caller, "");
        assertEq(harness.lastTransitionAt(), enableTs_, "after enable");

        vm.warp(uint256(disableTs_));
        _disableAs(caller, "");
        assertEq(harness.lastTransitionAt(), disableTs_, "after disable");

        vm.warp(uint256(reEnableTs_));
        _enableAs(caller, "");
        assertEq(harness.lastTransitionAt(), reEnableTs_, "after re-enable through enable");
    }

    // ========== REVERTS ========== //

    function test_enable_revertsIfCurrentlyEnabled() external {
        _enableAs(caller, SAMPLE_DATA);

        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller);
        harness.enable(SAMPLE_DATA);
    }

    function test_enable_revertsIfAuthorizeReverts() external {
        harness.setAuthorizeEnableShouldRevert(true);

        vm.expectRevert(EnablerV2Harness.MockUnauthorizedEnable.selector);
        vm.prank(caller);
        harness.enable(SAMPLE_DATA);

        _assertState(false, 0, "post-revert");
    }

    function test_enable_revertsIfBeforeReverts() external {
        harness.setBeforeEnableShouldRevert(true);

        vm.expectRevert(EnablerV2Harness.MockBeforeEnableReverted.selector);
        vm.prank(caller);
        harness.enable(SAMPLE_DATA);

        _assertState(false, 0, "post-revert");
    }

    /// @notice With both hooks toggled to revert, the surviving selector
    ///         tells us which hook ran first. The authorize hook must run
    ///         before the before hook, so the selector must be the authorize
    ///         one.
    function test_enable_runsAuthorizeBeforeBeforeHook() external {
        harness.setAuthorizeEnableShouldRevert(true);
        harness.setBeforeEnableShouldRevert(true);

        vm.expectRevert(EnablerV2Harness.MockUnauthorizedEnable.selector);
        vm.prank(caller);
        harness.enable(SAMPLE_DATA);
    }
}
