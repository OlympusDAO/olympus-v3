// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {Test} from "@forge-std-1.16.2/Test.sol";
import {StdInvariant} from "@forge-std-1.16.2/StdInvariant.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

// Libraries
import {OffsettingRateLimiterConstants} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterConstants.sol";

// Contracts
import {OffsettingRateLimiterHarness} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterHarness.sol";
import {OffsettingRateLimiterHandler} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterHandler.sol";

/// @notice Invariant tests for the OffsettingRateLimiter abstract contract. The
///         fuzzer drives the handler's restricted action surface; we read the
///         harness state and the handler's ghost variables to assert global
///         properties.
/// @dev Two independence properties (per-direction and cross-eid) are enforced
///      *inside the handler*, since they can only be observed at the action
///      boundary. The corresponding `invariant_handler_*` functions here only
///      assert that the handler-side checks ran, as a coverage signal.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract OffsettingRateLimiterTests_Invariants is StdInvariant, Test {
    OffsettingRateLimiterHarness internal harness;
    OffsettingRateLimiterHandler internal handler;

    /// @dev Snapshot of the previous `lastUpdated` per direction per tracked
    ///      eid, used by `invariant_lastUpdated_monotonic`. Updated at the
    ///      end of each invariant call.
    mapping(uint32 => uint48) internal _prevOutLastUpdated;
    mapping(uint32 => uint48) internal _prevInLastUpdated;

    function setUp() public {
        // Use a fixed start timestamp so the first warp does not underflow.
        // Reuses the same value as the unit-test base so all suites share
        // one calibrated origin point.
        vm.warp(OffsettingRateLimiterConstants.START_TIMESTAMP);
        harness = new OffsettingRateLimiterHarness();
        handler = new OffsettingRateLimiterHandler(harness);

        // Bootstrap the coverage-signal counters by running real handler
        // actions, NOT by manually incrementing the ghost variables. The
        // action wrappers run their snapshot+compare logic and increment the
        // ghost counters as a side effect. This guarantees that the
        // verification code paths are exercised by the bootstrap itself, so
        // a regression that removes one of those checks does not silently
        // pass.
        //
        // Sequence chosen to cover all three counters:
        //   - setOut: directionIndependenceChecked +1, crossEidIndependenceChecked +1
        //   - outflow(eid, 1): primes outbound to 1
        //   - inflow(eid, 2): triggers the floor branch (subOrZero(1, 2) = 0),
        //     so counterpartFloorHits +1 plus crossEidIndependenceChecked +1
        handler.setOut(0, _bootstrapLimit(), _bootstrapWindow());
        handler.outflow(0, 1);
        handler.inflow(0, 2);
        require(
            handler.counterpartFloorHits() > 0,
            "bootstrap failed to fire counterpartFloorHits"
        );
        require(
            handler.directionIndependenceChecked() > 0,
            "bootstrap failed to fire directionIndependenceChecked"
        );
        require(
            handler.crossEidIndependenceChecked() > 0,
            "bootstrap failed to fire crossEidIndependenceChecked"
        );

        targetContract(address(handler));
        excludeContract(address(harness));
    }

    /// @dev Mirrors the handler's `MAX_LIMIT` constant.
    function _bootstrapLimit() private pure returns (uint256) {
        return 1_000_000 ether;
    }

    /// @dev Mirrors the handler's `DEFAULT_PRECONFIG_WINDOW` constant.
    function _bootstrapWindow() private pure returns (uint32) {
        return 1 hours;
    }

    // ========== INVARIANTS ========== //

    /// @notice If the *stored* inFlight is at most the limit, the decayed
    ///         inFlight is also at most the limit on both directions. Note
    ///         that `stored > limit` is reachable after a limit reduction;
    ///         the property only constrains the well-behaved case.
    function invariant_decayedInFlightLeLimitWhenBelowLimit() public view {
        for (uint256 i = 0; i < handler.trackedEidsLength(); i++) {
            uint32 eid = handler.trackedEids(i);
            (uint256 outStored, uint256 outLimit, , ) = harness.outRateLimits(eid);
            if (outStored <= outLimit) {
                (uint256 outDecayed, ) = harness.sendable(eid);
                assertLe(outDecayed, outLimit, "out decayed > out limit");
            }
            (uint256 inStored, uint256 inLimit, , ) = harness.inRateLimits(eid);
            if (inStored <= inLimit) {
                (uint256 inDecayed, ) = harness.receivable(eid);
                assertLe(inDecayed, inLimit, "in decayed > in limit");
            }
        }
    }

    /// @notice When the decayed inFlight is at most the limit, available +
    ///         decayed equals limit. When the decayed inFlight exceeds the
    ///         limit (only possible during the brief window between a limit
    ///         reduction and the next decay-checkpoint), available is zero.
    function invariant_availablePlusInFlightEqLimitNormalCase() public view {
        for (uint256 i = 0; i < handler.trackedEidsLength(); i++) {
            uint32 eid = handler.trackedEids(i);
            _checkBalance(eid, true);
            _checkBalance(eid, false);
        }
    }

    function _checkBalance(uint32 eid_, bool out_) private view {
        (, uint256 limit, , ) = out_ ? harness.outRateLimits(eid_) : harness.inRateLimits(eid_);
        (uint256 decayed, uint256 available) = out_
            ? harness.sendable(eid_)
            : harness.receivable(eid_);

        if (decayed <= limit) {
            assertEq(decayed + available, limit, "decayed + available != limit");
        } else {
            assertEq(available, 0, "available not zero when decayed > limit");
        }
    }

    /// @notice `sendable` and `receivable` never revert on any tracked eid,
    ///         regardless of the configured `(limit, window)` and stored
    ///         in-flight values reachable via the handler's action surface.
    function invariant_sendable_receivable_neverRevert() public view {
        for (uint256 i = 0; i < handler.trackedEidsLength(); i++) {
            uint32 eid = handler.trackedEids(i);
            harness.sendable(eid);
            harness.receivable(eid);
        }
    }

    /// @notice `lastUpdated` for any direction never decreases between
    ///         successive observations. The snapshot is updated at the end of
    ///         each invariant call so the comparison is against the previous
    ///         observation, not against `setUp`.
    function invariant_lastUpdated_monotonic() public {
        for (uint256 i = 0; i < handler.trackedEidsLength(); i++) {
            uint32 eid = handler.trackedEids(i);
            (, , , uint48 outLu) = harness.outRateLimits(eid);
            (, , , uint48 inLu) = harness.inRateLimits(eid);
            assertGe(outLu, _prevOutLastUpdated[eid], "out.lastUpdated regressed");
            assertGe(inLu, _prevInLastUpdated[eid], "in.lastUpdated regressed");
            _prevOutLastUpdated[eid] = outLu;
            _prevInLastUpdated[eid] = inLu;
        }
    }

    // ========== COVERAGE SIGNALS ========== //
    //
    // The three invariants below assert the bootstrap-set ghost counters
    // remain > 0. The actual property each represents is enforced inside the
    // handler's actions via in-action `assertEq`. The corresponding ghost
    // counter is bootstrapped to >= 1 in `setUp` by running real handler
    // actions, so the very first invariant call after `setUp` does not see a
    // zero counter, and each fuzz run inherits the bootstrapped state.

    /// @notice The counterpart-floor branch in `_settle` is exercised at
    ///         least once during the run.
    function invariant_counterpartFloorWasExercised() public view {
        assertGt(handler.counterpartFloorHits(), 0, "counterpart floor never reached");
    }

    /// @notice The handler ran the per-direction-independence check at least
    ///         once across the run.
    function invariant_handler_directionIndependenceWasChecked() public view {
        assertGt(
            handler.directionIndependenceChecked(),
            0,
            "direction-independence check never ran"
        );
    }

    /// @notice The handler ran the cross-eid-independence check at least
    ///         once across the run.
    function invariant_handler_crossEidIndependenceWasChecked() public view {
        assertGt(
            handler.crossEidIndependenceChecked(),
            0,
            "cross-eid-independence check never ran"
        );
    }
}
