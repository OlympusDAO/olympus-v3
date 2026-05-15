// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {OffsettingRateLimiterTestBase} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

/// @dev Tests for `_setOutRateLimits` (exposed via the harness as
///      `setOutRateLimits`). Symmetric tests for `_setInRateLimits` live in
///      `OffsettingRateLimiter_SetInRateLimits.t.sol`.
contract OffsettingRateLimiterTests_SetOutRateLimits is OffsettingRateLimiterTestBase {
    // ========== SINGLE-ELEMENT CONFIG ========== //

    function test_setOutRateLimits_singleEntry_storesAllFields() external {
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        _assertOutState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "single"
        );
        // Inbound side: limit and window untouched, but lastUpdated is
        // refreshed by `_settle` regardless of whether inbound was configured.
        _assertInState(EID_A, 0, 0, 0, uint48(vm.getBlockTimestamp()), "in: lastUpdated refreshed");
    }

    function test_setOutRateLimits_singleEntry_preservesExistingInFlight() external {
        // Configure both, drive an inFlight, then re-configure outbound only.
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 amount = DEFAULT_LIMIT / 3;
        harness.outflow(EID_A, amount);

        // Re-configure outbound with a new limit / window. The stored inFlight
        // is checkpointed (no time has passed) and preserved.
        uint256 newLimit = DEFAULT_LIMIT * 2;
        uint32 newWindow = DEFAULT_WINDOW * 4;
        harness.setOutRateLimits(_configs(_config(EID_A, newLimit, newWindow)));

        _assertOutState(EID_A, amount, newLimit, newWindow, uint48(vm.getBlockTimestamp()), "out");
    }

    // ========== MULTI-ELEMENT CONFIG ========== //

    function test_setOutRateLimits_threeEntries_appliesAll() external {
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _configs(
            _config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW),
            _config(EID_B, DEFAULT_LIMIT * 2, DEFAULT_WINDOW * 2),
            _config(EID_C, DEFAULT_LIMIT * 3, DEFAULT_WINDOW * 3)
        );

        harness.setOutRateLimits(configs);

        uint48 t = uint48(vm.getBlockTimestamp());
        _assertOutState(EID_A, 0, DEFAULT_LIMIT, DEFAULT_WINDOW, t, "A");
        _assertOutState(EID_B, 0, DEFAULT_LIMIT * 2, DEFAULT_WINDOW * 2, t, "B");
        _assertOutState(EID_C, 0, DEFAULT_LIMIT * 3, DEFAULT_WINDOW * 3, t, "C");
    }

    // ========== EMPTY ========== //

    function test_setOutRateLimits_emptyArray_emitsAndDoesNothing() external {
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _emptyConfigs();

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.OutRateLimitsSet(configs);

        harness.setOutRateLimits(configs);

        _assertOutState(EID_A, 0, 0, 0, 0, "empty does nothing");
    }

    // ========== DUPLICATE EID ========== //

    function test_setOutRateLimits_duplicateEid_lastEntryWins() external {
        // Three entries for the same eid, applied in order. Limits and
        // windows differ between entries so the assertion can prove the last
        // entry's values are what survive.
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _configs(
            _config(EID_A, SMALL_LIMIT, SMALL_WINDOW),
            _config(EID_A, SMALL_LIMIT * 2, SMALL_WINDOW / 2),
            _config(EID_A, SMALL_LIMIT * 3, SMALL_WINDOW / 4)
        );

        harness.setOutRateLimits(configs);

        _assertOutState(
            EID_A,
            0,
            SMALL_LIMIT * 3,
            SMALL_WINDOW / 4,
            uint48(vm.getBlockTimestamp()),
            "duplicate, last wins"
        );
    }

    /// @notice With pre-existing inFlight and the duplicate-eid path, each
    ///         entry's `_settle` checkpoints the previous (limit, window) before
    ///         the next is written. Since all entries are within the same block,
    ///         no decay occurs between them, so the inFlight is preserved.
    function test_setOutRateLimits_duplicateEid_inFlightSurvivesIntermediate() external {
        _setupBoth(EID_A, SMALL_LIMIT, SMALL_WINDOW, 0);
        harness.outflow(EID_A, SMALL_LIMIT / 2);

        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _configs(
            _config(EID_A, SMALL_LIMIT * 2, SMALL_WINDOW * 2),
            _config(EID_A, SMALL_LIMIT * 4, SMALL_WINDOW / 2),
            _config(EID_A, SMALL_LIMIT * 8, SMALL_WINDOW / 4)
        );
        harness.setOutRateLimits(configs);

        _assertOutState(
            EID_A,
            SMALL_LIMIT / 2,
            SMALL_LIMIT * 8,
            SMALL_WINDOW / 4,
            uint48(vm.getBlockTimestamp()),
            "duplicate same block: inFlight preserved"
        );
    }

    // ========== IDEMPOTENCE WITHIN A BLOCK ========== //

    function test_setOutRateLimits_multipleCallsSameBlock_idempotentOnInFlight() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 amount = DEFAULT_LIMIT / 4;
        harness.outflow(EID_A, amount);

        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        (uint256 inFlight, , , ) = harness.outRateLimits(EID_A);
        assertEq(inFlight, amount, "idempotent at elapsed == 0");
    }

    // ========== CHECKPOINT AT PREVIOUS RATE ========== //

    function test_setOutRateLimits_checkpointsInFlightAtPreviousDecayRate() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT);

        // Warp halfway. Under the old (limit, window) the decayed inFlight is
        // exactly half the limit.
        skip(DEFAULT_WINDOW / 2);

        // Re-configure with arbitrary new (limit, window). The setter
        // checkpoints first, so the stored inFlight should be the decayed value
        // at the previous rate.
        uint256 newLimit = DEFAULT_LIMIT * 7;
        uint32 newWindow = DEFAULT_WINDOW / 3;
        harness.setOutRateLimits(_configs(_config(EID_A, newLimit, newWindow)));

        uint256 expected = _expectedDecayedInFlight(
            DEFAULT_LIMIT,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            DEFAULT_WINDOW / 2
        );
        _assertOutState(
            EID_A,
            expected,
            newLimit,
            newWindow,
            uint48(vm.getBlockTimestamp()),
            "checkpointed at previous rate"
        );
    }

    // ========== COUNTERPART CHECKPOINT ========== //

    function test_setOutRateLimits_checkpointsCounterpartButPreservesItsConfig() external {
        // Configure both, drive inbound inFlight, then re-configure outbound.
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.inflow(EID_A, DEFAULT_LIMIT / 2);

        skip(DEFAULT_WINDOW / 4);

        uint256 expectedDecayedIn = _expectedDecayedInFlight(
            DEFAULT_LIMIT / 2,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            DEFAULT_WINDOW / 4
        );

        uint256 newOutLimit = DEFAULT_LIMIT * 5;
        uint32 newOutWindow = DEFAULT_WINDOW / 2;
        harness.setOutRateLimits(_configs(_config(EID_A, newOutLimit, newOutWindow)));

        // Outbound got the new (limit, window).
        _assertOutState(EID_A, 0, newOutLimit, newOutWindow, uint48(vm.getBlockTimestamp()), "out");

        // Inbound config (limit, window) is preserved; inFlight is decayed and
        // lastUpdated is refreshed.
        _assertInState(
            EID_A,
            expectedDecayedIn,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "in checkpointed only"
        );
    }

    // ========== LIMIT REDUCTION BELOW INFLIGHT ========== //

    function test_setOutRateLimits_reduceLimitBelowInFlight_doesNotRevert() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT);

        uint256 newLimit = DEFAULT_LIMIT / 4;
        harness.setOutRateLimits(_configs(_config(EID_A, newLimit, DEFAULT_WINDOW)));

        _assertOutState(
            EID_A,
            DEFAULT_LIMIT,
            newLimit,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "reduced limit"
        );
        // sendable: stored inFlight > new limit -> available is zero.
        _assertSendable(EID_A, DEFAULT_LIMIT, 0, "available zero until decay catches up");
    }

    // ========== LIMIT INCREASE ACCELERATES DECAY ========== //

    /// @notice The decay rate is `limit / window`, so increasing the limit at a
    ///         fixed window accelerates the decay of any pre-existing in-flight.
    function test_setOutRateLimits_increaseLimit_acceleratesDecayOfPreExistingInFlight() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT);

        // Warp halfway. Decayed inFlight = DEFAULT_LIMIT / 2 under (LIMIT, WINDOW).
        skip(DEFAULT_WINDOW / 2);

        // Set a new limit equal to 10x the old limit, same window. Under the
        // new schedule the decay rate is 10 * (LIMIT/WINDOW). After another
        // half-window the second-half decay is 5 * LIMIT, which more than
        // wipes the remaining LIMIT / 2.
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT * 10, DEFAULT_WINDOW)));

        skip(DEFAULT_WINDOW / 2);

        _assertSendable(
            EID_A,
            0,
            DEFAULT_LIMIT * 10,
            "post-update half-window decay wipes inFlight"
        );
    }

    // ========== WINDOW INCREASE SLOWS DECAY ========== //

    function test_setOutRateLimits_increaseWindow_slowsDecayOfPreExistingInFlight() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT);

        skip(DEFAULT_WINDOW / 2);
        // Stored inFlight after the checkpoint will be DEFAULT_LIMIT / 2.

        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW * 2)));

        // Stored value at this moment.
        uint256 storedInFlight = DEFAULT_LIMIT / 2;
        _assertOutState(
            EID_A,
            storedInFlight,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW * 2,
            uint48(vm.getBlockTimestamp()),
            "stored after checkpoint"
        );

        // Warp another half-window of the *original* window length. Under the
        // new (LIMIT, 2 * WINDOW), the decay is (LIMIT * WINDOW/2) / (2 *
        // WINDOW) = LIMIT / 4. So the new decayed inFlight should be LIMIT / 2 -
        // LIMIT / 4 = LIMIT / 4.
        skip(DEFAULT_WINDOW / 2);

        uint256 expectedAfter = _expectedDecayedInFlight(
            storedInFlight,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW * 2,
            DEFAULT_WINDOW / 2
        );
        _assertSendable(EID_A, expectedAfter, DEFAULT_LIMIT - expectedAfter, "slower decay");
        assertEq(expectedAfter, DEFAULT_LIMIT / 4, "expected = LIMIT / 4");
    }

    // ========== LIMIT == 0 PAUSES THE DIRECTION ========== //

    function test_setOutRateLimits_zeroLimit_revertsAnyNonZeroOutflow() external {
        harness.setOutRateLimits(_configs(_config(EID_A, 0, DEFAULT_WINDOW)));

        vm.expectRevert(
            abi.encodeWithSelector(IOffsettingRateLimiter.RateLimitExceeded.selector, 1, 0)
        );
        harness.outflow(EID_A, 1);
    }

    // ========== WINDOW == 0 ========== //

    function test_setOutRateLimits_zeroWindow_sendableReturnsZeroAndFullLimit() external {
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, 0)));

        // Force a non-zero stored inFlight even though the window is zero. The
        // first outflow must succeed because available = DEFAULT_LIMIT.
        harness.outflow(EID_A, DEFAULT_LIMIT / 4);

        // sendable still reports full capacity because elapsed >= window (= 0).
        _assertSendable(EID_A, 0, DEFAULT_LIMIT, "zero window collapses decay");
    }

    // ========== EVENTS ========== //

    function test_setOutRateLimits_emitsEventWithExactArray() external {
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _configs(
            _config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW),
            _config(EID_B, DEFAULT_LIMIT * 2, DEFAULT_WINDOW * 2)
        );

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.OutRateLimitsSet(configs);

        harness.setOutRateLimits(configs);
    }

    // ========== INDEPENDENCE FROM INBOUND CONFIG ========== //

    function test_setOutRateLimits_doesNotChangeInboundLimitOrWindow() external {
        // Inbound has its own (limit, window) preset.
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT * 7, DEFAULT_WINDOW * 11)));

        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        _assertInState(
            EID_A,
            0,
            DEFAULT_LIMIT * 7,
            DEFAULT_WINDOW * 11,
            uint48(vm.getBlockTimestamp()),
            "in untouched"
        );
    }

    // ========== INDEPENDENCE ACROSS EIDS ========== //

    function test_setOutRateLimits_doesNotAffectOtherEids() external {
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        // EID_B remains zero across all four fields.
        _assertOutState(EID_B, 0, 0, 0, 0, "other eid out");
        _assertInState(EID_B, 0, 0, 0, 0, "other eid in");
    }

    // ========== TIMESTAMP PAST UINT48 ========== //

    /// @notice Locks in cast-truncation behaviour at `vm.getBlockTimestamp() ==
    ///         type(uint48).max + 1`. The cast `uint48(vm.getBlockTimestamp())`
    ///         truncates to zero, so any subsequent read sees a huge `elapsed`
    ///         and falls into the early-return path. Flagged in the summary.
    function test_setOutRateLimits_writesAtTimestampPastUint48_truncates() external {
        vm.warp(UINT48_MAX + 1);
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        (, , , uint48 lastUpdated) = harness.outRateLimits(EID_A);
        assertEq(lastUpdated, 0, "uint48 cast wraps to zero one past the boundary");

        // The view consequently reports `elapsed >= window` and returns full
        // capacity even though no time has passed in the calling perspective.
        _assertSendable(EID_A, 0, DEFAULT_LIMIT, "view sees full capacity after truncation");
    }

    // ========== FUZZ ========== //

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_setOutRateLimits_lastEntryWins(
        uint32 eid_,
        uint256 limit1_,
        uint256 limit2_,
        uint32 window1_,
        uint32 window2_
    ) external {
        // Bounds: keep limits / windows positive and within sane ranges
        limit1_ = bound(limit1_, 0, FUZZ_LIMIT_CEIL);
        limit2_ = bound(limit2_, 0, FUZZ_LIMIT_CEIL);
        window1_ = uint32(bound(uint256(window1_), 0, MAX_WINDOW));
        window2_ = uint32(bound(uint256(window2_), 0, MAX_WINDOW));

        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _configs(
            _config(eid_, limit1_, window1_),
            _config(eid_, limit2_, window2_)
        );
        harness.setOutRateLimits(configs);

        _assertOutState(eid_, 0, limit2_, window2_, uint48(vm.getBlockTimestamp()), "out");
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_setOutRateLimits_independentEids(
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
}
