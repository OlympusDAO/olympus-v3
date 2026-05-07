// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {OffsettingRateLimiterTestBase} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterTestBase.sol";
import {stdError} from "@forge-std-1.9.6/StdError.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

/// @dev Tests for the public view functions `sendable` / `receivable`, the
///      internal helper `_currentState` (exposed via the harness),
///      the storage-mapping getters `outRateLimits` / `inRateLimits` and that
///      they return the *raw* stored value rather than the decayed view-time value.
contract OffsettingRateLimiterTests_View is OffsettingRateLimiterTestBase {
    // ========== sendable ========== //

    function test_sendable_unconfigured_returnsZeros() external view {
        _assertSendable(EID_A, 0, 0, "unconfigured");
    }

    function test_sendable_elapsedGreaterEqualWindow_returnsZeroAndFullLimit() external {
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.outflow(EID_A, DEFAULT_LIMIT);

        // Warp exactly to the window boundary.
        skip(DEFAULT_WINDOW);
        _assertSendable(EID_A, 0, DEFAULT_LIMIT, "elapsed == window");

        // Warp past the window boundary.
        skip(1);
        _assertSendable(EID_A, 0, DEFAULT_LIMIT, "elapsed > window");
    }

    function test_sendable_zeroWindow_returnsZeroAndFullLimit() external {
        // Set a non-zero window first to drive a non-zero stored inFlight.
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.outflow(EID_A, DEFAULT_LIMIT / 2);

        // Then reduce the window to zero. The setter checkpoints first, so the
        // stored inFlight is preserved across the change.
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, 0)));
        (uint256 stored, , , ) = harness.outRateLimits(EID_A);
        assertEq(stored, DEFAULT_LIMIT / 2, "stored inFlight preserved across window change");

        // Even with non-zero stored inFlight, sendable returns (0, limit).
        _assertSendable(EID_A, 0, DEFAULT_LIMIT, "zero window");
    }

    function test_sendable_elapsedZero_returnsRawInFlightAndDeducted() external {
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.outflow(EID_A, DEFAULT_LIMIT / 4);

        _assertSendable(
            EID_A,
            DEFAULT_LIMIT / 4,
            DEFAULT_LIMIT - DEFAULT_LIMIT / 4,
            "elapsed == 0"
        );
    }

    function test_sendable_partialDecay_returnsExpected() external {
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.outflow(EID_A, DEFAULT_LIMIT);

        // Pick an arbitrary fraction of the window where the integer arithmetic
        // does not lose precision.
        uint256 elapsed = (uint256(DEFAULT_WINDOW) * 7) / 11;
        skip(elapsed);

        uint256 expectedDecayedInFlight = _expectedDecayedInFlight(
            DEFAULT_LIMIT,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            elapsed
        );
        _assertSendable(
            EID_A,
            expectedDecayedInFlight,
            DEFAULT_LIMIT - expectedDecayedInFlight,
            "partial decay"
        );
    }

    function test_sendable_storedAboveLimit_returnsZeroAvailable() external {
        // Drive stored inFlight to the full limit, then reduce the limit.
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.outflow(EID_A, DEFAULT_LIMIT);
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT / 2, DEFAULT_WINDOW)));

        // No time has elapsed since the checkpoint, so the decayed value equals
        // the stored value, which exceeds the new limit.
        _assertSendable(EID_A, DEFAULT_LIMIT, 0, "stored > limit, available clamped at 0");
    }

    function test_sendable_doesNotMutateState() external {
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.outflow(EID_A, DEFAULT_LIMIT / 3);

        skip(DEFAULT_WINDOW / 4);

        (uint256 inBefore, uint256 limBefore, uint32 winBefore, uint48 luBefore) = harness
            .outRateLimits(EID_A);

        harness.sendable(EID_A);

        (uint256 inAfter, uint256 limAfter, uint32 winAfter, uint48 luAfter) = harness
            .outRateLimits(EID_A);

        assertEq(inAfter, inBefore, "inFlight unchanged by sendable");
        assertEq(limAfter, limBefore, "limit unchanged by sendable");
        assertEq(winAfter, winBefore, "window unchanged by sendable");
        assertEq(luAfter, luBefore, "lastUpdated unchanged by sendable");
    }

    // ========== receivable ========== //

    function test_receivable_unconfigured_returnsZeros() external view {
        _assertReceivable(EID_A, 0, 0, "unconfigured");
    }

    function test_receivable_elapsedGreaterEqualWindow_returnsZeroAndFullLimit() external {
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.inflow(EID_A, DEFAULT_LIMIT);

        skip(DEFAULT_WINDOW);
        _assertReceivable(EID_A, 0, DEFAULT_LIMIT, "elapsed == window");

        skip(1);
        _assertReceivable(EID_A, 0, DEFAULT_LIMIT, "elapsed > window");
    }

    function test_receivable_zeroWindow_returnsZeroAndFullLimit() external {
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.inflow(EID_A, DEFAULT_LIMIT / 2);

        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, 0)));
        (uint256 stored, , , ) = harness.inRateLimits(EID_A);
        assertEq(stored, DEFAULT_LIMIT / 2, "stored inFlight preserved");

        _assertReceivable(EID_A, 0, DEFAULT_LIMIT, "zero window");
    }

    function test_receivable_elapsedZero_returnsRawInFlightAndDeducted() external {
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.inflow(EID_A, DEFAULT_LIMIT / 4);

        _assertReceivable(
            EID_A,
            DEFAULT_LIMIT / 4,
            DEFAULT_LIMIT - DEFAULT_LIMIT / 4,
            "elapsed == 0"
        );
    }

    function test_receivable_partialDecay_returnsExpected() external {
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.inflow(EID_A, DEFAULT_LIMIT);

        uint256 elapsed = (uint256(DEFAULT_WINDOW) * 13) / 17;
        skip(elapsed);

        uint256 expectedDecayedInFlight = _expectedDecayedInFlight(
            DEFAULT_LIMIT,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            elapsed
        );
        _assertReceivable(
            EID_A,
            expectedDecayedInFlight,
            DEFAULT_LIMIT - expectedDecayedInFlight,
            "partial decay"
        );
    }

    function test_receivable_storedAboveLimit_returnsZeroAvailable() external {
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.inflow(EID_A, DEFAULT_LIMIT);
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT / 2, DEFAULT_WINDOW)));

        _assertReceivable(EID_A, DEFAULT_LIMIT, 0, "stored > limit");
    }

    function test_receivable_doesNotMutateState() external {
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.inflow(EID_A, DEFAULT_LIMIT / 3);

        skip(DEFAULT_WINDOW / 4);

        (uint256 inBefore, uint256 limBefore, uint32 winBefore, uint48 luBefore) = harness
            .inRateLimits(EID_A);

        harness.receivable(EID_A);

        (uint256 inAfter, uint256 limAfter, uint32 winAfter, uint48 luAfter) = harness.inRateLimits(
            EID_A
        );

        assertEq(inAfter, inBefore, "inFlight unchanged by receivable");
        assertEq(limAfter, limBefore, "limit unchanged by receivable");
        assertEq(winAfter, winBefore, "window unchanged by receivable");
        assertEq(luAfter, luBefore, "lastUpdated unchanged by receivable");
    }

    // ========== _currentState (via the harness) ========== //

    function test_currentState_elapsedZero_returnsInFlightAndDeducted() external view {
        (uint256 inFlight, uint256 available) = harness.currentState(
            DEFAULT_LIMIT / 4,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(block.timestamp)
        );
        assertEq(inFlight, DEFAULT_LIMIT / 4, "inFlight unchanged when elapsed == 0");
        assertEq(available, DEFAULT_LIMIT - DEFAULT_LIMIT / 4, "available correct");
    }

    function test_currentState_elapsedEqualWindow_returnsZeroAndFullLimit() external {
        uint48 t0 = uint48(block.timestamp);
        skip(DEFAULT_WINDOW);

        (uint256 inFlight, uint256 available) = harness.currentState(
            DEFAULT_LIMIT,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            t0
        );
        assertEq(inFlight, 0, "inFlight zero at boundary");
        assertEq(available, DEFAULT_LIMIT, "available full at boundary");
    }

    function test_currentState_elapsedGreaterThanWindow_returnsZeroAndFullLimit() external {
        uint48 t0 = uint48(block.timestamp);
        skip(uint256(DEFAULT_WINDOW) * 100);

        (uint256 inFlight, uint256 available) = harness.currentState(
            DEFAULT_LIMIT,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            t0
        );
        assertEq(inFlight, 0, "fully decayed past window");
        assertEq(available, DEFAULT_LIMIT, "available full past window");
    }

    function test_currentState_windowZero_guardsDivisionByZero() external {
        uint48 t0 = uint48(block.timestamp);
        skip(123);

        (uint256 inFlight, uint256 available) = harness.currentState(
            DEFAULT_LIMIT,
            DEFAULT_LIMIT,
            0,
            t0
        );
        assertEq(inFlight, 0, "inFlight zero with zero window");
        assertEq(available, DEFAULT_LIMIT, "available full with zero window");
    }

    function test_currentState_partialDecay_matchesIntegerArithmetic() external {
        uint48 t0 = uint48(block.timestamp);
        skip(PARTIAL_DECAY_ELAPSED);

        uint256 storedInFlight = (DEFAULT_LIMIT * 3) / 5;
        (uint256 inFlight, uint256 available) = harness.currentState(
            storedInFlight,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            t0
        );

        uint256 expectedDecay = (DEFAULT_LIMIT * PARTIAL_DECAY_ELAPSED) / DEFAULT_WINDOW;
        uint256 expectedInFlight = expectedDecay >= storedInFlight
            ? 0
            : storedInFlight - expectedDecay;
        assertEq(inFlight, expectedInFlight, "inFlight matches arithmetic");
        assertEq(available, DEFAULT_LIMIT - expectedInFlight, "available matches arithmetic");
    }

    function test_currentState_decayFloorsAtZero() external {
        uint48 t0 = uint48(block.timestamp);
        // (SMALL_LIMIT * 10) / SMALL_WINDOW per second decay rate; pick
        // storedInFlight at LIMIT/10 and elapsed at WINDOW/2 so decay
        // (= LIMIT/2) cleanly exceeds storedInFlight (= LIMIT/10) before the
        // window ends.
        uint256 storedInFlight = SMALL_LIMIT / 10;
        uint256 elapsed = SMALL_WINDOW / 2;

        skip(elapsed);

        (uint256 inFlight, uint256 available) = harness.currentState(
            storedInFlight,
            SMALL_LIMIT,
            SMALL_WINDOW,
            t0
        );
        assertEq(inFlight, 0, "decay floored at zero");
        assertEq(available, SMALL_LIMIT, "available is full limit when inFlight floored");
    }

    function test_currentState_storedInFlightAboveLimit_availableZero() external view {
        uint256 storedInFlight = DEFAULT_LIMIT * 2;
        (uint256 inFlight, uint256 available) = harness.currentState(
            storedInFlight,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(block.timestamp)
        );
        assertEq(inFlight, storedInFlight, "stored above limit returned as is");
        assertEq(available, 0, "available clamped to zero when stored > limit");
    }

    /// @dev Locks in the integer-division behaviour when `limit << window`. The
    ///      old single-direction RateLimiter shipped with a NatSpec warning
    ///      about this regime; the new contract does not, so we capture the
    ///      observed behaviour here for review.
    function test_currentState_decayPrecision_smallLimitLargeWindow() external {
        uint48 t0 = uint48(block.timestamp);
        uint256 storedInFlight = PRECISION_LIMIT;

        // Decay step size is `window / limit` seconds per unit drop. With
        // PRECISION_LIMIT=100 and PRECISION_WINDOW=1_000_000 that is 10_000s
        // per unit. We verify the rounding at three points along the curve.
        uint256 stepSeconds = uint256(PRECISION_WINDOW) / PRECISION_LIMIT; // 10_000

        // For elapsed below `stepSeconds`, the integer division truncates
        // the entire decay to zero, so `inFlight` does not move.
        skip(stepSeconds / 10); // decay = 0
        (uint256 inFlight, uint256 available) = harness.currentState(
            storedInFlight,
            PRECISION_LIMIT,
            PRECISION_WINDOW,
            t0
        );
        assertEq(inFlight, PRECISION_LIMIT, "decay rounds down to zero with small elapsed");
        assertEq(available, 0, "available is zero while inFlight stays at limit");

        // At elapsed == one full step, decay advances by exactly 1.
        skip(stepSeconds - stepSeconds / 10);
        (inFlight, available) = harness.currentState(
            storedInFlight,
            PRECISION_LIMIT,
            PRECISION_WINDOW,
            t0
        );
        assertEq(inFlight, PRECISION_LIMIT - 1, "decay advances by 1 at one step");
        assertEq(available, 1, "available advances by 1");

        // At elapsed == ten steps, decay == 10.
        skip(stepSeconds * 9);
        (inFlight, available) = harness.currentState(
            storedInFlight,
            PRECISION_LIMIT,
            PRECISION_WINDOW,
            t0
        );
        assertEq(inFlight, PRECISION_LIMIT - 10, "decay == 10 at ten steps");
        assertEq(available, 10, "available == 10 at ten steps");
    }

    /// @notice Locks in the `limit * elapsed` overflow boundary inside
    ///         `_currentState`. The multiplication is not in an `unchecked`
    ///         block, so a `limit` close to `type(uint256).max` reverts with an
    ///         arithmetic-overflow panic for any non-zero `elapsed` < `window`.
    /// @dev This effectively bricks the eid+direction until decay catches up
    ///      (i.e. until `elapsed >= window`, where the early return path
    ///      avoids the multiplication). Flagged in the test summary.
    function test_currentState_limitTimesElapsed_overflowReverts() external {
        uint48 t0 = uint48(block.timestamp);
        // elapsed > 1 causes `type(uint256).max * elapsed` to overflow.
        skip(2);

        vm.expectRevert(stdError.arithmeticError);
        harness.currentState(0, type(uint256).max, DEFAULT_WINDOW, t0);
    }

    /// @notice At `elapsed >= window`, the early-return short-circuits the
    ///         multiplication, so the same `limit` value does not revert.
    function test_currentState_limitMaxValue_doesNotOverflowOnceWindowElapsed() external {
        uint48 t0 = uint48(block.timestamp);
        skip(DEFAULT_WINDOW);

        (uint256 inFlight, uint256 available) = harness.currentState(
            type(uint256).max,
            type(uint256).max,
            DEFAULT_WINDOW,
            t0
        );
        assertEq(inFlight, 0, "early return: inFlight zero");
        assertEq(available, type(uint256).max, "early return: available is full max limit");
    }

    /// @notice Documents that `block.timestamp - lastUpdated` is computed in
    ///         `uint256` after the cast, so the cast-truncation surface is in
    ///         the *write* path, not in `_currentState`. Two assertions: the
    ///         first locks in the trivial `elapsed == 0` case at a high
    ///         `lastUpdated_`, the second pushes `block.timestamp` past
    ///         `lastUpdated_` (using a uint64-capable warp target above
    ///         `UINT48_MAX`) and verifies the subtraction does not overflow.
    function test_currentState_lastUpdatedAtUint48Max_doesNotOverflow() external {
        vm.warp(UINT48_MAX);
        uint48 t0 = uint48(block.timestamp);

        // Sub-case 1: elapsed == 0 returns the stored value via the early-
        // return path without touching the multiplication.
        (uint256 inFlight, uint256 available) = harness.currentState(
            DEFAULT_LIMIT / 2,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            t0
        );
        assertEq(inFlight, DEFAULT_LIMIT / 2, "elapsed == 0 returns stored value");
        assertEq(available, DEFAULT_LIMIT / 2, "available correct at uint48 boundary");

        // Sub-case 2: warp past UINT48_MAX so `block.timestamp` is in the
        // uint64 region while `lastUpdated_` is at the uint48 ceiling, then
        // call `currentState` with the same `lastUpdated_`. The subtraction
        // is computed in uint256 after the cast so it must not overflow, and
        // since `elapsed >= window` the early-return path triggers.
        vm.warp(UINT48_MAX + uint256(DEFAULT_WINDOW));
        (inFlight, available) = harness.currentState(
            DEFAULT_LIMIT / 2,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            t0
        );
        assertEq(inFlight, 0, "early return: inFlight zero past uint48 boundary");
        assertEq(available, DEFAULT_LIMIT, "early return: available is full limit");
    }

    /// @notice Locks in cast-truncation behaviour at `block.timestamp ==
    ///         type(uint48).max + 1`. The cast `uint48(block.timestamp)`
    ///         truncates to zero, so any subsequent read sees a huge `elapsed`
    ///         and falls into the early-return path. Flagged in the summary.
    function test_setRateLimits_writesAtTimestampPastUint48_truncates() external {
        vm.warp(UINT48_MAX + 1);
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        (, , , uint48 lastUpdated) = harness.outRateLimits(EID_A);
        assertEq(lastUpdated, 0, "uint48 cast wraps to zero one past the boundary");

        // The view consequently reports `elapsed >= window` and returns full
        // capacity even though no time has passed in the calling perspective.
        _assertSendable(EID_A, 0, DEFAULT_LIMIT, "view sees full capacity after truncation");
    }

    // ========== outRateLimits ========== //

    function test_outRateLimits_unconfiguredEid_returnsZeros() external view {
        _assertOutState(EID_A, 0, 0, 0, 0, "default");
    }

    function test_outRateLimits_afterConfig_storesAllFields() external {
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        _assertOutState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(block.timestamp),
            "after setOut"
        );
    }

    function test_outRateLimits_afterOutflow_returnsRawNotDecayedInFlight() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 amount = DEFAULT_LIMIT / 4;
        uint48 t0 = uint48(block.timestamp);

        harness.outflow(EID_A, amount);

        // Warp halfway into the window. The raw stored value should not change,
        // even though the decayed view value does.
        vm.warp(uint256(t0) + DEFAULT_WINDOW / 2);

        _assertOutState(EID_A, amount, DEFAULT_LIMIT, DEFAULT_WINDOW, t0, "raw after warp");

        // sendable returns the decayed view, which differs from the raw stored
        // value mid-window.
        uint256 expectedDecayedInFlight = _expectedDecayedInFlight(
            amount,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            DEFAULT_WINDOW / 2
        );
        _assertSendable(
            EID_A,
            expectedDecayedInFlight,
            DEFAULT_LIMIT - expectedDecayedInFlight,
            "decayed view"
        );
    }

    // ========== inRateLimits ========== //

    function test_inRateLimits_unconfiguredEid_returnsZeros() external view {
        _assertInState(EID_A, 0, 0, 0, 0, "default");
    }

    function test_inRateLimits_afterConfig_storesAllFields() external {
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        _assertInState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(block.timestamp),
            "after setIn"
        );
    }

    function test_inRateLimits_afterInflow_returnsRawNotDecayedInFlight() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 amount = DEFAULT_LIMIT / 4;
        uint48 t0 = uint48(block.timestamp);

        harness.inflow(EID_A, amount);

        vm.warp(uint256(t0) + DEFAULT_WINDOW / 2);

        _assertInState(EID_A, amount, DEFAULT_LIMIT, DEFAULT_WINDOW, t0, "raw after warp");

        uint256 expectedDecayedInFlight = _expectedDecayedInFlight(
            amount,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            DEFAULT_WINDOW / 2
        );
        _assertReceivable(
            EID_A,
            expectedDecayedInFlight,
            DEFAULT_LIMIT - expectedDecayedInFlight,
            "decayed view"
        );
    }
}
