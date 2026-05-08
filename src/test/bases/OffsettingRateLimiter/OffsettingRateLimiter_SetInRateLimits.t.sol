// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {OffsettingRateLimiterTestBase} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

/// @dev Tests for `_setInRateLimits` (exposed via the harness as
///      `setInRateLimits`). Mirrors `OffsettingRateLimiter_SetOutRateLimits.t.sol`,
///      with the inbound and outbound roles swapped.
contract OffsettingRateLimiterTests_SetInRateLimits is OffsettingRateLimiterTestBase {
    // ========== SINGLE-ELEMENT CONFIG ========== //

    function test_setInRateLimits_singleEntry_storesAllFields() external {
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        _assertInState(EID_A, 0, DEFAULT_LIMIT, DEFAULT_WINDOW, uint48(block.timestamp), "single");
        _assertOutState(EID_A, 0, 0, 0, uint48(block.timestamp), "out: lastUpdated refreshed");
    }

    function test_setInRateLimits_singleEntry_preservesExistingInFlight() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 amount = DEFAULT_LIMIT / 3;
        harness.inflow(EID_A, amount);

        uint256 newLimit = DEFAULT_LIMIT * 2;
        uint32 newWindow = DEFAULT_WINDOW * 4;
        harness.setInRateLimits(_configs(_config(EID_A, newLimit, newWindow)));

        _assertInState(EID_A, amount, newLimit, newWindow, uint48(block.timestamp), "in");
    }

    // ========== MULTI-ELEMENT CONFIG ========== //

    function test_setInRateLimits_threeEntries_appliesAll() external {
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _configs(
            _config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW),
            _config(EID_B, DEFAULT_LIMIT * 2, DEFAULT_WINDOW * 2),
            _config(EID_C, DEFAULT_LIMIT * 3, DEFAULT_WINDOW * 3)
        );

        harness.setInRateLimits(configs);

        uint48 t = uint48(block.timestamp);
        _assertInState(EID_A, 0, DEFAULT_LIMIT, DEFAULT_WINDOW, t, "A");
        _assertInState(EID_B, 0, DEFAULT_LIMIT * 2, DEFAULT_WINDOW * 2, t, "B");
        _assertInState(EID_C, 0, DEFAULT_LIMIT * 3, DEFAULT_WINDOW * 3, t, "C");
    }

    // ========== EMPTY ========== //

    function test_setInRateLimits_emptyArray_emitsAndDoesNothing() external {
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _emptyConfigs();

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.InRateLimitsSet(configs);

        harness.setInRateLimits(configs);

        _assertInState(EID_A, 0, 0, 0, 0, "empty does nothing");
    }

    // ========== DUPLICATE EID ========== //

    function test_setInRateLimits_duplicateEid_lastEntryWins() external {
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _configs(
            _config(EID_A, SMALL_LIMIT, SMALL_WINDOW),
            _config(EID_A, SMALL_LIMIT * 2, SMALL_WINDOW / 2),
            _config(EID_A, SMALL_LIMIT * 3, SMALL_WINDOW / 4)
        );

        harness.setInRateLimits(configs);

        _assertInState(
            EID_A,
            0,
            SMALL_LIMIT * 3,
            SMALL_WINDOW / 4,
            uint48(block.timestamp),
            "duplicate, last wins"
        );
    }

    function test_setInRateLimits_duplicateEid_inFlightSurvivesIntermediate() external {
        _setupBoth(EID_A, SMALL_LIMIT, SMALL_WINDOW, 0);
        harness.inflow(EID_A, SMALL_LIMIT / 2);

        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _configs(
            _config(EID_A, SMALL_LIMIT * 2, SMALL_WINDOW * 2),
            _config(EID_A, SMALL_LIMIT * 4, SMALL_WINDOW / 2),
            _config(EID_A, SMALL_LIMIT * 8, SMALL_WINDOW / 4)
        );
        harness.setInRateLimits(configs);

        _assertInState(
            EID_A,
            SMALL_LIMIT / 2,
            SMALL_LIMIT * 8,
            SMALL_WINDOW / 4,
            uint48(block.timestamp),
            "duplicate same block: inFlight preserved"
        );
    }

    // ========== IDEMPOTENCE WITHIN A BLOCK ========== //

    function test_setInRateLimits_multipleCallsSameBlock_idempotentOnInFlight() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        uint256 amount = DEFAULT_LIMIT / 4;
        harness.inflow(EID_A, amount);

        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        (uint256 inFlight, , , ) = harness.inRateLimits(EID_A);
        assertEq(inFlight, amount, "idempotent at elapsed == 0");
    }

    // ========== CHECKPOINT AT PREVIOUS RATE ========== //

    function test_setInRateLimits_checkpointsInFlightAtPreviousDecayRate() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.inflow(EID_A, DEFAULT_LIMIT);

        skip(DEFAULT_WINDOW / 2);

        uint256 newLimit = DEFAULT_LIMIT * 7;
        uint32 newWindow = DEFAULT_WINDOW / 3;
        harness.setInRateLimits(_configs(_config(EID_A, newLimit, newWindow)));

        uint256 expected = _expectedDecayedInFlight(
            DEFAULT_LIMIT,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            DEFAULT_WINDOW / 2
        );
        _assertInState(
            EID_A,
            expected,
            newLimit,
            newWindow,
            uint48(block.timestamp),
            "checkpointed at previous rate"
        );
    }

    // ========== COUNTERPART CHECKPOINT ========== //

    function test_setInRateLimits_checkpointsCounterpartButPreservesItsConfig() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT / 2);

        skip(DEFAULT_WINDOW / 4);

        uint256 expectedDecayedOut = _expectedDecayedInFlight(
            DEFAULT_LIMIT / 2,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            DEFAULT_WINDOW / 4
        );

        uint256 newInLimit = DEFAULT_LIMIT * 5;
        uint32 newInWindow = DEFAULT_WINDOW / 2;
        harness.setInRateLimits(_configs(_config(EID_A, newInLimit, newInWindow)));

        _assertInState(EID_A, 0, newInLimit, newInWindow, uint48(block.timestamp), "in");
        _assertOutState(
            EID_A,
            expectedDecayedOut,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(block.timestamp),
            "out checkpointed only"
        );
    }

    // ========== LIMIT REDUCTION BELOW INFLIGHT ========== //

    function test_setInRateLimits_reduceLimitBelowInFlight_doesNotRevert() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.inflow(EID_A, DEFAULT_LIMIT);

        uint256 newLimit = DEFAULT_LIMIT / 4;
        harness.setInRateLimits(_configs(_config(EID_A, newLimit, DEFAULT_WINDOW)));

        _assertInState(
            EID_A,
            DEFAULT_LIMIT,
            newLimit,
            DEFAULT_WINDOW,
            uint48(block.timestamp),
            "reduced limit"
        );
        _assertReceivable(EID_A, DEFAULT_LIMIT, 0, "available zero until decay catches up");
    }

    // ========== LIMIT INCREASE ACCELERATES DECAY ========== //

    function test_setInRateLimits_increaseLimit_acceleratesDecayOfPreExistingInFlight() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.inflow(EID_A, DEFAULT_LIMIT);

        skip(DEFAULT_WINDOW / 2);

        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT * 10, DEFAULT_WINDOW)));

        skip(DEFAULT_WINDOW / 2);

        _assertReceivable(
            EID_A,
            0,
            DEFAULT_LIMIT * 10,
            "post-update half-window decay wipes inFlight"
        );
    }

    // ========== WINDOW INCREASE SLOWS DECAY ========== //

    function test_setInRateLimits_increaseWindow_slowsDecayOfPreExistingInFlight() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.inflow(EID_A, DEFAULT_LIMIT);

        skip(DEFAULT_WINDOW / 2);

        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW * 2)));

        uint256 storedInFlight = DEFAULT_LIMIT / 2;
        _assertInState(
            EID_A,
            storedInFlight,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW * 2,
            uint48(block.timestamp),
            "stored after checkpoint"
        );

        skip(DEFAULT_WINDOW / 2);

        uint256 expectedAfter = _expectedDecayedInFlight(
            storedInFlight,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW * 2,
            DEFAULT_WINDOW / 2
        );
        _assertReceivable(EID_A, expectedAfter, DEFAULT_LIMIT - expectedAfter, "slower decay");
        assertEq(expectedAfter, DEFAULT_LIMIT / 4, "expected = LIMIT / 4");
    }

    // ========== LIMIT == 0 PAUSES THE DIRECTION ========== //

    function test_setInRateLimits_zeroLimit_revertsAnyNonZeroInflow() external {
        harness.setInRateLimits(_configs(_config(EID_A, 0, DEFAULT_WINDOW)));

        vm.expectRevert(
            abi.encodeWithSelector(IOffsettingRateLimiter.RateLimitExceeded.selector, 1, 0)
        );
        harness.inflow(EID_A, 1);
    }

    // ========== WINDOW == 0 ========== //

    function test_setInRateLimits_zeroWindow_receivableReturnsZeroAndFullLimit() external {
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, 0)));

        harness.inflow(EID_A, DEFAULT_LIMIT / 4);

        _assertReceivable(EID_A, 0, DEFAULT_LIMIT, "zero window collapses decay");
    }

    // ========== EVENTS ========== //

    function test_setInRateLimits_emitsEventWithExactArray() external {
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _configs(
            _config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW),
            _config(EID_B, DEFAULT_LIMIT * 2, DEFAULT_WINDOW * 2)
        );

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.InRateLimitsSet(configs);

        harness.setInRateLimits(configs);
    }

    // ========== INDEPENDENCE FROM OUTBOUND CONFIG ========== //

    function test_setInRateLimits_doesNotChangeOutboundLimitOrWindow() external {
        harness.setOutRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT * 7, DEFAULT_WINDOW * 11)));

        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        _assertOutState(
            EID_A,
            0,
            DEFAULT_LIMIT * 7,
            DEFAULT_WINDOW * 11,
            uint48(block.timestamp),
            "out untouched"
        );
    }

    // ========== INDEPENDENCE ACROSS EIDS ========== //

    function test_setInRateLimits_doesNotAffectOtherEids() external {
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        _assertOutState(EID_B, 0, 0, 0, 0, "other eid out");
        _assertInState(EID_B, 0, 0, 0, 0, "other eid in");
    }

    // ========== TIMESTAMP PAST UINT48 ========== //

    /// @notice Locks in cast-truncation behaviour at `block.timestamp ==
    ///         type(uint48).max + 1`. The cast `uint48(block.timestamp)`
    ///         truncates to zero, so any subsequent read sees a huge `elapsed`
    ///         and falls into the early-return path. Flagged in the summary.
    function test_setInRateLimits_writesAtTimestampPastUint48_truncates() external {
        vm.warp(UINT48_MAX + 1);
        harness.setInRateLimits(_configs(_config(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW)));

        (, , , uint48 lastUpdated) = harness.inRateLimits(EID_A);
        assertEq(lastUpdated, 0, "uint48 cast wraps to zero one past the boundary");

        // The view consequently reports `elapsed >= window` and returns full
        // capacity even though no time has passed in the calling perspective.
        _assertReceivable(EID_A, 0, DEFAULT_LIMIT, "view sees full capacity after truncation");
    }

    // ========== FUZZ ========== //

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_setInRateLimits_lastEntryWins(
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
        harness.setInRateLimits(configs);

        _assertInState(eid_, 0, limit2_, window2_, uint48(block.timestamp), "in");
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_setInRateLimits_independentEids(
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

        harness.setInRateLimits(_configs(_config(eidA_, limit_, window_)));

        assertEq(_outFingerprint(eidB_), outBefore, "eidB out four-tuple unchanged");
        assertEq(_inFingerprint(eidB_), inBefore, "eidB in four-tuple unchanged");
    }
}
