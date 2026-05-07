// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {Test} from "@forge-std-1.9.6/Test.sol";

// Contracts
import {ReEnablerGracePeriodHarness} from "src/test/libraries/ReEnablerGracePeriod/ReEnablerGracePeriodHarness.sol";

/// @notice Shared test base for the `ReEnablerGracePeriod` unit and fuzz tests. Defines
///         named actors, sentinel timestamps, and helpers for deploying the harness with
///         a chosen window length and exercising the lifecycle that drives
///         `lastTransitionAt`.
contract ReEnablerGracePeriodTestBase is Test {
    // ========== ACTORS ========== //

    address internal caller;

    // ========== SENTINEL TIMESTAMPS ========== //

    /// @dev A non-zero starting timestamp picked so that every grace window deadline
    ///      (which is `lastTransitionAt + _GRACE`) stays well above zero, and so that the
    ///      harness can warp far forward without crossing the `uint48` ceiling.
    uint48 internal constant START_TIMESTAMP = 1_000_000;

    /// @dev Maximum timestamp representable in `uint48`.
    uint48 internal constant UINT48_MAX = type(uint48).max;

    /// @dev Default grace window of one day used by the standard test setup.
    uint32 internal constant DEFAULT_GRACE = 1 days;

    // ========== STATE ========== //

    ReEnablerGracePeriodHarness internal harness;

    // ========== SETUP ========== //

    function setUp() public virtual {
        vm.warp(START_TIMESTAMP);

        caller = makeAddr("caller");

        harness = new ReEnablerGracePeriodHarness(DEFAULT_GRACE);
        vm.label(address(harness), "ReEnablerGracePeriodHarness");
    }

    // ========== HELPERS ========== //

    /// @dev Drives the underlying `EnablerV2` lifecycle by enabling at the current block,
    ///      refreshing `lastTransitionAt` to it.
    function _enable() internal {
        vm.prank(caller);
        harness.enable("");
    }

    /// @dev Drives the underlying `EnablerV2` lifecycle by disabling at the current
    ///      block, refreshing `lastTransitionAt` to it.
    function _disable() internal {
        vm.prank(caller);
        harness.disable("");
    }
}
