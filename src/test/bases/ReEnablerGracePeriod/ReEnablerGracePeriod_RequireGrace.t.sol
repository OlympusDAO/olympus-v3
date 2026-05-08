// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {ReEnablerGracePeriodTestBase} from "src/test/bases/ReEnablerGracePeriod/ReEnablerGracePeriodTestBase.sol";
import {ReEnablerGracePeriodHarness} from "src/test/bases/ReEnablerGracePeriod/ReEnablerGracePeriodHarness.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

/// @dev Tests for `ReEnablerGracePeriod._requireGrace`. The deadline is computed as
///      `lastTransitionAt + gracePeriod`. The check passes when `block.timestamp <= deadline`
///      and reverts when `block.timestamp >  deadline`.
contract ReEnablerGracePeriodTests_RequireGrace is ReEnablerGracePeriodTestBase {
    // ========== SUCCESS ========== //

    /// @notice With `lastTransitionAt == 0`, the deadline is `gracePeriod`. Tests that the
    ///         boundary is treated inclusively when the current block has not yet
    ///         reached the deadline.
    function test_requireGrace_passesIfWithinWindowBeforeAnyTransition() external {
        // setUp warps to START_TIMESTAMP, which is far above DEFAULT_GRACE,
        // so we explicitly warp back to a timestamp inside the deadline.
        vm.warp(uint256(DEFAULT_GRACE) - 1);
        harness.requireGrace();
    }

    function test_requireGrace_passesAtDeadlineBeforeAnyTransition() external {
        vm.warp(uint256(DEFAULT_GRACE));
        harness.requireGrace();
    }

    function test_requireGrace_passesIfWithinWindowAfterEnable() external {
        _enable();
        skip(DEFAULT_GRACE - 1);

        harness.requireGrace();
    }

    function test_requireGrace_passesAtDeadlineAfterEnable() external {
        _enable();
        skip(DEFAULT_GRACE);

        harness.requireGrace();
    }

    function test_requireGrace_passesIfWithinWindowAfterDisable() external {
        _enable();
        skip(uint256(DEFAULT_GRACE) * 2);
        // Window has expired since the enable, but the disable refreshes
        // `lastTransitionAt`, opening a fresh window.
        _disable();
        skip(DEFAULT_GRACE - 1);

        harness.requireGrace();
    }

    /// @notice Each transition recorded by `EnablerV2` updates `lastTransitionAt`, which
    ///         moves the grace deadline forward by the same offset.
    function test_requireGrace_restartsWindowOnEachTransition() external {
        _enable();
        skip(DEFAULT_GRACE / 2);
        _disable();
        skip(DEFAULT_GRACE / 2);
        _enable();

        // We are now `DEFAULT_GRACE` past the first enable, but only zero
        // seconds past the latest enable. Without the restart, the call
        // would revert. With the restart, it must pass even after warping
        // to the new deadline.
        skip(DEFAULT_GRACE);
        harness.requireGrace();
    }

    /// @notice The deadline reads `gracePeriod` from storage on every call, so a
    ///         successful `setGracePeriod` immediately extends the window for the
    ///         current `lastTransitionAt`.
    function test_requireGrace_usesIncreasedPeriodAfterSet() external {
        _enable();
        uint32 newPeriod = DEFAULT_GRACE * 2;
        vm.prank(caller);
        harness.setGracePeriod(newPeriod);

        // Warp past the original deadline but inside the new one.
        skip(uint256(DEFAULT_GRACE) + 1);
        harness.requireGrace();
    }

    // ========== SUCCESS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_requireGrace_passesAtOrBeforeDeadline(
        uint32 grace_,
        uint48 transitionAt_,
        uint64 elapsed_
    ) external {
        grace_ = uint32(bound(uint256(grace_), 1, type(uint32).max));
        // Keep `transitionAt + grace` strictly below `uint48` max so the
        // deadline does not saturate.
        transitionAt_ = uint48(
            bound(uint256(transitionAt_), 1, uint256(UINT48_MAX) - uint256(grace_))
        );
        elapsed_ = uint64(bound(uint256(elapsed_), 0, uint256(grace_)));

        ReEnablerGracePeriodHarness fresh = new ReEnablerGracePeriodHarness(grace_);
        vm.label(address(fresh), "ReEnablerGracePeriodHarness:fuzz");

        // Drive `lastTransitionAt` to `transitionAt_` via an enable.
        vm.warp(uint256(transitionAt_));
        vm.prank(caller);
        fresh.enable("");

        vm.warp(uint256(transitionAt_) + uint256(elapsed_));
        fresh.requireGrace();
    }

    // ========== REVERTS ========== //

    function test_requireGrace_revertsIfPastDeadlineBeforeAnyTransition() external {
        vm.warp(uint256(DEFAULT_GRACE) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(DEFAULT_GRACE))
        );
        harness.requireGrace();
    }

    function test_requireGrace_revertsIfPastDeadlineAfterEnable() external {
        _enable();
        uint48 enableAt = uint48(block.timestamp);
        skip(uint256(DEFAULT_GRACE) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGracePeriod.GracePeriod_Expired.selector,
                enableAt + DEFAULT_GRACE
            )
        );
        harness.requireGrace();
    }

    function test_requireGrace_revertsIfPastDeadlineAfterDisable() external {
        _enable();
        skip(uint256(DEFAULT_GRACE) * 2);
        _disable();
        uint48 disableAt = uint48(block.timestamp);
        skip(uint256(DEFAULT_GRACE) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGracePeriod.GracePeriod_Expired.selector,
                disableAt + DEFAULT_GRACE
            )
        );
        harness.requireGrace();
    }

    /// @notice A shorter `gracePeriod` brings the deadline forward; the revert reports
    ///         the new deadline rather than the one implied by the constructor value.
    function test_requireGrace_revertsWithNewDeadlineAfterDecrease() external {
        _enable();
        uint48 enableAt = uint48(block.timestamp);

        uint32 newPeriod = DEFAULT_GRACE / 2;
        vm.prank(caller);
        harness.setGracePeriod(newPeriod);

        // Warp past the new deadline but still inside the original window.
        uint48 newDeadline = enableAt + newPeriod;
        vm.warp(uint256(newDeadline) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, newDeadline)
        );
        harness.requireGrace();
    }

    function test_requireGrace_revertsReportingLatestDeadline() external {
        _enable();
        skip(DEFAULT_GRACE / 4);
        _disable();
        uint48 latestTransitionAt = uint48(block.timestamp);
        skip(uint256(DEFAULT_GRACE) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGracePeriod.GracePeriod_Expired.selector,
                latestTransitionAt + DEFAULT_GRACE
            )
        );
        harness.requireGrace();
    }

    // ========== REVERTS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_requireGrace_revertsWithExactDeadlineIfPastDeadline(
        uint32 grace_,
        uint48 transitionAt_,
        uint64 overshoot_
    ) external {
        grace_ = uint32(bound(uint256(grace_), 1, type(uint32).max));
        transitionAt_ = uint48(
            bound(uint256(transitionAt_), 1, uint256(UINT48_MAX) - uint256(grace_) - 1)
        );
        // Overshoot at least one second past the deadline, capped so the
        // resulting `block.timestamp` still fits in `uint48`.
        uint256 maxOvershoot = uint256(UINT48_MAX) - uint256(transitionAt_) - uint256(grace_);
        overshoot_ = uint64(bound(uint256(overshoot_), 1, maxOvershoot));

        ReEnablerGracePeriodHarness fresh = new ReEnablerGracePeriodHarness(grace_);
        vm.label(address(fresh), "ReEnablerGracePeriodHarness:fuzz");

        vm.warp(uint256(transitionAt_));
        vm.prank(caller);
        fresh.enable("");

        vm.warp(uint256(transitionAt_) + uint256(grace_) + uint256(overshoot_));

        vm.expectRevert(
            abi.encodeWithSelector(
                IGracePeriod.GracePeriod_Expired.selector,
                uint48(uint256(transitionAt_) + uint256(grace_))
            )
        );
        fresh.requireGrace();
    }
}
