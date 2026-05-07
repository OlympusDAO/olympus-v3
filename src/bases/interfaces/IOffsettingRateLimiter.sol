// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IOffsettingRateLimiter
/// @notice The external interface of a rate limiter that tracks the amount moved
///         between this contract and a remote endpoint, and offsets activity in one
///         direction against in-flight activity in the other.
interface IOffsettingRateLimiter {
    // ========== TYPES ========== //

    /// @notice The state of a rate limit for a single endpoint identifier and direction.
    /// @param inFlight The amount that has been recorded within the active window and
    ///        has not yet decayed to zero.
    /// @param limit The maximum amount that may be in flight at any point.
    /// @param window The length in seconds of the sliding window over which the
    ///        in-flight amount decays linearly from `limit` to zero.
    /// @param lastUpdated The timestamp of the most recent update applied to this rate
    ///        limit, used as the starting point of the decay calculation.
    struct RateLimit {
        uint256 inFlight;
        uint256 limit;
        uint32 window;
        uint48 lastUpdated;
    }

    /// @notice The configuration payload used to set a rate limit for a given endpoint.
    /// @dev A configuration with `limit` set to zero pauses the direction it
    ///      applies to, since no further capacity can be granted in that direction.
    /// @param eid The endpoint identifier the configuration applies to.
    /// @param limit The maximum amount that may be in flight at any point.
    /// @param window The length in seconds of the sliding window over which the
    ///        in-flight amount decays linearly from `limit` to zero.
    struct RateLimitConfig {
        uint32 eid;
        uint256 limit;
        uint32 window;
    }

    // ========== EVENTS ========== //

    /// @notice Emitted when one or more outbound rate limits have been configured.
    /// @param configs The configurations that have been applied, in the order in which
    ///        they were applied.
    event OutRateLimitsSet(RateLimitConfig[] configs);

    /// @notice Emitted when one or more inbound rate limits have been configured.
    /// @param configs The configurations that have been applied, in the order in which
    ///        they were applied.
    event InRateLimitsSet(RateLimitConfig[] configs);

    /// @notice Emitted when the outbound in-flight amount has been cleared for one or
    ///         more endpoints.
    /// @dev The corresponding inbound rate limits for the listed endpoints are not
    ///      affected by this operation.
    /// @param eids The endpoint identifiers whose outbound in-flight amount has been
    ///        cleared.
    event OutboundInFlightCleared(uint32[] eids);

    /// @notice Emitted when the inbound in-flight amount has been cleared for one or
    ///         more endpoints.
    /// @dev The corresponding outbound rate limits for the listed endpoints are not
    ///      affected by this operation.
    /// @param eids The endpoint identifiers whose inbound in-flight amount has been
    ///        cleared.
    event InboundInFlightCleared(uint32[] eids);

    // ========== ERRORS ========== //

    /// @notice Thrown when a flow would exceed the remaining capacity of a rate limit for a given direction.
    /// @param requested The amount that was attempted to be debited from the rate limit.
    /// @param available The remaining capacity of the rate limit at the current timestamp.
    error RateLimitExceeded(uint256 requested, uint256 available);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the stored outbound rate limit state for a destination endpoint.
    /// @param dstEid_ The destination endpoint identifier.
    /// @return inFlight The stored in-flight amount.
    /// @return limit The maximum amount that may be in flight at any point.
    /// @return window The length in seconds of the sliding window.
    /// @return lastUpdated The timestamp of the most recent update.
    function outRateLimits(
        uint32 dstEid_
    ) external view returns (uint256 inFlight, uint256 limit, uint32 window, uint48 lastUpdated);

    /// @notice Returns the stored inbound rate limit state for a source endpoint.
    /// @param srcEid_ The source endpoint identifier.
    /// @return inFlight The stored in-flight amount.
    /// @return limit The maximum amount that may be in flight at any point.
    /// @return window The length in seconds of the sliding window.
    /// @return lastUpdated The timestamp of the most recent update.
    function inRateLimits(
        uint32 srcEid_
    ) external view returns (uint256 inFlight, uint256 limit, uint32 window, uint48 lastUpdated);

    /// @notice Returns the current outbound capacity for a destination endpoint, with
    ///         the in-flight amount decayed against the current timestamp.
    /// @param dstEid_ The destination endpoint identifier.
    /// @return inFlight The decayed in-flight amount at the current timestamp.
    /// @return available The amount that may still be sent before the rate limit is
    ///         exceeded.
    function sendable(uint32 dstEid_) external view returns (uint256 inFlight, uint256 available);

    /// @notice Returns the current inbound capacity for a source endpoint, with the
    ///         in-flight amount decayed against the current timestamp.
    /// @param srcEid_ The source endpoint identifier.
    /// @return inFlight The decayed in-flight amount at the current timestamp.
    /// @return available The amount that may still be received before the rate limit
    ///         is exceeded.
    function receivable(uint32 srcEid_) external view returns (uint256 inFlight, uint256 available);
}
