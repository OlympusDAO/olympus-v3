// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {OffsettingRateLimiterTestBase} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

/// @dev Tests for `_inflow` (exposed via the harness as `inflow`). Mirrors
///      `OffsettingRateLimiter_Outflow.t.sol`, with the inbound and outbound roles
///      swapped. Locks in the deliberate departure from the older
///      single-direction "subtract from outbound" semantics: the outbound
///      counterpart credit is clamped at zero with no carry-over.
contract OffsettingRateLimiterTests_Inflow is OffsettingRateLimiterTestBase {
    // ========== REVERTS ========== //

    function test_inflow_amountExceedsAvailable_revertsWithExactArgs() external {
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        uint256 requested = DEFAULT_LIMIT + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IOffsettingRateLimiter.RateLimitExceeded.selector,
                requested,
                DEFAULT_LIMIT
            )
        );
        harness.inflow(EID_A, requested);
    }

    function test_inflow_unconfiguredEid_nonZeroAmount_reverts() external {
        vm.expectRevert(
            abi.encodeWithSelector(IOffsettingRateLimiter.RateLimitExceeded.selector, 1, 0)
        );
        harness.inflow(EID_A, 1);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_inflow_alwaysRevertsAboveAvailable(
        uint256 limit_,
        uint32 window_,
        uint256 amount_,
        uint64 elapsed_
    ) external {
        limit_ = bound(limit_, 1, FUZZ_LIMIT_CEIL);
        window_ = uint32(bound(uint256(window_), MIN_WINDOW, MAX_WINDOW));
        elapsed_ = uint64(bound(uint256(elapsed_), 0, uint256(window_) - 1));

        harness.setInRateLimits(_configs(_config(EID_A, limit_, window_)));
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
        harness.inflow(EID_A, amount_);
    }

    // ========== SUCCESS AT BOUNDARY ========== //

    function test_inflow_amountEqualsAvailable_succeeds() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        harness.inflow(EID_A, DEFAULT_LIMIT);

        _assertInState(
            EID_A,
            DEFAULT_LIMIT,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "boundary"
        );
        _assertReceivable(EID_A, DEFAULT_LIMIT, 0, "no capacity left");
    }

    // ========== ZERO AMOUNT ========== //

    function test_inflow_unconfiguredEid_zeroAmount_doesNotRevert() external {
        // A zero-amount call against an unconfigured eid is a checkpoint that
        // touches both sides without recording any flow.
        harness.inflow(EID_A, 0);

        _assertOutState(EID_A, 0, 0, 0, uint48(vm.getBlockTimestamp()), "out cp");
        _assertInState(EID_A, 0, 0, 0, uint48(vm.getBlockTimestamp()), "in cp");
    }

    function test_inflow_zeroAmount_actsAsCheckpoint() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        // Prime both sides to (out, in) = (LIMIT/4, LIMIT/4):
        //   outflow(LIMIT/2)               -> out = LIMIT/2, in = 0
        //   clearInboundInFlight           -> out = LIMIT/2, in = 0 (no-op on out)
        //   inflow(LIMIT/4)                -> in = LIMIT/4, out = subOrZero(LIMIT/2, LIMIT/4) = LIMIT/4
        harness.outflow(EID_A, DEFAULT_LIMIT / 2);
        harness.clearInboundInFlight(_eids(EID_A));
        harness.inflow(EID_A, DEFAULT_LIMIT / 4);

        (uint256 outBefore, , , ) = harness.outRateLimits(EID_A);
        (uint256 inBefore, , , ) = harness.inRateLimits(EID_A);
        assertEq(outBefore, DEFAULT_LIMIT / 4, "out primed to LIMIT/4");
        assertEq(inBefore, DEFAULT_LIMIT / 4, "in primed to LIMIT/4");

        skip(DEFAULT_WINDOW / 8);

        (uint256 expectedOut, ) = harness.sendable(EID_A);
        (uint256 expectedIn, ) = harness.receivable(EID_A);

        assertLt(expectedOut, outBefore, "out has decayed");
        assertLt(expectedIn, inBefore, "in has decayed");

        harness.inflow(EID_A, 0);

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

    // ========== POST-STATE WITHOUT PRIOR OUTFLOW ========== //

    /// @notice Inflow with no prior outflow on a configured inbound limit
    ///         records on the inbound side as a normal debit; the outbound
    ///         counterpart credit is clamped at zero (no carry-over). This is
    ///         a deliberate departure from a "subtract from outbound" model.
    function test_inflow_noPriorOutflow_outboundCreditClampedAtZero() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        harness.inflow(EID_A, DEFAULT_LIMIT / 2);

        _assertInState(
            EID_A,
            DEFAULT_LIMIT / 2,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "in debited"
        );
        _assertOutState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "out clamped at zero"
        );
    }

    function test_inflow_postState_withCounterpartCredit() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT / 2);

        skip(DEFAULT_WINDOW / 4);

        uint256 expectedOutDecayed = _expectedDecayedInFlight(
            DEFAULT_LIMIT / 2,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            DEFAULT_WINDOW / 4
        );
        assertEq(expectedOutDecayed, DEFAULT_LIMIT / 4, "decayed out matches arithmetic");

        uint256 amount = DEFAULT_LIMIT / 8; // < decayedOut
        harness.inflow(EID_A, amount);

        (uint256 inInFlight, , , uint48 inLu) = harness.inRateLimits(EID_A);
        assertEq(inInFlight, amount, "in.inFlight = amount");
        assertEq(inLu, uint48(vm.getBlockTimestamp()), "in.lastUpdated refreshed");

        (uint256 outInFlight, , , uint48 outLu) = harness.outRateLimits(EID_A);
        assertEq(outInFlight, expectedOutDecayed - amount, "out.inFlight = decayedOut - amount");
        assertEq(outLu, uint48(vm.getBlockTimestamp()), "out.lastUpdated refreshed");
    }

    // ========== COUNTERPART CREDIT CLAMPED AT ZERO ========== //

    function test_inflow_counterpartFloorAtZero() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        harness.inflow(EID_A, DEFAULT_LIMIT / 2);

        _assertOutState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "out stays at zero"
        );
    }

    function test_inflow_counterpartCreditConsumedAndExcessDropped() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        uint256 c = DEFAULT_LIMIT / 4;
        harness.outflow(EID_A, c);

        uint256 a = c + DEFAULT_LIMIT / 8;
        harness.inflow(EID_A, a);

        _assertOutState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "counterpart wiped"
        );
        _assertInState(
            EID_A,
            a,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "in debited in full"
        );
    }

    // ========== SAME-BLOCK ACCUMULATION ========== //

    function test_inflow_sameBlock_accumulatesOnIn() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        uint256 amount = DEFAULT_LIMIT / 4;
        harness.inflow(EID_A, amount);
        harness.inflow(EID_A, amount);
        harness.inflow(EID_A, amount);
        harness.inflow(EID_A, amount);

        _assertInState(
            EID_A,
            DEFAULT_LIMIT,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "accumulated"
        );
    }

    // ========== INDEPENDENCE ACROSS EIDS ========== //

    function test_inflow_doesNotChangeOtherEids() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        _setupBoth(EID_B, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        (uint256 outInFlightB, uint256 outLimitB, uint32 outWindowB, uint48 outLuB) = harness
            .outRateLimits(EID_B);
        (uint256 inInFlightB, uint256 inLimitB, uint32 inWindowB, uint48 inLuB) = harness
            .inRateLimits(EID_B);

        harness.inflow(EID_A, DEFAULT_LIMIT);

        _assertOutState(EID_B, outInFlightB, outLimitB, outWindowB, outLuB, "B out untouched");
        _assertInState(EID_B, inInFlightB, inLimitB, inWindowB, inLuB, "B in untouched");
    }

    // ========== POST-STATE: FUZZ WITHIN AVAILABLE ========== //

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_inflow_neverRevertsWithinAvailable(
        uint256 limit_,
        uint32 window_,
        uint256 amount_,
        uint64 elapsed_
    ) external {
        limit_ = bound(limit_, 1, FUZZ_LIMIT_CEIL);
        window_ = uint32(bound(uint256(window_), MIN_WINDOW, MAX_WINDOW));
        elapsed_ = uint64(bound(uint256(elapsed_), 0, uint256(window_) - 1));

        harness.setInRateLimits(_configs(_config(EID_A, limit_, window_)));
        skip(elapsed_);

        // No prior inflow, so the available capacity equals the limit (decay
        // is irrelevant).
        amount_ = bound(amount_, 0, limit_);

        harness.inflow(EID_A, amount_);

        (uint256 inInFlight, , , uint48 inLu) = harness.inRateLimits(EID_A);
        // The pre-existing inFlight was zero, so the post-state is
        // `0 + amount_ == amount_`.
        assertEq(inInFlight, amount_, "post-state matches simulation");
        assertEq(inLu, uint48(vm.getBlockTimestamp()), "lastUpdated refreshed");
    }
}
