// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Test} from "@forge-std-1.9.6/Test.sol";

// Contracts
import {EnablerV2GracePeriodHarness} from "src/test/libraries/EnablerV2GracePeriod/EnablerV2GracePeriodHarness.sol";

/// @notice Shared test base for the `EnablerV2GracePeriod` unit and fuzz
///         tests. Defines named actors, sentinel timestamps, and helpers for
///         deploying the harness with a chosen window length and exercising
///         the lifecycle that drives `lastTransitionAt`.
contract EnablerV2GracePeriodTestBase is Test {
    // ========== ACTORS ========== //

    address internal caller;

    // ========== SENTINEL TIMESTAMPS ========== //

    /// @dev A non-zero starting timestamp picked so that every grace
    ///      window deadline (which is `lastTransitionAt + GRACE`) stays well
    ///      above zero, and so that the harness can warp far forward without
    ///      crossing the `uint48` ceiling.
    uint48 internal constant START_TIMESTAMP = 1_000_000;

    /// @dev Maximum timestamp representable in `uint48`.
    uint48 internal constant UINT48_MAX = type(uint48).max;

    /// @dev Default grace window of one day used by the standard test setup.
    uint32 internal constant DEFAULT_GRACE = 1 days;

    // ========== STATE ========== //

    EnablerV2GracePeriodHarness internal harness;

    // ========== SETUP ========== //

    function setUp() public virtual {
        vm.warp(START_TIMESTAMP);

        caller = makeAddr("caller");

        harness = new EnablerV2GracePeriodHarness(DEFAULT_GRACE);
        vm.label(address(harness), "EnablerV2GracePeriodHarness");
    }

    // ========== HELPERS ========== //

    /// @dev Drives the underlying `EnablerV2` lifecycle by enabling at the
    ///      current block, refreshing `lastTransitionAt` to it.
    function _enable() internal {
        vm.prank(caller);
        harness.enable("");
    }

    /// @dev Drives the underlying `EnablerV2` lifecycle by disabling at the
    ///      current block, refreshing `lastTransitionAt` to it.
    function _disable() internal {
        vm.prank(caller);
        harness.disable("");
    }
}
