// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReEnablerGracePeriodTestBase} from "src/test/bases/ReEnablerGracePeriod/ReEnablerGracePeriodTestBase.sol";
import {ReEnablerGracePeriodHarness} from "src/test/bases/ReEnablerGracePeriod/ReEnablerGracePeriodHarness.sol";
import {ReEnablerGracePeriodRejectingAuthHarness} from "src/test/bases/ReEnablerGracePeriod/ReEnablerGracePeriodRejectingAuthHarness.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

/// @dev Tests for `ReEnablerGracePeriod.setGracePeriod`, which is gated by `givenEnabled`
///      and routes through the `_authorizeSetGracePeriod` hook and the shared
///      `_setGracePeriod` helper. A successful call rejects a zero window, overwrites the
///      `gracePeriod` slot, and emits the `GracePeriodSet` event.
contract ReEnablerGracePeriodTests_SetGracePeriod is ReEnablerGracePeriodTestBase {
    /// @dev The setter is gated by `givenEnabled`, so the harness is enabled before each
    ///      test exercises it.
    function setUp() public override {
        super.setUp();
        _enable();
    }

    // ========== SUCCESS ========== //

    function test_setGracePeriod_storesValueAndUpdatesView() external {
        uint32 newPeriod = DEFAULT_GRACE * 2;

        vm.prank(caller);
        harness.setGracePeriod(newPeriod);

        assertEq(harness.gracePeriod(), newPeriod, "gracePeriod should reflect the new value");
    }

    function test_setGracePeriod_emitsGracePeriodSet() external {
        uint32 newPeriod = DEFAULT_GRACE + 1;

        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(newPeriod);
        vm.prank(caller);
        harness.setGracePeriod(newPeriod);
    }

    function test_setGracePeriod_overwritesPreviousValue() external {
        // First update moves the window away from the constructor default.
        vm.prank(caller);
        harness.setGracePeriod(DEFAULT_GRACE * 2);
        assertEq(
            harness.gracePeriod(),
            DEFAULT_GRACE * 2,
            "first update should overwrite the constructor value"
        );

        // Second update overwrites the first.
        vm.prank(caller);
        harness.setGracePeriod(DEFAULT_GRACE * 3);
        assertEq(
            harness.gracePeriod(),
            DEFAULT_GRACE * 3,
            "second update should overwrite the first"
        );
    }

    function test_setGracePeriod_acceptsMinNonZeroPeriod() external {
        vm.prank(caller);
        harness.setGracePeriod(1);

        assertEq(harness.gracePeriod(), 1, "gracePeriod should accept one second");
    }

    function test_setGracePeriod_acceptsMaxPeriod() external {
        vm.prank(caller);
        harness.setGracePeriod(type(uint32).max);

        assertEq(
            harness.gracePeriod(),
            type(uint32).max,
            "gracePeriod should accept the uint32 maximum"
        );
    }

    /// @notice Calling the setter twice with the same value leaves the contract in the
    ///         same observable state as a single call: the stored value is unchanged
    ///         and the helper does not short-circuit on equality.
    function test_setGracePeriod_idempotentForRepeatedSameValue() external {
        uint32 newPeriod = DEFAULT_GRACE * 2;

        vm.prank(caller);
        harness.setGracePeriod(newPeriod);

        // The second call with the same value also emits the event and leaves the
        // stored value untouched.
        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(newPeriod);
        vm.prank(caller);
        harness.setGracePeriod(newPeriod);

        assertEq(
            harness.gracePeriod(),
            newPeriod,
            "gracePeriod should remain at the same value after a repeated update"
        );
    }

    // ========== SUCCESS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_setGracePeriod_storesAnyNonZeroPeriod(uint32 period_) external {
        period_ = uint32(bound(uint256(period_), 1, type(uint32).max));

        vm.prank(caller);
        harness.setGracePeriod(period_);

        assertEq(harness.gracePeriod(), period_, "stored gracePeriod should match the input");
    }

    // ========== REVERTS ========== //

    function test_setGracePeriod_revertsIfZeroPeriod() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(caller);
        harness.setGracePeriod(0);
    }

    function test_setGracePeriod_revertsIfAuthorisationRejected() external {
        ReEnablerGracePeriodRejectingAuthHarness rejecting = new ReEnablerGracePeriodRejectingAuthHarness(
                DEFAULT_GRACE
            );
        vm.label(address(rejecting), "ReEnablerGracePeriodRejectingAuthHarness");
        vm.prank(caller);
        rejecting.enable("");

        vm.expectRevert(
            ReEnablerGracePeriodRejectingAuthHarness.AuthorizeSetGracePeriod_Rejected.selector
        );
        vm.prank(caller);
        rejecting.setGracePeriod(DEFAULT_GRACE * 2);
    }

    function test_setGracePeriod_revertsBeforeStateMutationOnAuthorisationRevert() external {
        ReEnablerGracePeriodRejectingAuthHarness rejecting = new ReEnablerGracePeriodRejectingAuthHarness(
                DEFAULT_GRACE
            );
        vm.label(address(rejecting), "ReEnablerGracePeriodRejectingAuthHarness");
        vm.prank(caller);
        rejecting.enable("");

        // The authorisation hook reverts before the helper runs, so even a zero value
        // is reported through the auth error rather than `GracePeriod_ZeroPeriod`. This
        // confirms that `_authorizeSetGracePeriod` is invoked first.
        vm.expectRevert(
            ReEnablerGracePeriodRejectingAuthHarness.AuthorizeSetGracePeriod_Rejected.selector
        );
        vm.prank(caller);
        rejecting.setGracePeriod(0);
    }

    function test_setGracePeriod_revertsWhenDisabled() external {
        _disable();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller);
        harness.setGracePeriod(DEFAULT_GRACE * 2);
    }
}
