// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

// TODO: consider whether the rate limit feature is required

// Adopted from: LayerZero OApp RateLimiter (an abstract contract).
// TODO: specify a specific commit hash instead
// Source: @layerzerolabs/oapp-evm v0.4.1, contracts/oapp/utils/RateLimiter.sol (MIT)
//
// Differences from upstream:
// 1. Rewritten as a library with struct Limits (storage wrapper); mapping is internal, exposed via
//    explicit view helpers, events are left to the consuming contract.
// 2. Unconfigured EIDs (limit == 0 && window == 0) skip the check instead of reverting,
//    making rate limiting opt-in per EID rather than requiring explicit configuration
//    for every peer before traffic is allowed.
// 3. The configure() loop is checked (the upstream uses unchecked,
//    but the current version of Solidity does not require this).

/// @title RateLimiterLib
/// @notice Library for per-endpoint rate limiting with linear decay.
library RateLimiterLib {
    // ========= TYPES ========= //

    /// @notice Persistent store wrapping the per-endpoint rate limit mapping.
    struct Limits {
        mapping(uint32 eid => RateLimit) limits;
    }

    /// @notice Rate limit state for a single endpoint.
    /// @param amountInFlight The amount currently in flight.
    /// @param lastUpdated Timestamp of the last update.
    /// @param limit Maximum allowed amount within the window.
    /// @param window Duration of the rate limiting window in seconds.
    struct RateLimit {
        uint192 amountInFlight;
        uint64 lastUpdated;
        uint192 limit;
        uint64 window;
    }

    /// @notice Configuration input for setting rate limits.
    /// @param dstEid The destination endpoint ID.
    /// @param limit Maximum allowed amount within the window. 0 = unconfigured, type(uint192).max = effectively disabled.
    /// @param window Duration of the rate limiting window in seconds.
    struct RateLimitConfig {
        uint32 dstEid;
        uint192 limit;
        uint64 window;
    }

    // ========= ERRORS ========= //

    /// @notice Thrown when a send would exceed the rate limit.
    error RateLimitExceeded();

    // ========= FUNCTIONS ========= //

    /// @notice Configures rate limits for one or more endpoints.
    /// @dev Checkpoints existing rate limit state before applying new parameters to avoid
    ///      retroactively applying a new decay rate.
    /// @param self The rate limiter store.
    /// @param configs_ Array of rate limit configurations.
    function configure(Limits storage self, RateLimitConfig[] calldata configs_) internal {
        for (uint256 i = 0; i < configs_.length; i++) {
            RateLimit storage rl = self.limits[configs_[i].dstEid];

            // Checkpoint existing rate limit to avoid retroactively applying new decay rate
            checkOutflow(self, configs_[i].dstEid, 0);

            rl.limit = configs_[i].limit;
            rl.window = configs_[i].window;
        }
    }

    /// @notice Resets rate limit state (amountInFlight) for the given endpoint IDs.
    /// @dev Sets amountInFlight to 0 and lastUpdated to the current timestamp.
    ///      Does not modify limit or window.
    /// @param self The rate limiter store.
    /// @param eids_ The endpoint IDs to reset.
    function reset(Limits storage self, uint32[] calldata eids_) internal {
        for (uint256 i = 0; i < eids_.length; i++) {
            RateLimit storage rl = self.limits[eids_[i]];
            rl.amountInFlight = 0;
            rl.lastUpdated = uint64(block.timestamp);
        }
    }

    /// @notice Checks and updates outflow for rate limiting.
    /// @dev Unconfigured EIDs (limit == 0 && window == 0) are skipped.
    /// @param self The rate limiter store.
    /// @param eid_ The destination endpoint ID.
    /// @param amount_ The amount to send.
    function checkOutflow(Limits storage self, uint32 eid_, uint256 amount_) internal {
        RateLimit storage rl = self.limits[eid_];

        // Skip unconfigured rate limits
        if (rl.limit == 0 && rl.window == 0) return;

        (uint256 currentAmountInFlight, uint256 amountCanBeSent_) = _decay(
            rl.amountInFlight,
            rl.lastUpdated,
            rl.limit,
            rl.window
        );
        if (amount_ > amountCanBeSent_) revert RateLimitExceeded();

        rl.amountInFlight = uint192(currentAmountInFlight + amount_);
        rl.lastUpdated = uint64(block.timestamp);
    }

    /// @notice Reduces amountInFlight on inflow.
    /// @param self The rate limiter store.
    /// @param eid_ The source endpoint ID.
    /// @param amount_ The amount received.
    function checkInflow(Limits storage self, uint32 eid_, uint256 amount_) internal {
        RateLimit storage rl = self.limits[eid_];
        rl.amountInFlight = uint192(amount_ >= rl.amountInFlight ? 0 : rl.amountInFlight - amount_);
    }

    /// @notice Returns how much can currently be sent to a destination endpoint.
    /// @param self The rate limiter store.
    /// @param eid_ The destination endpoint ID.
    /// @return currentAmountInFlight The current decayed amount in flight.
    /// @return amountCanBeSent_ The amount that can still be sent.
    function amountCanBeSent(
        Limits storage self,
        uint32 eid_
    ) internal view returns (uint256 currentAmountInFlight, uint256 amountCanBeSent_) {
        RateLimit memory rl = self.limits[eid_];
        return _decay(rl.amountInFlight, rl.lastUpdated, rl.limit, rl.window);
    }

    /// @notice Returns the raw rate limit state for a given endpoint.
    /// @param self The rate limiter store.
    /// @param eid_ The endpoint ID.
    /// @return amountInFlight The amount currently in flight.
    /// @return lastUpdated Timestamp of the last update.
    /// @return limit Maximum allowed amount.
    /// @return window Duration of the window.
    function get(
        Limits storage self,
        uint32 eid_
    )
        internal
        view
        returns (uint192 amountInFlight, uint64 lastUpdated, uint192 limit, uint64 window)
    {
        RateLimit memory rl = self.limits[eid_];
        return (rl.amountInFlight, rl.lastUpdated, rl.limit, rl.window);
    }

    // ========= PRIVATE ========= //

    /// @notice Calculates the current decayed amount in flight and how much can be sent.
    function _decay(
        uint192 amountInFlight_,
        uint64 lastUpdated_,
        uint192 limit_,
        uint64 window_
    ) private view returns (uint256 currentAmountInFlight, uint256 amountCanBeSent_) {
        uint256 timeSinceLastDeposit = block.timestamp - lastUpdated_;
        // Linear decay
        uint256 decay = (uint256(limit_) * timeSinceLastDeposit) / (window_ > 0 ? window_ : 1);
        currentAmountInFlight = amountInFlight_ <= decay ? 0 : amountInFlight_ - decay;
        // If limit was lowered below current in-flight, set to 0
        amountCanBeSent_ = limit_ <= currentAmountInFlight ? 0 : limit_ - currentAmountInFlight;
    }
}
