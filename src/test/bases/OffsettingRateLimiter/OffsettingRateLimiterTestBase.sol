// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.18;

import {Test} from "@forge-std-1.16.2/Test.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

// Libraries
import {OffsettingRateLimiterConstants} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterConstants.sol";

// Contracts
import {OffsettingRateLimiterHarness} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterHarness.sol";

/// @notice Shared test base for the OffsettingRateLimiter unit, scenario and fuzz tests.
/// @dev Defines named constants for every eid, every default rate limit, and every
///      sentinel timestamp used across the tests. Provides helpers for the most
///      repeated actions: building config/eid arrays, asserting the four-tuple of
///      stored state, asserting the (inFlight, available) pair returned by the
///      view functions, configuring + warping forward, recording an outflow /
///      inflow and asserting both-side state, and computing the expected linearly
///      decayed inFlight using the same integer arithmetic as the contract.
contract OffsettingRateLimiterTestBase is Test {
    // ========== ENDPOINT IDS ========== //

    uint32 internal constant EID_A = 101;
    uint32 internal constant EID_B = 202;
    uint32 internal constant EID_C = 303;
    uint32 internal constant EID_D = 404;

    // ========== DEFAULT RATE LIMIT VALUES ========== //

    uint256 internal constant DEFAULT_LIMIT = 1_000 ether;
    uint32 internal constant DEFAULT_WINDOW = 1 hours;
    uint256 internal constant LARGE_LIMIT = 1_000_000 ether;
    uint32 internal constant LARGE_WINDOW = 30 days;

    /// @dev Small `(limit, window)` pair used by tests that need integer-scale
    ///      reasoning over duplicate-eid sequencing or the multi-step
    ///      lifecycle, where multiplying by `1 ether` would obscure the
    ///      arithmetic.
    uint256 internal constant SMALL_LIMIT = 100;
    uint32 internal constant SMALL_WINDOW = 100;

    /// @dev Adversarial-ratio pair: `limit` is much smaller than `window`, so
    ///      the integer division in `_currentState` rounds substantial
    ///      sub-second decay down to zero. Used to lock in observed precision
    ///      behaviour.
    uint256 internal constant PRECISION_LIMIT = 100;
    uint32 internal constant PRECISION_WINDOW = 1_000_000;

    /// @dev Lifecycle-test scaled values: a starting (limit, window) and a
    ///      doubled-limit / 4x-window successor used by the multi-step
    ///      scenario to keep the magnitudes self-documenting.
    uint256 internal constant LIFECYCLE_LIMIT_1 = 1_000;
    uint32 internal constant LIFECYCLE_WINDOW_1 = 1_000;
    uint256 internal constant LIFECYCLE_LIMIT_2 = 2_000;
    uint32 internal constant LIFECYCLE_WINDOW_2 = 4_000;

    /// @dev Coprime numerator / denominator used in the partial-decay tests so
    ///      that the rounded value is non-trivial.
    uint256 internal constant PARTIAL_DECAY_ELAPSED = 1_357;

    // ========== SENTINEL TIMESTAMPS ========== //

    /// @dev Re-exported from `OffsettingRateLimiterConstants` so the unit-test
    ///      base and the invariant entrypoint share one canonical value.
    uint256 internal constant START_TIMESTAMP = OffsettingRateLimiterConstants.START_TIMESTAMP;

    /// @dev Maximum timestamp representable in uint48 (the storage size of
    ///      `lastUpdated`).
    uint256 internal constant UINT48_MAX = type(uint48).max;

    // ========== FUZZ BOUNDS ========== //

    /// @dev Picked so `limit * window` fits in uint256 even when `limit` and
    ///      `window` both saturate the bound. Since `window <= type(uint32).max`
    ///      (the storage size) the bound on `limit` only needs to keep the
    ///      product in range; we pick a generous `2**192` ceiling.
    uint256 internal constant FUZZ_LIMIT_CEIL = 2 ** 192;
    uint32 internal constant MIN_WINDOW = 1;
    uint32 internal constant MAX_WINDOW = type(uint32).max;

    // ========== STATE ========== //

    OffsettingRateLimiterHarness internal harness;

    // ========== SETUP ========== //

    function setUp() public virtual {
        vm.warp(START_TIMESTAMP);
        harness = new OffsettingRateLimiterHarness();
    }

    // ========== CONFIG/EID ARRAY BUILDERS ========== //

    function _config(
        uint32 eid_,
        uint256 limit_,
        uint32 window_
    ) internal pure returns (IOffsettingRateLimiter.RateLimitConfig memory) {
        return IOffsettingRateLimiter.RateLimitConfig({eid: eid_, limit: limit_, window: window_});
    }

    function _configs(
        IOffsettingRateLimiter.RateLimitConfig memory c1_
    ) internal pure returns (IOffsettingRateLimiter.RateLimitConfig[] memory configs) {
        configs = new IOffsettingRateLimiter.RateLimitConfig[](1);
        configs[0] = c1_;
    }

    function _configs(
        IOffsettingRateLimiter.RateLimitConfig memory c1_,
        IOffsettingRateLimiter.RateLimitConfig memory c2_
    ) internal pure returns (IOffsettingRateLimiter.RateLimitConfig[] memory configs) {
        configs = new IOffsettingRateLimiter.RateLimitConfig[](2);
        configs[0] = c1_;
        configs[1] = c2_;
    }

    function _configs(
        IOffsettingRateLimiter.RateLimitConfig memory c1_,
        IOffsettingRateLimiter.RateLimitConfig memory c2_,
        IOffsettingRateLimiter.RateLimitConfig memory c3_
    ) internal pure returns (IOffsettingRateLimiter.RateLimitConfig[] memory configs) {
        configs = new IOffsettingRateLimiter.RateLimitConfig[](3);
        configs[0] = c1_;
        configs[1] = c2_;
        configs[2] = c3_;
    }

    function _emptyConfigs()
        internal
        pure
        returns (IOffsettingRateLimiter.RateLimitConfig[] memory)
    {
        return new IOffsettingRateLimiter.RateLimitConfig[](0);
    }

    function _eids(uint32 e1_) internal pure returns (uint32[] memory eids) {
        eids = new uint32[](1);
        eids[0] = e1_;
    }

    function _eids(uint32 e1_, uint32 e2_) internal pure returns (uint32[] memory eids) {
        eids = new uint32[](2);
        eids[0] = e1_;
        eids[1] = e2_;
    }

    function _eids(
        uint32 e1_,
        uint32 e2_,
        uint32 e3_
    ) internal pure returns (uint32[] memory eids) {
        eids = new uint32[](3);
        eids[0] = e1_;
        eids[1] = e2_;
        eids[2] = e3_;
    }

    function _emptyEids() internal pure returns (uint32[] memory) {
        return new uint32[](0);
    }

    // ========== STATE ASSERTIONS ========== //

    /// @dev Asserts the full four-tuple of stored outbound state for `eid_`.
    function _assertOutState(
        uint32 eid_,
        uint256 expectedInFlight_,
        uint256 expectedLimit_,
        uint32 expectedWindow_,
        uint48 expectedLastUpdated_,
        string memory label_
    ) internal view {
        (uint256 inFlight, uint256 limit, uint32 window, uint48 lastUpdated) = harness
            .outRateLimits(eid_);
        assertEq(inFlight, expectedInFlight_, string.concat(label_, ": out.inFlight mismatch"));
        assertEq(limit, expectedLimit_, string.concat(label_, ": out.limit mismatch"));
        assertEq(window, expectedWindow_, string.concat(label_, ": out.window mismatch"));
        assertEq(
            lastUpdated,
            expectedLastUpdated_,
            string.concat(label_, ": out.lastUpdated mismatch")
        );
    }

    /// @dev Asserts the full four-tuple of stored inbound state for `eid_`.
    function _assertInState(
        uint32 eid_,
        uint256 expectedInFlight_,
        uint256 expectedLimit_,
        uint32 expectedWindow_,
        uint48 expectedLastUpdated_,
        string memory label_
    ) internal view {
        (uint256 inFlight, uint256 limit, uint32 window, uint48 lastUpdated) = harness.inRateLimits(
            eid_
        );
        assertEq(inFlight, expectedInFlight_, string.concat(label_, ": in.inFlight mismatch"));
        assertEq(limit, expectedLimit_, string.concat(label_, ": in.limit mismatch"));
        assertEq(window, expectedWindow_, string.concat(label_, ": in.window mismatch"));
        assertEq(
            lastUpdated,
            expectedLastUpdated_,
            string.concat(label_, ": in.lastUpdated mismatch")
        );
    }

    /// @dev Asserts the (inFlight, available) pair returned by `sendable`.
    function _assertSendable(
        uint32 eid_,
        uint256 expectedInFlight_,
        uint256 expectedAvailable_,
        string memory label_
    ) internal view {
        (uint256 inFlight, uint256 available) = harness.sendable(eid_);
        assertEq(
            inFlight,
            expectedInFlight_,
            string.concat(label_, ": sendable.inFlight mismatch")
        );
        assertEq(
            available,
            expectedAvailable_,
            string.concat(label_, ": sendable.available mismatch")
        );
    }

    /// @dev Asserts the (inFlight, available) pair returned by `receivable`.
    function _assertReceivable(
        uint32 eid_,
        uint256 expectedInFlight_,
        uint256 expectedAvailable_,
        string memory label_
    ) internal view {
        (uint256 inFlight, uint256 available) = harness.receivable(eid_);
        assertEq(
            inFlight,
            expectedInFlight_,
            string.concat(label_, ": receivable.inFlight mismatch")
        );
        assertEq(
            available,
            expectedAvailable_,
            string.concat(label_, ": receivable.available mismatch")
        );
    }

    // ========== HIGHER-LEVEL HELPERS ========== //

    /// @dev Configures both directions for `eid_` with the same `(limit, window)`
    ///      then warps `vm.getBlockTimestamp()` forward by `delay_` seconds.
    function _setupBoth(uint32 eid_, uint256 limit_, uint32 window_, uint64 delay_) internal {
        harness.setOutRateLimits(_configs(_config(eid_, limit_, window_)));
        harness.setInRateLimits(_configs(_config(eid_, limit_, window_)));
        if (delay_ != 0) {
            vm.warp(vm.getBlockTimestamp() + delay_);
        }
    }

    /// @dev Records an outflow for `eid_` of `amount_` and asserts the resulting
    ///      stored inFlight on both sides.
    function _outflowAndAssert(
        uint32 eid_,
        uint256 amount_,
        uint256 expectedOutInFlight_,
        uint256 expectedInInFlight_,
        string memory label_
    ) internal {
        harness.outflow(eid_, amount_);
        (uint256 outInFlight, , , uint48 outLastUpdated) = harness.outRateLimits(eid_);
        (uint256 inInFlight, , , uint48 inLastUpdated) = harness.inRateLimits(eid_);
        assertEq(
            outInFlight,
            expectedOutInFlight_,
            string.concat(label_, ": out.inFlight after outflow")
        );
        assertEq(
            inInFlight,
            expectedInInFlight_,
            string.concat(label_, ": in.inFlight after outflow")
        );
        assertEq(
            outLastUpdated,
            uint48(vm.getBlockTimestamp()),
            string.concat(label_, ": out.lastUpdated after outflow")
        );
        assertEq(
            inLastUpdated,
            uint48(vm.getBlockTimestamp()),
            string.concat(label_, ": in.lastUpdated after outflow")
        );
    }

    /// @dev Records an inflow for `eid_` of `amount_` and asserts the resulting
    ///      stored inFlight on both sides.
    function _inflowAndAssert(
        uint32 eid_,
        uint256 amount_,
        uint256 expectedInInFlight_,
        uint256 expectedOutInFlight_,
        string memory label_
    ) internal {
        harness.inflow(eid_, amount_);
        (uint256 outInFlight, , , uint48 outLastUpdated) = harness.outRateLimits(eid_);
        (uint256 inInFlight, , , uint48 inLastUpdated) = harness.inRateLimits(eid_);
        assertEq(
            inInFlight,
            expectedInInFlight_,
            string.concat(label_, ": in.inFlight after inflow")
        );
        assertEq(
            outInFlight,
            expectedOutInFlight_,
            string.concat(label_, ": out.inFlight after inflow")
        );
        assertEq(
            inLastUpdated,
            uint48(vm.getBlockTimestamp()),
            string.concat(label_, ": in.lastUpdated after inflow")
        );
        assertEq(
            outLastUpdated,
            uint48(vm.getBlockTimestamp()),
            string.concat(label_, ": out.lastUpdated after inflow")
        );
    }

    // ========== DECAY ARITHMETIC HELPERS ========== //

    /// @dev Mirrors `_currentState` of the contract: computes the decayed
    ///      in-flight value for a given `(inFlight_, limit_, window_, elapsed_)`
    ///      using the same integer arithmetic the contract uses (`limit_ *
    ///      elapsed_ / window_` followed by clamp-at-zero). When `window_ == 0`
    ///      or `elapsed_ >= window_` the function returns `0`.
    function _expectedDecayedInFlight(
        uint256 inFlight_,
        uint256 limit_,
        uint32 window_,
        uint256 elapsed_
    ) internal pure returns (uint256) {
        if (window_ == 0) return 0;
        if (elapsed_ >= window_) return 0;
        uint256 decay = (limit_ * elapsed_) / window_;
        return decay >= inFlight_ ? 0 : inFlight_ - decay;
    }

    /// @dev Mirrors `_currentState` end-to-end: returns `(inFlight, available)`
    ///      using the same arithmetic as the contract.
    function _expectedCurrentState(
        uint256 inFlight_,
        uint256 limit_,
        uint32 window_,
        uint256 elapsed_
    ) internal pure returns (uint256 inFlight, uint256 available) {
        if (window_ == 0 || elapsed_ >= window_) return (0, limit_);
        uint256 decay = (limit_ * elapsed_) / window_;
        inFlight = decay >= inFlight_ ? 0 : inFlight_ - decay;
        available = limit_ > inFlight ? limit_ - inFlight : 0;
    }

    // ========== FUZZ HELPERS ========== //

    /// @dev Hashes the full four-tuple of stored outbound state for `eid_`,
    ///      so before/after comparisons can be expressed as a single equality.
    function _outFingerprint(uint32 eid_) internal view returns (bytes32) {
        (uint256 inFlight, uint256 limit, uint32 window, uint48 lu) = harness.outRateLimits(eid_);
        return keccak256(abi.encode(inFlight, limit, window, lu));
    }

    /// @dev Hashes the full four-tuple of stored inbound state for `eid_`,
    ///      so before/after comparisons can be expressed as a single equality.
    function _inFingerprint(uint32 eid_) internal view returns (bytes32) {
        (uint256 inFlight, uint256 limit, uint32 window, uint48 lu) = harness.inRateLimits(eid_);
        return keccak256(abi.encode(inFlight, limit, window, lu));
    }
}
