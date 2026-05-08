// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

// Libraries
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";

/// @title OffsettingRateLimiter
/// @notice An abstract rate limiter that maintains independent outbound and inbound
///         rate limits per endpoint, and offsets activity in one direction against
///         the in-flight amount of the other.
/// @dev Each endpoint has two rate limits: outbound (`outRateLimits`) and
///      inbound (`inRateLimits`), whose in-flight amounts decay linearly
///      over the configured window. A flow debits its own side in full and
///      offsets the counterpart by reducing its in-flight with a floor at
///      zero; excess credit is dropped, not carried over.
///
///      This is not net accounting: the trailing leg of a round trip always
///      records its full amount, since the leading leg's in-flight has
///      already partially decayed by the time it is cancelled. A balanced
///      round trip therefore leaves residual in-flight equal to the trailing
///      leg, not zero.
///
///      Only internal mutators are exposed; an inheriting contract must gate
///      configuration and reset behind its own access control and invoke
///      `_outflow` / `_inflow` from the appropriate code paths.
abstract contract OffsettingRateLimiter is IOffsettingRateLimiter {
    /// @inheritdoc IOffsettingRateLimiter
    /// @dev The returned `inFlight` value is the raw stored amount and has not been
    ///      decayed against the current timestamp. Callers that require the current
    ///      effective capacity should use `sendable` instead.
    mapping(uint32 dstEid_ => RateLimit) public override outRateLimits;

    /// @inheritdoc IOffsettingRateLimiter
    /// @dev The returned `inFlight` value is the raw stored amount and has not been
    ///      decayed against the current timestamp. Callers that require the current
    ///      effective capacity should use `receivable` instead.
    mapping(uint32 srcEid_ => RateLimit) public override inRateLimits;

    /// @inheritdoc IOffsettingRateLimiter
    /// @dev When the configured window has fully elapsed since `lastUpdated`, or
    ///      when the configured window is zero, the returned `inFlight` is zero and
    ///      `available` is the full configured `limit`.
    function sendable(
        uint32 dstEid_
    ) external view virtual override returns (uint256 inFlight, uint256 available) {
        RateLimit storage rl = outRateLimits[dstEid_];
        return _currentState(rl.inFlight, rl.limit, rl.window, rl.lastUpdated);
    }

    /// @inheritdoc IOffsettingRateLimiter
    /// @dev When the configured window has fully elapsed since `lastUpdated`, or
    ///      when the configured window is zero, the returned `inFlight` is zero and
    ///      `available` is the full configured `limit`.
    function receivable(
        uint32 srcEid_
    ) external view virtual override returns (uint256 inFlight, uint256 available) {
        RateLimit storage rl = inRateLimits[srcEid_];
        return _currentState(rl.inFlight, rl.limit, rl.window, rl.lastUpdated);
    }

    /// @notice Configures the outbound rate limits for one or more destination
    ///         endpoints.
    /// @dev For each configuration, the existing outbound rate limit is
    ///      checkpointed against the current timestamp before the new `limit` and
    ///      `window` values are written, so the stored in-flight amount continues
    ///      to decay at the previous rate up to the moment of the change. The
    ///      in-flight amount itself is preserved across the configuration change.
    ///      The corresponding inbound rate limit is also checkpointed
    ///      (decayed-in-place with `lastUpdated` refreshed) by the same call, but
    ///      its `limit` and `window` are not modified.
    ///      Repeated entries for the same endpoint within the same call are
    ///      applied in order, so the last entry determines the final state.
    ///      This deviates from the typical convention elsewhere in the codebase
    ///      of reverting on duplicate inputs; here duplicates are accepted and
    ///      the trailing entry overrides the earlier ones.
    ///
    ///     Emits an `OutRateLimitsSet` event.
    /// @param configs_ The outbound rate limit configurations to apply.
    function _setOutRateLimits(RateLimitConfig[] memory configs_) internal virtual {
        _applyConfigs(outRateLimits, inRateLimits, configs_);
        emit OutRateLimitsSet(configs_);
    }

    /// @notice Configures the inbound rate limits for one or more source endpoints.
    /// @dev For each configuration, the existing inbound rate limit is
    ///      checkpointed against the current timestamp before the new `limit` and
    ///      `window` values are written, so the stored in-flight amount continues
    ///      to decay at the previous rate up to the moment of the change. The
    ///      in-flight amount itself is preserved across the configuration change.
    ///      The corresponding outbound rate limit is also checkpointed
    ///      (decayed-in-place with `lastUpdated` refreshed) by the same call, but
    ///      its `limit` and `window` are not modified.
    ///      Repeated entries for the same endpoint within the same call are
    ///      applied in order, so the last entry determines the final state.
    ///      This deviates from the typical convention elsewhere in the codebase
    ///      of reverting on duplicate inputs; here duplicates are accepted and
    ///      the trailing entry overrides the earlier ones.
    ///
    ///      Emits an `InRateLimitsSet` event.
    /// @param configs_ The inbound rate limit configurations to apply.
    function _setInRateLimits(RateLimitConfig[] memory configs_) internal virtual {
        _applyConfigs(inRateLimits, outRateLimits, configs_);
        emit InRateLimitsSet(configs_);
    }

    /// @notice Applies a batch of rate limit configurations to a primary direction
    ///         and checkpoints the in-flight amount against the previous configuration.
    /// @dev The function calls `_settle` with a zero delta for each entry, which
    ///      decays the existing in-flight amount and refreshes `lastUpdated` to
    ///      the current timestamp before the new `limit` and `window` are written.
    ///      The counterpart rate limit is also checkpointed by the same call,
    ///      since `_settle` always touches both sides, even though no delta is
    ///      recorded.
    /// @param rlByEid_ The mapping that holds the rate limits being configured.
    /// @param counterpartRlByEid_ The mapping that holds the counterpart rate limits.
    /// @param configs_ The rate limit configurations to apply.
    function _applyConfigs(
        mapping(uint32 => RateLimit) storage rlByEid_,
        mapping(uint32 => RateLimit) storage counterpartRlByEid_,
        RateLimitConfig[] memory configs_
    ) private {
        uint256 len = configs_.length;
        uint32 eid;
        for (uint256 i = 0; i < len; ++i) {
            eid = configs_[i].eid;
            RateLimit storage rl = rlByEid_[eid];
            _settle(rl, counterpartRlByEid_[eid], 0);
            rl.limit = configs_[i].limit;
            rl.window = configs_[i].window;
        }
    }

    /// @notice Clears the outbound in-flight amount for one or more destination
    ///         endpoints.
    /// @dev The in-flight amount is set to zero and `lastUpdated` is set to the
    ///      current timestamp for each endpoint. The configured `limit` and
    ///      `window` are not modified, and the corresponding inbound rate limits
    ///      are not affected.
    ///
    ///      Emits an `OutboundInFlightCleared` event.
    /// @param eids_ The destination endpoint identifiers to reset.
    function _clearOutboundInFlight(uint32[] memory eids_) internal virtual {
        _reset(outRateLimits, eids_);
        emit OutboundInFlightCleared(eids_);
    }

    /// @notice Clears the inbound in-flight amount for one or more source endpoints.
    /// @dev The in-flight amount is set to zero and `lastUpdated` is set to the
    ///      current timestamp for each endpoint. The configured `limit` and
    ///      `window` are not modified, and the corresponding outbound rate limits
    ///      are not affected.
    ///
    ///      Emits an `InboundInFlightCleared` event.
    /// @param eids_ The source endpoint identifiers to reset.
    function _clearInboundInFlight(uint32[] memory eids_) internal virtual {
        _reset(inRateLimits, eids_);
        emit InboundInFlightCleared(eids_);
    }

    /// @notice Clears the in-flight amount for a set of endpoints in the given
    ///         mapping.
    /// @dev For each endpoint, the in-flight amount is set to zero and
    ///      `lastUpdated` is set to the current timestamp. The `limit` and
    ///      `window` are preserved.
    /// @param rlByEid_ The mapping that holds the rate limits to reset.
    /// @param eids_ The endpoint identifiers to reset.
    function _reset(mapping(uint32 => RateLimit) storage rlByEid_, uint32[] memory eids_) private {
        uint256 len = eids_.length;
        for (uint256 i = 0; i < len; ++i) {
            RateLimit storage rl = rlByEid_[eids_[i]];
            rl.inFlight = 0;
            rl.lastUpdated = uint48(block.timestamp);
        }
    }

    /// @notice Records an outbound flow of `amount_` to the destination endpoint and
    ///         credits the inbound rate limit for the same endpoint by the same
    ///         amount.
    /// @dev Reverts with `RateLimitExceeded` when `amount_` is greater than the
    ///      available outbound capacity at the current timestamp. The inbound
    ///      credit is clamped at zero, so any excess credit beyond the inbound
    ///      in-flight amount is dropped rather than carried over.
    /// @param dstEid_ The destination endpoint identifier.
    /// @param amount_ The amount to record as an outbound flow.
    function _outflow(uint32 dstEid_, uint256 amount_) internal virtual {
        _settle(outRateLimits[dstEid_], inRateLimits[dstEid_], amount_);
    }

    /// @notice Records an inbound flow of `amount_` from the source endpoint and
    ///         credits the outbound rate limit for the same endpoint by the same
    ///         amount.
    /// @dev Reverts with `RateLimitExceeded` when `amount_` is greater than the
    ///      available inbound capacity at the current timestamp. The outbound
    ///      credit is clamped at zero, so any excess credit beyond the outbound
    ///      in-flight amount is dropped rather than carried over.
    /// @param srcEid_ The source endpoint identifier.
    /// @param amount_ The amount to record as an inbound flow.
    function _inflow(uint32 srcEid_, uint256 amount_) internal virtual {
        _settle(inRateLimits[srcEid_], outRateLimits[srcEid_], amount_);
    }

    /// @notice Computes the decayed in-flight amount and the remaining capacity of a
    ///         rate limit at the current timestamp.
    /// @dev The decay is linear at a rate of `limit_ / window_` per second from
    ///      the stored `inFlight_` value at `lastUpdated_`. When the elapsed time
    ///      is at least `window_`, or when `window_` is zero, the function returns
    ///      a fully decayed result with `inFlight` equal to zero and `available`
    ///      equal to the full `limit_`. The early return also avoids a division by
    ///      zero when `window_` is zero.
    ///
    ///      Integer division of `decay` rounds DOWN, so the effective
    ///      `inFlight` is rounded UP and `available` is rounded DOWN relative
    ///      to the exact linear curve. This is the protocol-favourable
    ///      direction: a user can never observe more capacity than the true
    ///      linear decay would grant, and any sub-quantum slack is held back
    ///      rather than handed out early.
    /// @param inFlight_ The stored in-flight amount at the last update.
    /// @param limit_ The maximum amount that may be in flight at any point.
    /// @param window_ The length in seconds of the sliding window.
    /// @param lastUpdated_ The timestamp of the most recent update.
    /// @return inFlight The decayed in-flight amount at the current timestamp.
    /// @return available The remaining capacity at the current timestamp.
    function _currentState(
        uint256 inFlight_,
        uint256 limit_,
        uint32 window_,
        uint48 lastUpdated_
    ) internal view virtual returns (uint256 inFlight, uint256 available) {
        uint256 elapsed = block.timestamp - lastUpdated_;
        if (elapsed >= window_) return (0, limit_);

        uint256 decay = Math.mulDiv(limit_, elapsed, window_);
        inFlight = _subOrZero(inFlight_, decay);
        available = _subOrZero(limit_, inFlight);
        return (inFlight, available);
    }

    /// @notice Settles a flow of `delta_` against a primary rate limit and credits
    ///         the counterpart rate limit by the same amount.
    /// @dev The function decays the primary rate limit, reverts with
    ///      `RateLimitExceeded` when `delta_` is greater than the remaining
    ///      capacity, and otherwise stores the new in-flight value as the decayed
    ///      amount plus `delta_` and refreshes the primary `lastUpdated` to the
    ///      current timestamp. The counterpart rate limit is then decayed and its
    ///      in-flight value is reduced by `delta_`, with a floor at zero, after
    ///      which its `lastUpdated` is also refreshed to the current timestamp.
    ///
    ///      When `delta_` is zero, the call serves as a checkpoint that captures
    ///      the current decayed in-flight amounts on both rate limits and
    ///      refreshes the `lastUpdated` of both to the current timestamp without
    ///      altering the effective remaining capacity.
    /// @param rl_ The storage reference to the primary rate limit (the one being debited by `delta_`).
    /// @param counterpartRl_ The storage reference to the counterpart rate limit (offset by `delta_`).
    /// @param delta_ The amount to record on the primary side (and to be credited to the counterpart rate limit).
    function _settle(
        RateLimit storage rl_,
        RateLimit storage counterpartRl_,
        uint256 delta_
    ) private {
        // Calculate the current `inFlight` amount and `available` capacity
        (uint256 inFlight, uint256 available) = _currentState(
            rl_.inFlight,
            rl_.limit,
            rl_.window,
            rl_.lastUpdated
        );
        // Check if the requested delta exceeds the available capacity
        if (delta_ > available) revert RateLimitExceeded(delta_, available);
        // Update
        unchecked {
            // Safe: `delta_ <= available` and `inFlight + available` fits in `uint256` (= `max(inFlight, limit_)`)
            rl_.inFlight = inFlight + delta_;
        }
        rl_.lastUpdated = uint48(block.timestamp);

        // Update the counterpart rate limit
        (inFlight, ) = _currentState(
            counterpartRl_.inFlight,
            counterpartRl_.limit,
            counterpartRl_.window,
            counterpartRl_.lastUpdated
        );
        counterpartRl_.inFlight = _subOrZero(inFlight, delta_);
        counterpartRl_.lastUpdated = uint48(block.timestamp);
    }

    /// @notice Returns `a_ - b_` when `a_` is greater than `b_`, and zero otherwise.
    /// @dev The subtraction is performed inside an `unchecked` block, since the
    ///      conditional guarantees that no underflow can occur.
    /// @param a_ The minuend.
    /// @param b_ The subtrahend.
    /// @return The non-negative difference, clamped at zero.
    function _subOrZero(uint256 a_, uint256 b_) private pure returns (uint256) {
        unchecked {
            return a_ > b_ ? a_ - b_ : 0;
        }
    }
}
