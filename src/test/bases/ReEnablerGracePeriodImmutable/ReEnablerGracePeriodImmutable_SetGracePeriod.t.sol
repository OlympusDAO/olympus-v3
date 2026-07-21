// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {ReEnablerGracePeriodImmutableTestBase} from "src/test/bases/ReEnablerGracePeriodImmutable/ReEnablerGracePeriodImmutableTestBase.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

/// @dev Tests for `ReEnablerGracePeriodImmutable.setGracePeriod`, which is the locking
///      override and must always revert with `GracePeriod_NotConfigurable` regardless
///      of the caller and of the supplied value.
contract ReEnablerGracePeriodImmutableTests_SetGracePeriod is
    ReEnablerGracePeriodImmutableTestBase
{
    // ========== REVERTS ========== //

    function test_setGracePeriod_revertsForArbitraryCaller() external {
        vm.expectRevert(IGracePeriod.GracePeriod_NotConfigurable.selector);
        vm.prank(caller);
        harness.setGracePeriod(DEFAULT_GRACE * 2);
    }

    function test_setGracePeriod_revertsForZeroPeriod() external {
        // The lock takes precedence over the zero check, so even a zero value reverts
        // with `GracePeriod_NotConfigurable` rather than `GracePeriod_ZeroPeriod`.
        vm.expectRevert(IGracePeriod.GracePeriod_NotConfigurable.selector);
        vm.prank(caller);
        harness.setGracePeriod(0);
    }

    function test_setGracePeriod_revertsForSameValue() external {
        // Supplying the current value still reverts: the lock is not value-dependent.
        vm.expectRevert(IGracePeriod.GracePeriod_NotConfigurable.selector);
        vm.prank(caller);
        harness.setGracePeriod(DEFAULT_GRACE);
    }

    // ========== REVERTS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_setGracePeriod_revertsForAnyCallerAndValue(
        address caller_,
        uint32 period_
    ) external {
        vm.expectRevert(IGracePeriod.GracePeriod_NotConfigurable.selector);
        vm.prank(caller_);
        harness.setGracePeriod(period_);
    }
}
