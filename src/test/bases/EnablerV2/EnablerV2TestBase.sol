// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {Test} from "@forge-std-1.9.6/Test.sol";

// Contracts
import {EnablerV2Harness} from "src/test/bases/EnablerV2/EnablerV2Harness.sol";
import {StaticCallProbe} from "src/test/bases/EnablerV2/StaticCallProbe.sol";

/// @notice Shared test base for the `EnablerV2` unit and fuzz tests. Defines
///         named actors, sentinel timestamps, and helpers for the most
///         repeated actions: pranking the caller, enabling, disabling, and
///         asserting the `(isEnabled, lastTransitionAt)` pair.
contract EnablerV2TestBase is Test {
    // ========== EVENTS ========== //

    event Enabled();
    event Disabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at);

    // ========== ACTORS ========== //

    address internal caller;
    address internal otherCaller;

    // ========== SENTINEL TIMESTAMPS ========== //

    /// @dev A non-zero starting timestamp picked so that
    ///      `lastTransitionAt == 0` unambiguously marks the "never enabled"
    ///      state and so that the harness has room to warp far forward
    ///      without crossing the `uint48` ceiling.
    uint48 internal constant START_TIMESTAMP = 1_000_000;

    /// @dev Maximum timestamp representable in `uint48`, which is the storage
    ///      width of `lastTransitionAt`.
    uint48 internal constant UINT48_MAX = type(uint48).max;

    // ========== STATE ========== //

    EnablerV2Harness internal harness;
    StaticCallProbe internal probe;

    // ========== SETUP ========== //

    function setUp() public virtual {
        vm.warp(START_TIMESTAMP);

        caller = makeAddr("caller");
        otherCaller = makeAddr("otherCaller");

        probe = new StaticCallProbe();
        vm.label(address(probe), "StaticCallProbe");

        harness = new EnablerV2Harness();
        vm.label(address(harness), "EnablerV2Harness");

        harness.setProbe(probe);
    }

    // ========== HIGHER-LEVEL HELPERS ========== //

    /// @dev Pranks `caller_` and invokes `harness.enable(data_)`.
    function _enableAs(address caller_, bytes memory data_) internal {
        vm.prank(caller_);
        harness.enable(data_);
    }

    /// @dev Pranks `caller_` and invokes `harness.disable(data_)`.
    function _disableAs(address caller_, bytes memory data_) internal {
        vm.prank(caller_);
        harness.disable(data_);
    }

    // ========== STATE ASSERTIONS ========== //

    /// @dev Asserts the `(isEnabled, lastTransitionAt)` pair against expected
    ///      values, with a per-call label that surfaces in any mismatch.
    function _assertState(
        bool expectedIsEnabled_,
        uint48 expectedLastTransitionAt_,
        string memory label_
    ) internal view {
        assertEq(
            harness.isEnabled(),
            expectedIsEnabled_,
            string.concat(label_, ": isEnabled mismatch")
        );
        assertEq(
            harness.lastTransitionAt(),
            expectedLastTransitionAt_,
            string.concat(label_, ": lastTransitionAt mismatch")
        );
    }
}
