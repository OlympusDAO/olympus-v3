// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {OffsettingRateLimiterTestBase} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

/// @dev Tests for `_clearOutboundInFlight` and `_clearInboundInFlight`,
///      exposed via the harness as `clearOutboundInFlight` and
///      `clearInboundInFlight`.
contract OffsettingRateLimiterTests_ClearInFlight is OffsettingRateLimiterTestBase {
    // ========== _clearOutboundInFlight ========== //

    function test_clearOutboundInFlight_singleEid_resetsInFlightAndRefreshesLastUpdated() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT / 2);

        skip(123);

        harness.clearOutboundInFlight(_eids(EID_A));

        // (limit, window) preserved; inFlight cleared; lastUpdated refreshed.
        _assertOutState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "after clear"
        );
    }

    function test_clearOutboundInFlight_multipleEids_resetsAll() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        _setupBoth(EID_B, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        _setupBoth(EID_C, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        harness.outflow(EID_A, DEFAULT_LIMIT);
        harness.outflow(EID_B, DEFAULT_LIMIT);
        harness.outflow(EID_C, DEFAULT_LIMIT);

        harness.clearOutboundInFlight(_eids(EID_A, EID_B, EID_C));

        uint48 t = uint48(vm.getBlockTimestamp());
        _assertOutState(EID_A, 0, DEFAULT_LIMIT, DEFAULT_WINDOW, t, "A");
        _assertOutState(EID_B, 0, DEFAULT_LIMIT, DEFAULT_WINDOW, t, "B");
        _assertOutState(EID_C, 0, DEFAULT_LIMIT, DEFAULT_WINDOW, t, "C");
    }

    function test_clearOutboundInFlight_emptyArray_emitsAndDoesNothing() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT / 2);

        uint32[] memory eids = _emptyEids();

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.OutboundInFlightCleared(eids);

        harness.clearOutboundInFlight(eids);

        // EID_A unchanged.
        _assertOutState(
            EID_A,
            DEFAULT_LIMIT / 2,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "untouched"
        );
    }

    function test_clearOutboundInFlight_duplicateEid_isIdempotent() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT);

        harness.clearOutboundInFlight(_eids(EID_A, EID_A, EID_A));

        _assertOutState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "duplicate eids"
        );
    }

    function test_clearOutboundInFlight_selectiveReset_doesNotTouchOmittedEids() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        _setupBoth(EID_B, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        _setupBoth(EID_C, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        harness.outflow(EID_A, DEFAULT_LIMIT);
        harness.outflow(EID_B, DEFAULT_LIMIT);
        harness.outflow(EID_C, DEFAULT_LIMIT);

        // Snapshot EID_B before, since it should remain unchanged.
        (uint256 inFlightB, uint256 limitB, uint32 windowB, uint48 luB) = harness.outRateLimits(
            EID_B
        );

        harness.clearOutboundInFlight(_eids(EID_A, EID_C));

        _assertOutState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "A cleared"
        );
        _assertOutState(
            EID_C,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "C cleared"
        );
        _assertOutState(EID_B, inFlightB, limitB, windowB, luB, "B untouched");
    }

    function test_clearOutboundInFlight_doesNotAffectInboundDirection() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT / 2);
        harness.inflow(EID_A, DEFAULT_LIMIT / 4);

        // The above two flows already cross-credited the counterparts. Take a
        // snapshot of the inbound side now to verify it does not change.
        (uint256 inFlightIn, uint256 limitIn, uint32 windowIn, uint48 luIn) = harness.inRateLimits(
            EID_A
        );

        harness.clearOutboundInFlight(_eids(EID_A));

        (
            uint256 inFlightInAfter,
            uint256 limitInAfter,
            uint32 windowInAfter,
            uint48 luInAfter
        ) = harness.inRateLimits(EID_A);

        assertEq(inFlightInAfter, inFlightIn, "in.inFlight unchanged");
        assertEq(limitInAfter, limitIn, "in.limit unchanged");
        assertEq(windowInAfter, windowIn, "in.window unchanged");
        assertEq(luInAfter, luIn, "in.lastUpdated unchanged");
    }

    function test_clearOutboundInFlight_emitsEventWithExactArray() external {
        uint32[] memory eids = _eids(EID_A, EID_B);

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.OutboundInFlightCleared(eids);

        harness.clearOutboundInFlight(eids);
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_clearOutboundInFlight_idempotent(uint32[] calldata eids_) external {
        // Bound the array length and copy into a memory array.
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
        // Drive each one to a non-zero in-flight. Use a small per-iteration
        // amount so duplicate eids do not exhaust the limit by accumulating
        // across iterations: 8 * 1 = 8 << DEFAULT_LIMIT.
        for (uint256 i = 0; i < len; i++) {
            harness.outflow(eids[i], 1);
        }

        harness.clearOutboundInFlight(eids);
        uint48 t1 = uint48(vm.getBlockTimestamp());
        for (uint256 i = 0; i < len; i++) {
            (uint256 inFlight, , , uint48 lu) = harness.outRateLimits(eids[i]);
            assertEq(inFlight, 0, "first clear: inFlight zero");
            assertEq(lu, t1, "first clear: lastUpdated current");
        }

        // The second clear at the same block produces an identical result.
        harness.clearOutboundInFlight(eids);
        for (uint256 i = 0; i < len; i++) {
            (uint256 inFlight, , , uint48 lu) = harness.outRateLimits(eids[i]);
            assertEq(inFlight, 0, "second clear: inFlight zero");
            assertEq(lu, t1, "second clear: lastUpdated unchanged at same block");
        }
    }

    // ========== _clearInboundInFlight ========== //

    function test_clearInboundInFlight_singleEid_resetsInFlightAndRefreshesLastUpdated() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.inflow(EID_A, DEFAULT_LIMIT / 2);

        skip(123);

        harness.clearInboundInFlight(_eids(EID_A));

        _assertInState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "after clear"
        );
    }

    function test_clearInboundInFlight_multipleEids_resetsAll() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        _setupBoth(EID_B, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        _setupBoth(EID_C, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        harness.inflow(EID_A, DEFAULT_LIMIT);
        harness.inflow(EID_B, DEFAULT_LIMIT);
        harness.inflow(EID_C, DEFAULT_LIMIT);

        harness.clearInboundInFlight(_eids(EID_A, EID_B, EID_C));

        uint48 t = uint48(vm.getBlockTimestamp());
        _assertInState(EID_A, 0, DEFAULT_LIMIT, DEFAULT_WINDOW, t, "A");
        _assertInState(EID_B, 0, DEFAULT_LIMIT, DEFAULT_WINDOW, t, "B");
        _assertInState(EID_C, 0, DEFAULT_LIMIT, DEFAULT_WINDOW, t, "C");
    }

    function test_clearInboundInFlight_emptyArray_emitsAndDoesNothing() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.inflow(EID_A, DEFAULT_LIMIT / 2);

        uint32[] memory eids = _emptyEids();

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.InboundInFlightCleared(eids);

        harness.clearInboundInFlight(eids);

        _assertInState(
            EID_A,
            DEFAULT_LIMIT / 2,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "untouched"
        );
    }

    function test_clearInboundInFlight_duplicateEid_isIdempotent() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.inflow(EID_A, DEFAULT_LIMIT);

        harness.clearInboundInFlight(_eids(EID_A, EID_A, EID_A));

        _assertInState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "duplicate eids"
        );
    }

    function test_clearInboundInFlight_selectiveReset_doesNotTouchOmittedEids() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        _setupBoth(EID_B, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        _setupBoth(EID_C, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);

        harness.inflow(EID_A, DEFAULT_LIMIT);
        harness.inflow(EID_B, DEFAULT_LIMIT);
        harness.inflow(EID_C, DEFAULT_LIMIT);

        (uint256 inFlightB, uint256 limitB, uint32 windowB, uint48 luB) = harness.inRateLimits(
            EID_B
        );

        harness.clearInboundInFlight(_eids(EID_A, EID_C));

        _assertInState(
            EID_A,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "A cleared"
        );
        _assertInState(
            EID_C,
            0,
            DEFAULT_LIMIT,
            DEFAULT_WINDOW,
            uint48(vm.getBlockTimestamp()),
            "C cleared"
        );
        _assertInState(EID_B, inFlightB, limitB, windowB, luB, "B untouched");
    }

    function test_clearInboundInFlight_doesNotAffectOutboundDirection() external {
        _setupBoth(EID_A, DEFAULT_LIMIT, DEFAULT_WINDOW, 0);
        harness.outflow(EID_A, DEFAULT_LIMIT / 2);
        harness.inflow(EID_A, DEFAULT_LIMIT / 4);

        (uint256 inFlightOut, uint256 limitOut, uint32 windowOut, uint48 luOut) = harness
            .outRateLimits(EID_A);

        harness.clearInboundInFlight(_eids(EID_A));

        (
            uint256 inFlightOutAfter,
            uint256 limitOutAfter,
            uint32 windowOutAfter,
            uint48 luOutAfter
        ) = harness.outRateLimits(EID_A);

        assertEq(inFlightOutAfter, inFlightOut, "out.inFlight unchanged");
        assertEq(limitOutAfter, limitOut, "out.limit unchanged");
        assertEq(windowOutAfter, windowOut, "out.window unchanged");
        assertEq(luOutAfter, luOut, "out.lastUpdated unchanged");
    }

    function test_clearInboundInFlight_emitsEventWithExactArray() external {
        uint32[] memory eids = _eids(EID_A, EID_B);

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.InboundInFlightCleared(eids);

        harness.clearInboundInFlight(eids);
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_clearInboundInFlight_idempotent(uint32[] calldata eids_) external {
        // Bound the array length and copy into a memory array.
        uint256 len = bound(eids_.length, 0, 8);
        uint32[] memory eids = new uint32[](len);
        for (uint256 i = 0; i < len; i++) {
            eids[i] = eids_[i];
        }

        // Configure each eid (re-configuring a duplicate is idempotent on
        // (limit, window) at the same block).
        for (uint256 i = 0; i < len; i++) {
            harness.setInRateLimits(_configs(_config(eids[i], DEFAULT_LIMIT, DEFAULT_WINDOW)));
        }
        // Drive each one to a non-zero in-flight. Use a small per-iteration
        // amount so duplicate eids do not exhaust the limit by accumulating
        // across iterations: 8 * 1 = 8 << DEFAULT_LIMIT.
        for (uint256 i = 0; i < len; i++) {
            harness.inflow(eids[i], 1);
        }

        harness.clearInboundInFlight(eids);
        uint48 t1 = uint48(vm.getBlockTimestamp());
        for (uint256 i = 0; i < len; i++) {
            (uint256 inFlight, , , uint48 lu) = harness.inRateLimits(eids[i]);
            assertEq(inFlight, 0, "first clear: inFlight zero");
            assertEq(lu, t1, "first clear: lastUpdated current");
        }

        // The second clear at the same block produces an identical result.
        harness.clearInboundInFlight(eids);
        for (uint256 i = 0; i < len; i++) {
            (uint256 inFlight, , , uint48 lu) = harness.inRateLimits(eids[i]);
            assertEq(inFlight, 0, "second clear: inFlight zero");
            assertEq(lu, t1, "second clear: lastUpdated unchanged at same block");
        }
    }
}
