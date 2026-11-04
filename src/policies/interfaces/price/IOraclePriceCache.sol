// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @title  IOraclePriceCache
/// @author OlympusDAO
/// @notice Interface for pair oracle contracts that can trigger caching for their configured pair
/// @dev    Use this for pair oracles where the cached pair is embedded in oracle configuration,
///         so callers do not pass pair arguments.
interface IOraclePriceCache {
    /// @notice Triggers a cache update for the oracle's configured pair
    function cachePrice() external;

    /// @notice Triggers a cache update only when the oracle's configured pair cache is stale
    function cachePriceIfNecessary() external;
}
