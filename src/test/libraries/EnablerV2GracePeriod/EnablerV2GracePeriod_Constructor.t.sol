// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {EnablerV2GracePeriodTestBase} from "src/test/libraries/EnablerV2GracePeriod/EnablerV2GracePeriodTestBase.sol";
import {EnablerV2GracePeriodHarness} from "src/test/libraries/EnablerV2GracePeriod/EnablerV2GracePeriodHarness.sol";

// Interfaces
import {IEnablerV2GracePeriod} from "src/interfaces/IEnablerV2GracePeriod.sol";

/// @dev Tests for the constructor of `EnablerV2GracePeriod`, which gates the
///      configured window length against zero and otherwise stores it as the
///      immutable `GRACE`.
contract EnablerV2GracePeriodTests_Constructor is EnablerV2GracePeriodTestBase {
    // ========== SUCCESS ========== //

    function test_constructor_storesGraceForMinNonZeroPeriod() external {
        EnablerV2GracePeriodHarness fresh = new EnablerV2GracePeriodHarness(1);
        vm.label(address(fresh), "EnablerV2GracePeriodHarness:GRACE=1");

        assertEq(fresh.GRACE(), 1, "GRACE stored as one second");
    }

    function test_constructor_storesGraceForMaxPeriod() external {
        EnablerV2GracePeriodHarness fresh = new EnablerV2GracePeriodHarness(type(uint32).max);
        vm.label(address(fresh), "EnablerV2GracePeriodHarness:GRACE=uint32.max");

        assertEq(fresh.GRACE(), type(uint32).max, "GRACE stored at uint32 max");
    }

    function test_constructor_storesGraceFromDefaultSetup() external view {
        assertEq(harness.GRACE(), DEFAULT_GRACE, "default GRACE stored");
    }

    // ========== SUCCESS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_constructor_storesGraceForAnyNonZeroPeriod(uint32 p_) external {
        p_ = uint32(bound(uint256(p_), 1, type(uint32).max));

        EnablerV2GracePeriodHarness fresh = new EnablerV2GracePeriodHarness(p_);
        vm.label(address(fresh), "EnablerV2GracePeriodHarness:fuzz");

        assertEq(fresh.GRACE(), p_, "stored GRACE matches input");
    }

    // ========== REVERTS ========== //

    function test_constructor_revertsIfZeroPeriod() external {
        vm.expectRevert(IEnablerV2GracePeriod.EnablerV2GracePeriod_ZeroPeriod.selector);
        new EnablerV2GracePeriodHarness(0);
    }
}
