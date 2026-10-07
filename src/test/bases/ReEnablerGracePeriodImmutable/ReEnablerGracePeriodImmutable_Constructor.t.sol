// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ReEnablerGracePeriodImmutableTestBase} from "src/test/bases/ReEnablerGracePeriodImmutable/ReEnablerGracePeriodImmutableTestBase.sol";
import {ReEnablerGracePeriodImmutableHarness} from "src/test/bases/ReEnablerGracePeriodImmutable/ReEnablerGracePeriodImmutableHarness.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

/// @dev Tests for the constructor of `ReEnablerGracePeriodImmutable`. The constructor
///      forwards the supplied window to the parent constructor of `ReEnablerGracePeriod`,
///      which validates the value, stores it in the `gracePeriod` slot, and emits the
///      `GracePeriodSet` event.
contract ReEnablerGracePeriodImmutableTests_Constructor is ReEnablerGracePeriodImmutableTestBase {
    // ========== SUCCESS ========== //

    function test_constructor_storesGraceForMinNonZeroPeriod() external {
        ReEnablerGracePeriodImmutableHarness fresh = new ReEnablerGracePeriodImmutableHarness(1);
        vm.label(address(fresh), "ReEnablerGracePeriodImmutableHarness:gracePeriod=1");

        assertEq(fresh.gracePeriod(), 1, "gracePeriod should be stored as one second");
    }

    function test_constructor_storesGraceForMaxPeriod() external {
        ReEnablerGracePeriodImmutableHarness fresh = new ReEnablerGracePeriodImmutableHarness(
            type(uint32).max
        );
        vm.label(address(fresh), "ReEnablerGracePeriodImmutableHarness:gracePeriod=uint32.max");

        assertEq(
            fresh.gracePeriod(),
            type(uint32).max,
            "gracePeriod should be stored at the uint32 maximum"
        );
    }

    function test_constructor_storesGraceFromDefaultSetup() external view {
        assertEq(harness.gracePeriod(), DEFAULT_GRACE, "default gracePeriod should be stored");
    }

    function test_constructor_emitsGracePeriodSet() external {
        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(DEFAULT_GRACE);
        new ReEnablerGracePeriodImmutableHarness(DEFAULT_GRACE);
    }

    // ========== REVERTS ========== //

    function test_constructor_revertsIfZeroPeriod() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        new ReEnablerGracePeriodImmutableHarness(0);
    }
}
