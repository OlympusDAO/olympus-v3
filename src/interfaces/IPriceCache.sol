// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

/// @title      IPriceCache
/// @notice     Interface for contracts that can cache prices
interface IPriceCache {
    /// @notice             Updates the cached price for an asset
    ///
    /// @param asset_       The address of the asset
    function cachePrice(address asset_) external;

    /// @notice                 Updates the cached price only if stale or no cache exists
    ///
    /// @param asset_           The address of the asset
    /// @param forceUpdate_     If true, update regardless of staleness
    function cachePriceIfNecessary(address asset_, bool forceUpdate_) external;
}
