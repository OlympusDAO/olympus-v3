// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title  IOraclePriceCache
/// @author OlympusDAO
/// @notice Interface for oracle contracts that can trigger caching for their configured assets
interface IOraclePriceCache {
    /// @notice Triggers cache updates for the oracle's configured assets
    function cachePrices() external;

    /// @notice Triggers cache updates only when the oracle's configured asset caches are stale
    function cachePricesIfNecessary() external;
}
