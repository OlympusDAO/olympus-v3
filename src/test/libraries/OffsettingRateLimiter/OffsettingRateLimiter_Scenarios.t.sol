// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {OffsettingRateLimiterTestBase} from "src/test/libraries/OffsettingRateLimiter/OffsettingRateLimiterTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/interfaces/IOffsettingRateLimiter.sol";

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
        uint48 t0 = uint48(block.timestamp);
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
        uint48 t0 = uint48(block.timestamp);
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
        uint48 t1 = uint48(block.timestamp);
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
        uint48 t2 = uint48(block.timestamp);
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
        uint48 t3 = uint48(block.timestamp);
        _assertOutState(EID_A, 0, limit2, window2, t3, "step 8: cleared");
        _assertSendable(EID_A, 0, limit2, "step 8: full capacity post-reset");

        // Step 9: outflow again at the new limit.
        harness.outflow(EID_A, limit2);
        _assertOutState(EID_A, limit2, limit2, window2, t3, "step 9: outflow post-reset");
        _assertSendable(EID_A, limit2, 0, "step 9: zero capacity again");
    }
}
