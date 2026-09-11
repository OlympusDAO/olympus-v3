// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Test} from "@forge-std-1.16.2/Test.sol";

// Contracts
import {ReEnablerGracePeriodImmutableHarness} from "src/test/bases/ReEnablerGracePeriodImmutable/ReEnablerGracePeriodImmutableHarness.sol";

/// @notice The shared test base for the `ReEnablerGracePeriodImmutable` unit tests.
///         Defines the named caller, the default grace window length used by every
///         deployment, and the harness instance reused across the cases.
contract ReEnablerGracePeriodImmutableTestBase is Test {
    // ========== ACTORS ========== //

    address internal caller;

    // ========== SENTINEL VALUES ========== //

    /// @dev The default grace window of one day used by the standard test setup.
    uint32 internal constant DEFAULT_GRACE = 1 days;

    // ========== STATE ========== //

    ReEnablerGracePeriodImmutableHarness internal harness;

    // ========== SETUP ========== //

    function setUp() public virtual {
        caller = makeAddr("caller");

        harness = new ReEnablerGracePeriodImmutableHarness(DEFAULT_GRACE);
        vm.label(address(harness), "ReEnablerGracePeriodImmutableHarness");
    }
}
