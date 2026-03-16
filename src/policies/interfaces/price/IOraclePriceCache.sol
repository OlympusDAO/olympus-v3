// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title  IOraclePriceCache
/// @author OlympusDAO
/// @notice Interface for pair oracle contracts that can trigger caching for their configured assets
/// @dev    Use this for pair oracles where the cached asset set is embedded in oracle configuration,
///         so callers do not pass an asset argument.
interface IOraclePriceCache {
    /// @notice Triggers cache updates for the oracle's configured assets
    function cachePrices() external;

    /// @notice Triggers cache updates only when the oracle's configured asset caches are stale
    function cachePricesIfNecessary() external;
}
