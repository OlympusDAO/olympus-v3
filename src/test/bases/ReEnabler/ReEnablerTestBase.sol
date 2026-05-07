// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {Test} from "@forge-std-1.9.6/Test.sol";

// Contracts
import {ReEnablerHarness} from "src/test/bases/ReEnabler/ReEnablerHarness.sol";

/// @notice Shared test base for the `ReEnabler` unit and fuzz tests.
///         Defines named actors, sentinel timestamps, and helpers for the
///         most repeated actions: enabling and disabling the underlying
///         contract through the `EnablerV2` lifecycle.
contract ReEnablerTestBase is Test {
    // ========== EVENTS ========== //

    event Enabled();
    event Disabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at);

    // ========== ACTORS ========== //

    address internal caller;
    address internal otherCaller;

    // ========== SENTINEL TIMESTAMPS ========== //

    uint48 internal constant START_TIMESTAMP = 1_000_000;
    uint48 internal constant UINT48_MAX = type(uint48).max;

    // ========== STATE ========== //

    ReEnablerHarness internal harness;

    // ========== SETUP ========== //

    function setUp() public virtual {
        vm.warp(START_TIMESTAMP);

        caller = makeAddr("caller");
        otherCaller = makeAddr("otherCaller");

        harness = new ReEnablerHarness();
        vm.label(address(harness), "ReEnablerHarness");
    }

    // ========== HIGHER-LEVEL HELPERS ========== //

    function _enableAs(address caller_) internal {
        vm.prank(caller_);
        harness.enable("");
    }

    function _disableAs(address caller_) internal {
        vm.prank(caller_);
        harness.disable("");
    }

    /// @dev Drives the contract into the canonical "enabled at least once,
    ///      currently disabled" state so that `reEnable` is in its happy
    ///      path.
    modifier givenEnabledThenDisabled() {
        _enableAs(caller);
        _disableAs(caller);
        _;
    }
}
