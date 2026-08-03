// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {OffsettingRateLimiterTestBase} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

/// @dev Long-running end-to-end scenarios that complement the per-function
///      unit tests by locking in interactions across multiple operations.
contract OffsettingRateLimiterTests_Scenarios is OffsettingRateLimiterTestBase {
    // ========== TABLE-DRIVEN DECAY ========== //

    /// @notice Configures one outbound rate limit, drives the in-flight to the
    ///         full limit, then walks an inline array of timestamps covering
    ///         `(0, window)`, `[window]`, and `(window, +inf)`. At each step,
    ///         asserts `(inFlight, available)` from the view function matches
    ///         the contract's integer-arithmetic expectation.
    function test_scenario_tableDrivenDecay() external {
        uint256 limit = DEFAULT_LIMIT;
        uint32 window = DEFAULT_WINDOW;

        harness.setOutRateLimits(_configs(_config(EID_A, limit, window)));
        uint48 t0 = uint48(vm.getBlockTimestamp());
        harness.outflow(EID_A, limit);

        // Inline timestamp table covering the three regions.
        uint256[14] memory elapseds = [
            uint256(0),
            1,
            10,
            100,
            900,
            1_799,
            1_800,
            1_801,
            3_500,
            uint256(window) - 1,
            uint256(window),
            uint256(window) + 1,
            uint256(window) * 2,
            uint256(window) * 100
        ];

        for (uint256 i = 0; i < elapseds.length; i++) {
            uint256 elapsed = elapseds[i];
            vm.warp(uint256(t0) + elapsed);

            (uint256 expectedInFlight, uint256 expectedAvailable) = _expectedCurrentState(
                limit,
                limit,
                window,
                elapsed
            );
            (uint256 actualInFlight, uint256 actualAvailable) = harness.sendable(EID_A);

            assertEq(actualInFlight, expectedInFlight, _withElapsedLabel("inFlight", elapsed));
            assertEq(actualAvailable, expectedAvailable, _withElapsedLabel("available", elapsed));
        }
    }

    function _withElapsedLabel(
        string memory field_,
        uint256 elapsed_
    ) private pure returns (string memory) {
        return string.concat(field_, " mismatch at elapsed=", vm.toString(elapsed_));
    }

    // ========== MULTI-STEP LIFECYCLE ========== //

    /// @notice Walks a single eid through: initial config, outflow, partial
    ///         decay, simultaneous limit-and-window change, continued decay
    ///         under the new schedule, outflow at the new limit, more decay,
    ///         reset, outflow again. After each step asserts the full
    ///         four-tuple of stored state plus the (inFlight, available) view.
    function test_scenario_multiStepLifecycle() external {
        uint256 limit1 = LIFECYCLE_LIMIT_1;
        uint32 window1 = LIFECYCLE_WINDOW_1;
        uint256 limit2 = LIFECYCLE_LIMIT_2;
        uint32 window2 = LIFECYCLE_WINDOW_2;

        // Step 1: initial config of outbound only.
        harness.setOutRateLimits(_configs(_config(EID_A, limit1, window1)));
        uint48 t0 = uint48(vm.getBlockTimestamp());
        _assertOutState(EID_A, 0, limit1, window1, t0, "step 1: initial config");
        _assertSendable(EID_A, 0, limit1, "step 1: full capacity");

        // Step 2: outflow at full limit.
        harness.outflow(EID_A, limit1);
        _assertOutState(EID_A, limit1, limit1, window1, t0, "step 2: full outflow");
        _assertSendable(EID_A, limit1, 0, "step 2: zero capacity");

        // Step 3: warp halfway through window1, partial decay.
        vm.warp(uint256(t0) + window1 / 2);
        uint256 expectedDecayed1 = _expectedDecayedInFlight(limit1, limit1, window1, window1 / 2);
        // Stored value is unchanged (no mutating call has happened yet).
        _assertOutState(EID_A, limit1, limit1, window1, t0, "step 3: stored unchanged");
        _assertSendable(EID_A, expectedDecayed1, limit1 - expectedDecayed1, "step 3: half-decay");

        // Step 4: simultaneous limit-and-window change.
        // The setter checkpoints under the *previous* schedule first, then
        // writes the new (limit, window).
        harness.setOutRateLimits(_configs(_config(EID_A, limit2, window2)));
        uint48 t1 = uint48(vm.getBlockTimestamp());
        _assertOutState(EID_A, expectedDecayed1, limit2, window2, t1, "step 4: config switch");
        _assertSendable(
            EID_A,
            expectedDecayed1,
            limit2 - expectedDecayed1,
            "step 4: bigger headroom"
        );

        // Step 5: continued decay under the new schedule.
        uint64 step5Elapsed = uint64(window2 / 2);
        vm.warp(uint256(t1) + step5Elapsed);
        uint256 expectedDecayed2 = _expectedDecayedInFlight(
            expectedDecayed1,
            limit2,
            window2,
            step5Elapsed
        );
        _assertOutState(EID_A, expectedDecayed1, limit2, window2, t1, "step 5: stored unchanged");
        _assertSendable(
            EID_A,
            expectedDecayed2,
            limit2 - expectedDecayed2,
            "step 5: post-second decay"
        );

        // Step 6: outflow that fits the post-second-decay headroom.
        uint256 step6Amount = limit2 - expectedDecayed2;
        harness.outflow(EID_A, step6Amount);
        uint48 t2 = uint48(vm.getBlockTimestamp());
        _assertOutState(
            EID_A,
            expectedDecayed2 + step6Amount,
            limit2,
            window2,
            t2,
            "step 6: outflow at new limit"
        );
        _assertSendable(EID_A, limit2, 0, "step 6: full again");

        // Step 7: more decay.
        uint64 step7Elapsed = uint64(window2 / 4);
        vm.warp(uint256(t2) + step7Elapsed);
        uint256 expectedDecayed3 = _expectedDecayedInFlight(limit2, limit2, window2, step7Elapsed);
        _assertSendable(EID_A, expectedDecayed3, limit2 - expectedDecayed3, "step 7: more decay");

        // Step 8: reset.
        harness.clearOutboundInFlight(_eids(EID_A));
        uint48 t3 = uint48(vm.getBlockTimestamp());
        _assertOutState(EID_A, 0, limit2, window2, t3, "step 8: cleared");
        _assertSendable(EID_A, 0, limit2, "step 8: full capacity post-reset");

        // Step 9: outflow again at the new limit.
        harness.outflow(EID_A, limit2);
        _assertOutState(EID_A, limit2, limit2, window2, t3, "step 9: outflow post-reset");
        _assertSendable(EID_A, limit2, 0, "step 9: zero capacity again");
    }

    // ========== SETTER PRESERVES IN-FLIGHT ACROSS CONFIG CHANGE ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_scenario_setOutRateLimitsPreservesInFlightAcrossChange(
        uint256 limitOld_,
        uint32 windowOld_,
        uint256 amount_,
        uint256 limitNew_,
        uint32 windowNew_
    ) external {
        limitOld_ = bound(limitOld_, 1, FUZZ_LIMIT_CEIL);
        windowOld_ = uint32(bound(uint256(windowOld_), 1, MAX_WINDOW));
        amount_ = bound(amount_, 0, limitOld_);
        limitNew_ = bound(limitNew_, 0, FUZZ_LIMIT_CEIL);
        windowNew_ = uint32(bound(uint256(windowNew_), 0, MAX_WINDOW));

        harness.setOutRateLimits(_configs(_config(EID_A, limitOld_, windowOld_)));
        harness.outflow(EID_A, amount_);

        // Configure under the new schedule in the same block (no decay between
        // the outflow and the setter call).
        harness.setOutRateLimits(_configs(_config(EID_A, limitNew_, windowNew_)));

        (uint256 inFlightAfter, , , ) = harness.outRateLimits(EID_A);
        assertEq(inFlightAfter, amount_, "stored inFlight preserved across config change");
    }

    // ========== SETTER PRESERVES COUNTERPART (LIMIT, WINDOW) ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_scenario_setRateLimitsPreservesCounterpartLimitWindow(
        uint256 outLimit_,
        uint32 outWindow_,
        uint256 inLimit_,
        uint32 inWindow_
    ) external {
        outLimit_ = bound(outLimit_, 0, FUZZ_LIMIT_CEIL);
        outWindow_ = uint32(bound(uint256(outWindow_), 0, MAX_WINDOW));
        inLimit_ = bound(inLimit_, 0, FUZZ_LIMIT_CEIL);
        inWindow_ = uint32(bound(uint256(inWindow_), 0, MAX_WINDOW));

        // Set the inbound side first, then the outbound side. The outbound
        // setter must not modify the inbound (limit, window).
        harness.setInRateLimits(_configs(_config(EID_A, inLimit_, inWindow_)));
        harness.setOutRateLimits(_configs(_config(EID_A, outLimit_, outWindow_)));

        (, uint256 inLimitAfter, uint32 inWindowAfter, ) = harness.inRateLimits(EID_A);
        assertEq(inLimitAfter, inLimit_, "in.limit preserved");
        assertEq(inWindowAfter, inWindow_, "in.window preserved");

        // And vice versa: a subsequent inbound setter must not modify the
        // outbound (limit, window).
        harness.setInRateLimits(_configs(_config(EID_A, inLimit_, inWindow_)));
        (, uint256 outLimitAfter, uint32 outWindowAfter, ) = harness.outRateLimits(EID_A);
        assertEq(outLimitAfter, outLimit_, "out.limit preserved");
        assertEq(outWindowAfter, outWindow_, "out.window preserved");
    }

    // ========== OUTFLOW THEN INFLOW: PARTIAL OFFSET ========== //

    /// @dev No elapsed time, so `decayedOut == outAmount_`. Bounding
    ///      `inAmount_ < outAmount_` forces the partial-offset branch
    ///      without re-deriving the contract's decay arithmetic.
    /// forge-config: default.fuzz.runs = 512
    function testFuzz_scenario_outflowThenInflowPartialOffset(
        uint256 outAmount_,
        uint256 inAmount_
    ) external {
        uint256 limit = DEFAULT_LIMIT;
        uint32 window = DEFAULT_WINDOW;
        outAmount_ = bound(outAmount_, 1, limit);
        inAmount_ = bound(inAmount_, 0, outAmount_ - 1);

        _setupBoth(EID_A, limit, window, 0);
        harness.outflow(EID_A, outAmount_);
        harness.inflow(EID_A, inAmount_);

        (uint256 outInFlight, , , ) = harness.outRateLimits(EID_A);
        (uint256 inInFlight, , , ) = harness.inRateLimits(EID_A);
        assertEq(outInFlight, outAmount_ - inAmount_, "out partially offset");
        assertEq(inInFlight, inAmount_, "in matches simulation");
    }

    // ========== OUTFLOW THEN INFLOW: FULL OFFSET ========== //

    /// @dev `inAmount_ >= outAmount_ >= decayedOut`, so the inflow always
    ///      clears `out.inFlight` regardless of how decay during `elapsed_`
    ///      reduced it. Avoids mirroring the contract's decay formula.
    /// forge-config: default.fuzz.runs = 512
    function testFuzz_scenario_outflowThenInflowFullOffset(
        uint256 outAmount_,
        uint256 inAmount_,
        uint64 elapsed_
    ) external {
        uint256 limit = DEFAULT_LIMIT;
        uint32 window = DEFAULT_WINDOW;
        outAmount_ = bound(outAmount_, 0, limit);
        inAmount_ = bound(inAmount_, outAmount_, limit);
        elapsed_ = uint64(bound(uint256(elapsed_), 0, uint256(window) - 1));

        _setupBoth(EID_A, limit, window, 0);
        harness.outflow(EID_A, outAmount_);
        skip(elapsed_);
        harness.inflow(EID_A, inAmount_);

        (uint256 outInFlight, , , ) = harness.outRateLimits(EID_A);
        (uint256 inInFlight, , , ) = harness.inRateLimits(EID_A);
        assertEq(outInFlight, 0, "out fully offset");
        assertEq(inInFlight, inAmount_, "in matches simulation");
    }
}
