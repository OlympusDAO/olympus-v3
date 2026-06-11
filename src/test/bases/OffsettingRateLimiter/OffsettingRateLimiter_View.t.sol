// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {OffsettingRateLimiterTestBase} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

// Libraries
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";

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
            uint48(vm.getBlockTimestamp())
        );
        assertEq(inFlight, DEFAULT_LIMIT / 4, "inFlight unchanged when elapsed == 0");
        assertEq(available, DEFAULT_LIMIT - DEFAULT_LIMIT / 4, "available correct");
    }

    function test_currentState_elapsedEqualWindow_returnsZeroAndFullLimit() external {
        uint48 t0 = uint48(vm.getBlockTimestamp());
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
        uint48 t0 = uint48(vm.getBlockTimestamp());
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
        uint48 t0 = uint48(vm.getBlockTimestamp());
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
        uint48 t0 = uint48(vm.getBlockTimestamp());
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
        uint48 t0 = uint48(vm.getBlockTimestamp());
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
            uint48(vm.getBlockTimestamp())
        );
        assertEq(inFlight, storedInFlight, "stored above limit returned as is");
        assertEq(available, 0, "available clamped to zero when stored > limit");
    }

    /// @dev Locks in the integer-division behaviour when `limit << window`. The
    ///      old single-direction RateLimiter shipped with a NatSpec warning
    ///      about this regime; the new contract does not, so we capture the
    ///      observed behaviour here for review.
    function test_currentState_decayPrecision_smallLimitLargeWindow() external {
        uint48 t0 = uint48(vm.getBlockTimestamp());
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

    /// @notice Locks in that `_currentState` handles `limit * elapsed`
    ///         products that exceed `2 ** 256` via the 512-bit intermediate
    ///         in `Math.mulDiv`, so a `limit` close to `type(uint256).max`
    ///         no longer reverts mid-window.
    function test_currentState_limitMaxValue_doesNotOverflowMidWindow() external {
        uint48 t0 = uint48(vm.getBlockTimestamp());
        // elapsed > 1 used to overflow `type(uint256).max * elapsed`.
        skip(2);

        (uint256 inFlight, uint256 available) = harness.currentState(
            0,
            type(uint256).max,
            DEFAULT_WINDOW,
            t0
        );
        // Stored inFlight was zero, so the post-decay value clamps at zero
        // regardless of the computed decay magnitude.
        assertEq(inFlight, 0, "inFlight stays at zero");
        // available = limit - inFlight = type(uint256).max - 0.
        assertEq(available, type(uint256).max, "available is full max limit");
    }

    /// @notice Locks in that `_currentState` does not revert when every
    ///         input is saturated at its type maximum just below the window
    ///         boundary. `Math.mulDiv` reverts only when the *result*
    ///         exceeds `type(uint256).max`; here `decay = floor(limit *
    ///         elapsed / window) < limit <= type(uint256).max` because
    ///         `elapsed < window`, so the result always fits.
    function test_currentState_allMaxValuesJustBelowWindow_doesNotRevert() external {
        uint48 t0 = uint48(vm.getBlockTimestamp());
        uint32 window = type(uint32).max;
        skip(uint256(window) - 1);

        (uint256 inFlight, uint256 available) = harness.currentState(
            type(uint256).max,
            type(uint256).max,
            window,
            t0
        );

        // With `inFlight_ = limit_ = max` and `elapsed = window - 1`,
        // `decay = floor(max * (window - 1) / window)`, the post-decay
        // value is `max - decay`, and `available = limit - inFlight`.
        uint256 expectedDecay = Math.mulDiv(
            type(uint256).max,
            uint256(window) - 1,
            uint256(window)
        );
        uint256 expectedInFlight = type(uint256).max - expectedDecay;
        assertEq(inFlight, expectedInFlight, "inFlight matches mulDiv");
        assertEq(available, type(uint256).max - expectedInFlight, "available matches");
    }

    /// @notice At `elapsed >= window` the early-return path skips the
    ///         multiplication entirely, so the same `limit` value passes
    ///         through without touching `Math.mulDiv`.
    function test_currentState_limitMaxValue_doesNotOverflowOnceWindowElapsed() external {
        uint48 t0 = uint48(vm.getBlockTimestamp());
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

    /// @notice Documents that `vm.getBlockTimestamp() - lastUpdated` is computed in
    ///         `uint256` after the cast, so the cast-truncation surface is in
    ///         the *write* path, not in `_currentState`. Two assertions: the
    ///         first locks in the trivial `elapsed == 0` case at a high
    ///         `lastUpdated_`, the second pushes `vm.getBlockTimestamp()` past
    ///         `lastUpdated_` (using a uint64-capable warp target above
    ///         `UINT48_MAX`) and verifies the subtraction does not overflow.
    function test_currentState_lastUpdatedAtUint48Max_doesNotOverflow() external {
        vm.warp(UINT48_MAX);
        uint48 t0 = uint48(vm.getBlockTimestamp());

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

        // Sub-case 2: warp past UINT48_MAX so `vm.getBlockTimestamp()` is in the
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

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_currentState_decayMonotonic(
        uint256 limit_,
        uint32 window_,
        uint256 inFlight_,
        uint64 t1_,
        uint64 t2_
    ) external {
        limit_ = bound(limit_, 1, FUZZ_LIMIT_CEIL);
        window_ = uint32(bound(uint256(window_), MIN_WINDOW, MAX_WINDOW));
        inFlight_ = bound(inFlight_, 0, FUZZ_LIMIT_CEIL);
        // Pick t1 <= t2 inside the window. Warp forward so `vm.getBlockTimestamp() -
        // t1/t2` stays well-defined.
        t1_ = uint64(bound(uint256(t1_), 0, uint256(window_) - 1));
        t2_ = uint64(bound(uint256(t2_), uint256(t1_), uint256(window_) - 1));
        // Ensure vm.getBlockTimestamp() is past `window_` so the subtraction below
        // does not underflow regardless of the (now-bounded) inputs.
        vm.warp(uint256(window_) + START_TIMESTAMP);

        uint48 t0 = uint48(vm.getBlockTimestamp());
        uint48 lu1 = uint48(uint256(t0) - uint256(t1_));
        uint48 lu2 = uint48(uint256(t0) - uint256(t2_));
        (uint256 inFlightAtT1, ) = harness.currentState(inFlight_, limit_, window_, lu1);
        (uint256 inFlightAtT2, ) = harness.currentState(inFlight_, limit_, window_, lu2);

        assertLe(inFlightAtT2, inFlightAtT1, "inFlight monotonic non-increasing in elapsed");
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_currentState_decayRecoversAfterWindow(
        uint256 limit_,
        uint32 window_,
        uint256 inFlight_,
        uint64 elapsed_
    ) external {
        limit_ = bound(limit_, 0, FUZZ_LIMIT_CEIL);
        window_ = uint32(bound(uint256(window_), 0, MAX_WINDOW));
        inFlight_ = bound(inFlight_, 0, type(uint256).max);
        // Cap elapsed at the uint48 max so the cast below stays in range
        elapsed_ = uint64(bound(uint256(elapsed_), uint256(window_), UINT48_MAX / 2));

        // Warp far enough that `vm.getBlockTimestamp() - elapsed_` does not underflow
        // and stays in uint48.
        vm.warp(UINT48_MAX);
        uint48 lastUpdated = uint48(vm.getBlockTimestamp() - elapsed_);

        (uint256 inFlight, uint256 available) = harness.currentState(
            inFlight_,
            limit_,
            window_,
            lastUpdated
        );

        assertEq(inFlight, 0, "decayed to zero past window");
        assertEq(available, limit_, "full limit available past window");
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
            uint48(vm.getBlockTimestamp()),
            "after setOut"
        );
    }

    function test_outRateLimits_afterOutflow_returnsRawNotDecayedInFlight() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 amount = DEFAULT_LIMIT / 4;
        uint48 t0 = uint48(vm.getBlockTimestamp());

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
            uint48(vm.getBlockTimestamp()),
            "after setIn"
        );
    }

    function test_inRateLimits_afterInflow_returnsRawNotDecayedInFlight() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 amount = DEFAULT_LIMIT / 4;
        uint48 t0 = uint48(vm.getBlockTimestamp());

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
