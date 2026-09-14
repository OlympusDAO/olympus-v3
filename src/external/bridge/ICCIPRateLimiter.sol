// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title ICCIPRateLimiter
/// @notice The token bucket types, events and errors of the Chainlink CCIP `RateLimiter` library.
/// @dev The struct layouts are identical to `RateLimiter.TokenBucket` and `RateLimiter.Config` of
///      Chainlink CCIP 1.6.0, so functions declared with these types encode to the same ABI and
///      the same selectors as the token pool functions that use the Chainlink types. Every amount
///      is expressed in the smallest unit of the pool token.
interface ICCIPRateLimiter {
    // ========== DATA STRUCTURES ========== //

    /// @notice The live state of a token bucket.
    /// @param tokens The current number of tokens in the bucket.
    /// @param lastUpdated The timestamp of the last refill, in seconds.
    /// @param isEnabled Whether the rate limiting is enabled.
    /// @param capacity The maximum number of tokens that the bucket can hold.
    /// @param rate The number of tokens per second that the bucket is refilled with.
    struct TokenBucket {
        uint128 tokens;
        uint32 lastUpdated;
        bool isEnabled;
        uint128 capacity;
        uint128 rate;
    }

    /// @notice The configuration of a token bucket.
    /// @dev    An enabled configuration requires `0 < rate < capacity`. A disabled configuration
    ///         requires `capacity == 0` and `rate == 0` and imposes no limit at all.
    /// @param isEnabled Whether the rate limiting is enabled.
    /// @param capacity The maximum number of tokens that the bucket can hold.
    /// @param rate The number of tokens per second that the bucket is refilled with.
    struct Config {
        bool isEnabled;
        uint128 capacity;
        uint128 rate;
    }

    // ========== EVENTS ========== //

    /// @notice Emitted when tokens are consumed from an enabled bucket.
    /// @param tokens The number of tokens consumed.
    event TokensConsumed(uint256 tokens);

    /// @notice Emitted when a bucket configuration is written.
    /// @param config The configuration written.
    event ConfigChanged(Config config);

    // ========== ERRORS ========== //

    /// @notice Thrown when a bucket holds more tokens than its capacity.
    error BucketOverfilled();

    /// @notice Thrown when a request exceeds the capacity of the bucket.
    /// @param capacity The capacity of the bucket.
    /// @param requested The number of tokens requested.
    /// @param tokenAddress The token of the bucket.
    error TokenMaxCapacityExceeded(uint256 capacity, uint256 requested, address tokenAddress);

    /// @notice Thrown when a request exceeds the tokens currently in the bucket.
    /// @param minWaitInSeconds The number of seconds until the bucket holds enough tokens.
    /// @param available The number of tokens currently in the bucket.
    /// @param tokenAddress The token of the bucket.
    error TokenRateLimitReached(uint256 minWaitInSeconds, uint256 available, address tokenAddress);

    /// @notice Thrown when an enabled configuration has a zero rate or a rate that is not below
    ///         its capacity.
    /// @param rateLimiterConfig The rejected configuration.
    error InvalidRateLimitRate(Config rateLimiterConfig);

    /// @notice Thrown when a disabled configuration has a non-zero capacity or rate.
    /// @param config The rejected configuration.
    error DisabledNonZeroRateLimit(Config config);
}
