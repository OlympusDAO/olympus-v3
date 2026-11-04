// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {OffsettingRateLimiterTestBase} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

/// @dev Tests for `_outflow` (exposed via the harness as `outflow`).
contract OffsettingRateLimiterTests_Outflow is OffsettingRateLimiterTestBase {
    // ========== REVERTS ========== //

    function test_outflow_amountExceedsAvailable_revertsWithExactArgs() external {
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        uint256 requested = DEFAULT_LIMIT + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IOffsettingRateLimiter.RateLimitExceeded.selector,
                requested,
                DEFAULT_LIMIT
            )
        );
        harness.outflow(EID_A, requested);
    }

    function test_outflow_unconfiguredEid_nonZeroAmount_reverts() external {
        vm.expectRevert(
            abi.encodeWithSelector(IOffsettingRateLimiter.RateLimitExceeded.selector, 1, 0)
        );
        harness.outflow(EID_A, 1);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_outflow_alwaysRevertsAboveAvailable(
        uint256 limit_,
        uint32 window_,
        uint256 amount_,
        uint64 elapsed_
    ) external {
        limit_ = bound(limit_, 1, FUZZ_LIMIT_CEIL);
        window_ = uint32(bound(uint256(window_), MIN_WINDOW, MAX_WINDOW));
        elapsed_ = uint64(bound(uint256(elapsed_), 0, uint256(window_) - 1));

        harness.setOutRateLimits(_configs(_config(EID_A, limit_, window_)));
        skip(elapsed_);

        // The available capacity is `limit_` since the stored inFlight is zero
        amount_ = bound(amount_, limit_ + 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOffsettingRateLimiter.RateLimitExceeded.selector,
                amount_,
                limit_
            )
        );
        harness.outflow(EID_A, amount_);
    }

    // ========== SUCCESS AT BOUNDARY ========== //

    function test_outflow_amountEqualsAvailable_succeeds() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        harness.outflow(EID_A, DEFAULT_LIMIT);

        _assertOutState(
            EID_A,
            DEFAULT_LIMIT,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "boundary"
        );
        _assertSendable(EID_A, DEFAULT_LIMIT, 0, "no capacity left");
    }

    // ========== ZERO AMOUNT ========== //

    function test_outflow_unconfiguredEid_zeroAmount_doesNotRevert() external {
        // A zero-amount call against an unconfigured eid is a checkpoint that
        // touches both sides without recording any flow.
        harness.outflow(EID_A, 0);

        _assertOutState(EID_A, 0, 0, 0, uint48(vm.getBlockTimestamp()), "out cp");
        _assertInState(EID_A, 0, 0, 0, uint48(vm.getBlockTimestamp()), "in cp");
    }

    function test_outflow_zeroAmount_actsAsCheckpoint() external {
        // Drive both sides to a known non-zero stored value.
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT / 2);
        harness.clearInboundInFlight(_eids(EID_A));
        harness.inflow(EID_A, DEFAULT_LIMIT / 4);
        // Now: in = LIMIT/4, out = subOrZero(LIMIT/2, LIMIT/4) = LIMIT/4.

        (uint256 outInFlightBefore, , , ) = harness.outRateLimits(EID_A);
        (uint256 inInFlightBefore, , , ) = harness.inRateLimits(EID_A);
        assertEq(outInFlightBefore, DEFAULT_LIMIT / 4, "out primed");
        assertEq(inInFlightBefore, DEFAULT_LIMIT / 4, "in primed");

        skip(DEFAULT_WINDOW / 8);

        // The view returns the decayed values that the checkpoint will store.
        (uint256 expectedOut, ) = harness.sendable(EID_A);
        (uint256 expectedIn, ) = harness.receivable(EID_A);

        assertLt(expectedOut, outInFlightBefore, "out has decayed");
        assertLt(expectedIn, inInFlightBefore, "in has decayed");

        harness.outflow(EID_A, 0);

        _assertOutState(
            EID_A,
            expectedOut,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "out cp"
        );
        _assertInState(
            EID_A,
            expectedIn,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "in cp"
        );
    }

    // ========== POST-STATE ========== //

    /// @notice No-counterpart variant: drive outbound to LIMIT/2, warp a
    ///         quarter window, then outflow LIMIT/8 (strictly less than the
    ///         decayed value so the counterpart is touched only via the
    ///         standard `subOrZero(0, amount) = 0` write). The
    ///         with-counterpart case is locked in by
    ///         `test_outflow_postState_withCounterpartCredit` below.
    function test_outflow_postState_matchesAlgorithm() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT / 2);

        skip(DEFAULT_WINDOW / 4);

        // decayedOut = LIMIT/2 - (LIMIT * WINDOW/4) / WINDOW = LIMIT/4
        uint256 expectedOutDecayed = _expectedDecayedInFlight(
            DEFAULT_LIMIT / 2,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            DEFAULT_WINDOW / 4
        );
        assertEq(expectedOutDecayed, DEFAULT_LIMIT / 4, "decayed out matches arithmetic");

        uint256 amount = DEFAULT_LIMIT / 8;
        harness.outflow(EID_A, amount);

        (uint256 outInFlight, , , uint48 outLu) = harness.outRateLimits(EID_A);
        assertEq(outInFlight, expectedOutDecayed + amount, "out.inFlight = decayedOut + amount");
        assertEq(outLu, uint48(vm.getBlockTimestamp()), "out.lastUpdated refreshed");

        (uint256 inInFlight, , , uint48 inLu) = harness.inRateLimits(EID_A);
        assertEq(inInFlight, 0, "in.inFlight stays at zero (no prior inflow)");
        assertEq(inLu, uint48(vm.getBlockTimestamp()), "in.lastUpdated refreshed");
    }

    function test_outflow_postState_withCounterpartCredit() external {
        // Same shape as `test_outflow_postState_matchesAlgorithm` but with a
        // pre-existing counterpart (inbound) inFlight, exercising the
        // `_subOrZero(decayedIn, amount)` write back to the counterpart.
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.inflow(EID_A, DEFAULT_LIMIT / 2);

        skip(DEFAULT_WINDOW / 4);

        uint256 expectedInDecayed = _expectedDecayedInFlight(
            DEFAULT_LIMIT / 2,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            DEFAULT_WINDOW / 4
        );
        assertEq(expectedInDecayed, DEFAULT_LIMIT / 4, "decayed in matches arithmetic");

        // Pick amount < decayedIn so the floor branch is not hit and the
        // counterpart is reduced by exactly `amount`.
        uint256 amount = DEFAULT_LIMIT / 8;

        harness.outflow(EID_A, amount);

        (uint256 outInFlight, , , uint48 outLu) = harness.outRateLimits(EID_A);
        // Stored out before this outflow was 0; decay does not matter.
        assertEq(outInFlight, amount, "out.inFlight = amount");
        assertEq(outLu, uint48(vm.getBlockTimestamp()), "out.lastUpdated refreshed");

        (uint256 inInFlight, , , uint48 inLu) = harness.inRateLimits(EID_A);
        assertEq(inInFlight, expectedInDecayed - amount, "in.inFlight = decayedIn - amount");
        assertEq(inLu, uint48(vm.getBlockTimestamp()), "in.lastUpdated refreshed");
    }

    // ========== COUNTERPART CREDIT CLAMPED AT ZERO ========== //

    /// @notice Counterpart inbound is at zero; outflow leaves it at zero.
    function test_outflow_counterpartFloorAtZero() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        harness.outflow(EID_A, DEFAULT_LIMIT / 2);

        _assertInState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "in stays at zero"
        );
    }

    /// @notice Counterpart inbound at `c`, outflow `a > c` leaves counterpart
    ///         at zero; the residual `a - c` is dropped, not carried over.
    function test_outflow_counterpartCreditConsumedAndExcessDropped() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        // Prime the inbound side to some value `c`.
        uint256 c = DEFAULT_LIMIT / 4;
        harness.inflow(EID_A, c);

        // Outflow `a > c`. After the call:
        //   in.inFlight = subOrZero(c, a) = 0
        //   The residual `a - c` is dropped (not credited as out reduction).
        uint256 a = c + DEFAULT_LIMIT / 8;
        harness.outflow(EID_A, a);

        _assertInState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "counterpart wiped"
        );
        // Out is debited the full amount `a`, regardless of `c`.
        _assertOutState(
            EID_A,
            a,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "out debited in full"
        );
    }

    // ========== SAME-BLOCK ACCUMULATION ========== //

    function test_outflow_sameBlock_accumulatesOnOut() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        uint256 amount = DEFAULT_LIMIT / 4;
        harness.outflow(EID_A, amount);
        harness.outflow(EID_A, amount);
        harness.outflow(EID_A, amount);
        harness.outflow(EID_A, amount);

        _assertOutState(
            EID_A,
            DEFAULT_LIMIT,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "accumulated"
        );
    }

    // ========== INDEPENDENCE ACROSS EIDS ========== //

    function test_outflow_doesNotChangeOtherEids() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        _setupBoth(EID_B, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        // Snapshot EID_B before.
        (uint256 outInFlightB, uint256 outLimitB, uint32 outWindowB, uint48 outLuB) = harness
            .outRateLimits(EID_B);
        (uint256 inInFlightB, uint256 inLimitB, uint32 inWindowB, uint48 inLuB) = harness
            .inRateLimits(EID_B);

        harness.outflow(EID_A, DEFAULT_LIMIT);

        _assertOutState(EID_B, outInFlightB, outLimitB, outWindowB, outLuB, "B out untouched");
        _assertInState(EID_B, inInFlightB, inLimitB, inWindowB, inLuB, "B in untouched");
    }

    // ========== SEQUENCED TWO-LEG SCENARIOS (SAME BLOCK) ========== //

    function test_outflow_sameBlock_outThenIn_equalAmounts_outZeroInX() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 x = DEFAULT_LIMIT / 4;

        harness.outflow(EID_A, x);
        harness.inflow(EID_A, x);

        // After outflow(x): out=x, in=0.
        // After inflow(x):  in=0+x=x, out=subOrZero(x, x)=0.
        (uint256 outInFlight, , , ) = harness.outRateLimits(EID_A);
        (uint256 inInFlight, , , ) = harness.inRateLimits(EID_A);
        assertEq(outInFlight, 0, "out = 0");
        assertEq(inInFlight, x, "in = x");
    }

    function test_outflow_sameBlock_inThenOut_equalAmounts_inZeroOutX() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 x = DEFAULT_LIMIT / 4;

        harness.inflow(EID_A, x);
        harness.outflow(EID_A, x);

        (uint256 outInFlight, , , ) = harness.outRateLimits(EID_A);
        (uint256 inInFlight, , , ) = harness.inRateLimits(EID_A);
        assertEq(inInFlight, 0, "in = 0");
        assertEq(outInFlight, x, "out = x");
    }

    function test_outflow_sameBlock_outThenInLess_outResidualEqualsDifference() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 x = DEFAULT_LIMIT / 2;
        uint256 y = DEFAULT_LIMIT / 4; // y < x

        harness.outflow(EID_A, x);
        harness.inflow(EID_A, y);

        (uint256 outInFlight, , , ) = harness.outRateLimits(EID_A);
        (uint256 inInFlight, , , ) = harness.inRateLimits(EID_A);
        assertEq(outInFlight, x - y, "out = x - y");
        assertEq(inInFlight, y, "in = y");
    }

    function test_outflow_sameBlock_outThenInMore_outZeroInY() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 x = DEFAULT_LIMIT / 4;
        uint256 y = DEFAULT_LIMIT / 2; // y > x

        harness.outflow(EID_A, x);
        harness.inflow(EID_A, y);

        (uint256 outInFlight, , , ) = harness.outRateLimits(EID_A);
        (uint256 inInFlight, , , ) = harness.inRateLimits(EID_A);
        assertEq(outInFlight, 0, "out = 0");
        assertEq(inInFlight, y, "in = y");
    }

    // ========== TIME-GAP ROUND TRIPS ========== //

    /// @notice `_outflow(eid, x)` at t=0, `_inflow(eid, x)` at t=Delta with
    ///         0 < Delta < window. The leading leg's decayed value is `x -
    ///         decay`, which is at most `x`, so it is fully cancelled by the
    ///         trailing leg. The trailing leg credits `x`.
    function test_outflow_timeGap_outThenInEqual_outZeroInX() external {
        uint32 window = DEFAULT_WINDOW;
        uint256 limit = DEFAULT_LIMIT;
        uint256 x = limit / 2;
        uint256 delta = window / 4;

        _setupBoth(EID_A, limit, window, 0);
        harness.outflow(EID_A, x);
        skip(delta);
        harness.inflow(EID_A, x);

        // decay = (limit * delta) / window
        uint256 decay = (limit * delta) / window;
        uint256 decayedOut = x > decay ? x - decay : 0;

        // After inflow:
        //   in.inFlight = decayedIn(=0) + x = x
        //   out.inFlight = subOrZero(decayedOut, x) = 0  (since decayedOut <= x)
        (uint256 outInFlight, , , ) = harness.outRateLimits(EID_A);
        (uint256 inInFlight, , , ) = harness.inRateLimits(EID_A);
        assertEq(outInFlight, 0, "out = 0 (residual <= x cancels fully)");
        assertEq(inInFlight, x, "in = x");
        // Sanity: decayedOut < x, so the leading leg was already partially decayed.
        assertLt(decayedOut, x, "leading leg has decayed");
    }

    /// @notice `_outflow(eid, x)` at t=0, `_inflow(eid, y)` at t=Delta with
    ///         `y >= x - decay`. Leading leg fully cancelled.
    function test_outflow_timeGap_outThenIn_yAtLeastXMinusDecay_outZeroInY() external {
        uint32 window = DEFAULT_WINDOW;
        uint256 limit = DEFAULT_LIMIT;
        uint256 x = limit / 2;
        uint256 delta = window / 4;

        _setupBoth(EID_A, limit, window, 0);
        harness.outflow(EID_A, x);
        skip(delta);

        uint256 decay = (limit * delta) / window;
        uint256 decayedOut = x > decay ? x - decay : 0;
        // Pick y between decayedOut and limit so the leading leg is fully
        // cancelled, but y still fits within the inbound limit.
        uint256 y = decayedOut + (limit - decayedOut) / 2;
        assertGe(y, decayedOut, "y >= decayedOut for the test to be meaningful");

        harness.inflow(EID_A, y);

        (uint256 outInFlight, , , ) = harness.outRateLimits(EID_A);
        (uint256 inInFlight, , , ) = harness.inRateLimits(EID_A);
        assertEq(outInFlight, 0, "out = 0");
        assertEq(inInFlight, y, "in = y");
    }

    /// @notice `_outflow(eid, x)` at t=0, `_inflow(eid, y)` at t=Delta with
    ///         `y < x - decay`. Leading leg only partially cancelled.
    function test_outflow_timeGap_outThenIn_yLessThanXMinusDecay_outResidualInY() external {
        uint32 window = DEFAULT_WINDOW;
        uint256 limit = DEFAULT_LIMIT;
        uint256 x = limit / 2;
        uint256 delta = window / 4;

        _setupBoth(EID_A, limit, window, 0);
        harness.outflow(EID_A, x);
        skip(delta);

        uint256 decay = (limit * delta) / window;
        uint256 decayedOut = x > decay ? x - decay : 0;
        // Pick y strictly less than decayedOut.
        uint256 y = decayedOut / 2;
        assertLt(y, decayedOut, "y < decayedOut for the partial-cancel branch");

        harness.inflow(EID_A, y);

        (uint256 outInFlight, , , ) = harness.outRateLimits(EID_A);
        (uint256 inInFlight, , , ) = harness.inRateLimits(EID_A);
        assertEq(outInFlight, decayedOut - y, "out = decayedOut - y");
        assertEq(inInFlight, y, "in = y");
    }

    // ========== POST-STATE: FUZZ WITHIN AVAILABLE ========== //

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_outflow_neverRevertsWithinAvailable(
        uint256 limit_,
        uint32 window_,
        uint256 amount_,
        uint64 elapsed_
    ) external {
        limit_ = bound(limit_, 1, FUZZ_LIMIT_CEIL);
        window_ = uint32(bound(uint256(window_), MIN_WINDOW, MAX_WINDOW));
        elapsed_ = uint64(bound(uint256(elapsed_), 0, uint256(window_) - 1));

        harness.setOutRateLimits(_configs(_config(EID_A, limit_, window_)));
        skip(elapsed_);

        // No prior outflow, so the available capacity equals the limit (decay
        // is irrelevant).
        amount_ = bound(amount_, 0, limit_);

        harness.outflow(EID_A, amount_);

        (uint256 outInFlight, , , uint48 outLu) = harness.outRateLimits(EID_A);
        // The pre-existing inFlight was zero, so the post-state is
        // `0 + amount_ == amount_`.
        assertEq(outInFlight, amount_, "post-state matches simulation");
        assertEq(outLu, uint48(vm.getBlockTimestamp()), "lastUpdated refreshed");
    }
}
