// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {OffsettingRateLimiterTestBase} from "src/test/libraries/OffsettingRateLimiter/OffsettingRateLimiterTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/interfaces/IOffsettingRateLimiter.sol";

/// @dev Fuzz tests. Bounds are chosen so that:
///      - `limit * window` does not overflow the multiplication inside
///        `_currentState`,
///      - `block.timestamp + warp` stays under `type(uint48).max` so the
///        `lastUpdated` cast does not truncate,
///      - the stored value is well-defined after each step.
contract OffsettingRateLimiterTests_Fuzz is OffsettingRateLimiterTestBase {
    // Picked so `limit * window` fits in uint256 even when `limit` and `window`
    // both saturate the bound. Since `window <= type(uint32).max` (the storage
    // size) the bound on `limit` only needs to keep the product in range; we
    // pick a generous `2**192` ceiling.
    uint256 internal constant FUZZ_LIMIT_CEIL = 2 ** 192;
    uint32 internal constant MIN_WINDOW = 1;
    uint32 internal constant MAX_WINDOW = type(uint32).max;

    // ========== OUTFLOW WITHIN AVAILABLE NEVER REVERTS ========== //

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

        // No prior outflow, so available equals limit (decay irrelevant).
        amount_ = bound(amount_, 0, limit_);

        harness.outflow(EID_A, amount_);

        (uint256 outInFlight, , , uint48 outLu) = harness.outRateLimits(EID_A);
        // Pre-existing inFlight was zero, so post = 0 + amount_ = amount_.
        assertEq(outInFlight, amount_, "post-state matches simulation");
        assertEq(outLu, uint48(block.timestamp), "lastUpdated refreshed");
    }

    // ========== OUTFLOW ABOVE AVAILABLE ALWAYS REVERTS ========== //

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

        // Available is `limit_` since stored inFlight is zero.
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

    // ========== DECAY MONOTONIC IN ELAPSED ========== //

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_decay_monotonic(
        uint256 limit_,
        uint32 window_,
        uint256 inFlight_,
        uint64 t1_,
        uint64 t2_
    ) external {
        limit_ = bound(limit_, 1, FUZZ_LIMIT_CEIL);
        window_ = uint32(bound(uint256(window_), MIN_WINDOW, MAX_WINDOW));
        inFlight_ = bound(inFlight_, 0, FUZZ_LIMIT_CEIL);
        // Pick t1 <= t2 inside the window. Warp forward so `block.timestamp -
        // t1/t2` stays well-defined.
        t1_ = uint64(bound(uint256(t1_), 0, uint256(window_) - 1));
        t2_ = uint64(bound(uint256(t2_), uint256(t1_), uint256(window_) - 1));
        // Ensure block.timestamp is past `window_` so the subtraction below
        // does not underflow regardless of the (now-bounded) inputs.
        vm.warp(uint256(window_) + START_TIMESTAMP);

        uint48 t0 = uint48(block.timestamp);
        uint48 lu1 = uint48(uint256(t0) - uint256(t1_));
        uint48 lu2 = uint48(uint256(t0) - uint256(t2_));
        (uint256 inFlightAtT1, ) = harness.currentState(inFlight_, limit_, window_, lu1);
        (uint256 inFlightAtT2, ) = harness.currentState(inFlight_, limit_, window_, lu2);

        assertLe(inFlightAtT2, inFlightAtT1, "inFlight monotonic non-increasing in elapsed");
    }

    // ========== DECAY RECOVERS PAST THE WINDOW ========== //

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_decay_recoversAfterWindow(
        uint256 limit_,
        uint32 window_,
        uint256 inFlight_,
        uint64 elapsed_
    ) external {
        limit_ = bound(limit_, 0, FUZZ_LIMIT_CEIL);
        window_ = uint32(bound(uint256(window_), 0, MAX_WINDOW));
        inFlight_ = bound(inFlight_, 0, type(uint256).max);
        // Cap elapsed at uint48 max so the cast below stays in range.
        elapsed_ = uint64(bound(uint256(elapsed_), uint256(window_), UINT48_MAX / 2));

        // Warp far enough that `block.timestamp - elapsed_` does not underflow
        // and stays in uint48.
        vm.warp(UINT48_MAX);
        uint48 lastUpdated = uint48(block.timestamp - elapsed_);

        (uint256 inFlight, uint256 available) = harness.currentState(
            inFlight_,
            limit_,
            window_,
            lastUpdated
        );

        assertEq(inFlight, 0, "decayed to zero past window");
        assertEq(available, limit_, "full limit available past window");
    }

    // ========== SET RATE LIMITS - LAST ENTRY WINS ========== //

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_setRateLimits_lastEntryWins(
        uint32 eid_,
        uint256 limit1_,
        uint256 limit2_,
        uint32 window1_,
        uint32 window2_
    ) external {
        // Bounds: keep limits / windows positive and within sane ranges.
        limit1_ = bound(limit1_, 0, FUZZ_LIMIT_CEIL);
        limit2_ = bound(limit2_, 0, FUZZ_LIMIT_CEIL);
        window1_ = uint32(bound(uint256(window1_), 0, MAX_WINDOW));
        window2_ = uint32(bound(uint256(window2_), 0, MAX_WINDOW));

        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _configs(
            _config(eid_, limit1_, window1_),
            _config(eid_, limit2_, window2_)
        );
        harness.setOutRateLimits(configs);

        _assertOutState(eid_, 0, limit2_, window2_, uint48(block.timestamp), "out");
    }

    // ========== CLEAR IS IDEMPOTENT ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_clear_idempotent(uint32[] calldata eids_) external {
        // Bound array length and copy into a memory array.
        uint256 len = bound(eids_.length, 0, 8);
        uint32[] memory eids = new uint32[](len);
        for (uint256 i = 0; i < len; i++) {
            eids[i] = eids_[i];
        }

        // Configure each eid (re-configuring a duplicate is idempotent on
        // (limit, window) at the same block).
        for (uint256 i = 0; i < len; i++) {
            harness.setOutRateLimits(_configs(_config(eids[i], DEFAULT_LIMIT, DEFAULT_WINDOW)));
        }
        // Drive each one to non-zero in-flight. Use a small per-iteration
        // amount so duplicate eids do not exhaust the limit by accumulating
        // across iterations: 8 * 1 = 8 << DEFAULT_LIMIT.
        for (uint256 i = 0; i < len; i++) {
            harness.outflow(eids[i], 1);
        }

        harness.clearOutboundInFlight(eids);
        uint48 t1 = uint48(block.timestamp);
        for (uint256 i = 0; i < len; i++) {
            (uint256 inFlight, , , uint48 lu) = harness.outRateLimits(eids[i]);
            assertEq(inFlight, 0, "first clear: inFlight zero");
            assertEq(lu, t1, "first clear: lastUpdated current");
        }

        // Second clear at the same block: identical result.
        harness.clearOutboundInFlight(eids);
        for (uint256 i = 0; i < len; i++) {
            (uint256 inFlight, , , uint48 lu) = harness.outRateLimits(eids[i]);
            assertEq(inFlight, 0, "second clear: inFlight zero");
            assertEq(lu, t1, "second clear: lastUpdated unchanged at same block");
        }
    }

    // ========== OUTFLOW THEN INFLOW SEQUENCE ========== //

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_outflow_inflow_sequence(
        uint256 outAmount_,
        uint256 inAmount_,
        uint64 elapsed_
    ) external {
        uint256 limit = DEFAULT_LIMIT;
        uint32 window = DEFAULT_WINDOW;
        outAmount_ = bound(outAmount_, 0, limit);
        inAmount_ = bound(inAmount_, 0, limit);
        elapsed_ = uint64(bound(uint256(elapsed_), 0, uint256(window) - 1));

        _setupBoth(EID_A, limit, window, 0);
        harness.outflow(EID_A, outAmount_);

        skip(elapsed_);

        // Decay calculation in the same arithmetic the contract uses.
        uint256 decay = (limit * uint256(elapsed_)) / window;
        uint256 decayedOut = outAmount_ > decay ? outAmount_ - decay : 0;

        harness.inflow(EID_A, inAmount_);

        // Final state:
        //   in.inFlight  = 0 (no prior in) + inAmount_ = inAmount_
        //   out.inFlight = subOrZero(decayedOut, inAmount_)
        uint256 expectedOut = decayedOut > inAmount_ ? decayedOut - inAmount_ : 0;

        (uint256 outInFlight, , , ) = harness.outRateLimits(EID_A);
        (uint256 inInFlight, , , ) = harness.inRateLimits(EID_A);
        assertEq(outInFlight, expectedOut, "out matches simulation");
        assertEq(inInFlight, inAmount_, "in matches simulation");
    }

    // ========== INDEPENDENCE ACROSS EIDS ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_setRateLimits_independentEids(
        uint32 eidA_,
        uint32 eidB_,
        uint256 limit_,
        uint32 window_
    ) external {
        vm.assume(eidA_ != eidB_);
        limit_ = bound(limit_, 0, FUZZ_LIMIT_CEIL);
        window_ = uint32(bound(uint256(window_), 0, MAX_WINDOW));

        bytes32 outBefore = _outFingerprint(eidB_);
        bytes32 inBefore = _inFingerprint(eidB_);

        harness.setOutRateLimits(_configs(_config(eidA_, limit_, window_)));

        assertEq(_outFingerprint(eidB_), outBefore, "eidB out four-tuple unchanged");
        assertEq(_inFingerprint(eidB_), inBefore, "eidB in four-tuple unchanged");
    }

    function _outFingerprint(uint32 eid_) private view returns (bytes32) {
        (uint256 inFlight, uint256 limit, uint32 window, uint48 lu) = harness.outRateLimits(eid_);
        return keccak256(abi.encode(inFlight, limit, window, lu));
    }

    function _inFingerprint(uint32 eid_) private view returns (bytes32) {
        (uint256 inFlight, uint256 limit, uint32 window, uint48 lu) = harness.inRateLimits(eid_);
        return keccak256(abi.encode(inFlight, limit, window, lu));
    }

    // ========== PRESERVE INFLIGHT ACROSS CONFIG CHANGE ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_setRateLimits_preservesInFlightAcrossChange(
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

    // ========== COUNTERPART (LIMIT, WINDOW) PRESERVED ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_setRateLimits_preservesCounterpartLimitWindow(
        uint256 outLimit_,
        uint32 outWindow_,
        uint256 inLimit_,
        uint32 inWindow_
    ) external {
        outLimit_ = bound(outLimit_, 0, FUZZ_LIMIT_CEIL);
        outWindow_ = uint32(bound(uint256(outWindow_), 0, MAX_WINDOW));
        inLimit_ = bound(inLimit_, 0, FUZZ_LIMIT_CEIL);
        inWindow_ = uint32(bound(uint256(inWindow_), 0, MAX_WINDOW));

        // Set in first, then out. Out's setter must not modify in's
        // (limit, window).
        harness.setInRateLimits(_configs(_config(EID_A, inLimit_, inWindow_)));
        harness.setOutRateLimits(_configs(_config(EID_A, outLimit_, outWindow_)));

        (, uint256 inLimitAfter, uint32 inWindowAfter, ) = harness.inRateLimits(EID_A);
        assertEq(inLimitAfter, inLimit_, "in.limit preserved");
        assertEq(inWindowAfter, inWindow_, "in.window preserved");

        // And vice versa: another setIn must not modify out's (limit, window).
        harness.setInRateLimits(_configs(_config(EID_A, inLimit_, inWindow_)));
        (, uint256 outLimitAfter, uint32 outWindowAfter, ) = harness.outRateLimits(EID_A);
        assertEq(outLimitAfter, outLimit_, "out.limit preserved");
        assertEq(outWindowAfter, outWindow_, "out.window preserved");
    }
}
