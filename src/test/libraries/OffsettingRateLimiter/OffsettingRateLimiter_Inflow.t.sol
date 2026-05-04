// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {OffsettingRateLimiterTestBase} from "src/test/libraries/OffsettingRateLimiter/OffsettingRateLimiterTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/interfaces/IOffsettingRateLimiter.sol";

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

    function test_inflow_unconfiguredEid_zeroAmount_doesNotRevert() external {
        harness.inflow(EID_A, 0);

        _assertOutState(EID_A, 0, 0, 0, uint48(block.timestamp), "out cp");
        _assertInState(EID_A, 0, 0, 0, uint48(block.timestamp), "in cp");
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
            uint48(block.timestamp),
            "boundary"
        );
        _assertReceivable(EID_A, DEFAULT_LIMIT, 0, "no capacity left");
    }

    // ========== ZERO AMOUNT ========== //

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
            uint48(block.timestamp),
            "out cp"
        );
        _assertInState(
            EID_A,
            expectedIn,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(block.timestamp),
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
            uint48(block.timestamp),
            "in debited"
        );
        _assertOutState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(block.timestamp),
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
        assertEq(inLu, uint48(block.timestamp), "in.lastUpdated refreshed");

        (uint256 outInFlight, , , uint48 outLu) = harness.outRateLimits(EID_A);
        assertEq(outInFlight, expectedOutDecayed - amount, "out.inFlight = decayedOut - amount");
        assertEq(outLu, uint48(block.timestamp), "out.lastUpdated refreshed");
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
            uint48(block.timestamp),
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
            uint48(block.timestamp),
            "counterpart wiped"
        );
        _assertInState(
            EID_A,
            a,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(block.timestamp),
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
            uint48(block.timestamp),
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
}
