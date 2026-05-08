// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {ReEnablerGracePeriodTestBase} from "src/test/bases/ReEnablerGracePeriod/ReEnablerGracePeriodTestBase.sol";
import {ReEnablerGracePeriodHarness} from "src/test/bases/ReEnablerGracePeriod/ReEnablerGracePeriodHarness.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

/// @dev Tests for the constructor of `ReEnablerGracePeriod`, which gates the configured
///      window length against zero and otherwise stores it in the `gracePeriod` slot,
///      exposed externally via the public getter. The constructor routes the value through
///      `_setGracePeriod`, so a successful deployment also emits a `GracePeriodSet`
///      event.
contract ReEnablerGracePeriodTests_Constructor is ReEnablerGracePeriodTestBase {
    // ========== SUCCESS ========== //

    function test_constructor_storesGraceForMinNonZeroPeriod() external {
        ReEnablerGracePeriodHarness fresh = new ReEnablerGracePeriodHarness(1);
        vm.label(address(fresh), "ReEnablerGracePeriodHarness:gracePeriod=1");

        assertEq(fresh.gracePeriod(), 1, "gracePeriod stored as one second");
    }

    function test_constructor_emitsGracePeriodSet() external {
        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(DEFAULT_GRACE);
        new ReEnablerGracePeriodHarness(DEFAULT_GRACE);
    }

    function test_constructor_storesGraceForMaxPeriod() external {
        ReEnablerGracePeriodHarness fresh = new ReEnablerGracePeriodHarness(type(uint32).max);
        vm.label(address(fresh), "ReEnablerGracePeriodHarness:gracePeriod=uint32.max");

        assertEq(fresh.gracePeriod(), type(uint32).max, "gracePeriod stored at uint32 max");
    }

    function test_constructor_storesGraceFromDefaultSetup() external view {
        assertEq(harness.gracePeriod(), DEFAULT_GRACE, "default gracePeriod stored");
    }

    // ========== SUCCESS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_constructor_storesGraceForAnyNonZeroPeriod(uint32 p_) external {
        p_ = uint32(bound(uint256(p_), 1, type(uint32).max));

        ReEnablerGracePeriodHarness fresh = new ReEnablerGracePeriodHarness(p_);
        vm.label(address(fresh), "ReEnablerGracePeriodHarness:fuzz");

        assertEq(fresh.gracePeriod(), p_, "stored gracePeriod matches input");
    }

    // ========== REVERTS ========== //

    function test_constructor_revertsIfZeroPeriod() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        new ReEnablerGracePeriodHarness(0);
    }
}
