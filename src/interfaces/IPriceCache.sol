// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title  IPriceCache
/// @author OlympusDAO
/// @notice Interface for caching explicit asset/quote pair snapshots
interface IPriceCache {
    /// @notice Pair cache snapshot in requested orientation
    ///
    /// @param assetPriceUsd Cached asset USD price
    /// @param quotePriceUsd Cached quote USD price
    /// @param updatedAt     Timestamp of snapshot write
    /// @param roundId       Monotonic pair cache write counter
    struct CachedPrice {
        uint256 assetPriceUsd;
        uint256 quotePriceUsd;
        uint48 updatedAt;
        uint80 roundId;
    }

    /// @notice Cache an explicit asset/quote pair snapshot
    ///
    /// @param asset_ Asset in requested orientation
    /// @param quote_ Quote in requested orientation
    function cachePrice(address asset_, address quote_) external;

    /// @notice Cache an explicit pair only when stale for maxAge_
    ///
    /// @param asset_  Asset in requested orientation
    /// @param quote_  Quote in requested orientation
    /// @param maxAge_ Maximum acceptable snapshot age in seconds
    function cachePriceIfNecessary(address asset_, address quote_, uint48 maxAge_) external;

    /// @notice Get the last cached snapshot for a pair in requested orientation
    ///
    /// @param asset_  Asset in requested orientation
    /// @param quote_  Quote in requested orientation
    /// @return cachedPrice Last cached pair snapshot data
    function getCachedPrice(
        address asset_,
        address quote_
    ) external view returns (CachedPrice memory cachedPrice);

    /// @notice Return whether pair snapshot is stale for maxAge_
    ///
    /// @param asset_  Asset in requested orientation
    /// @param quote_  Quote in requested orientation
    /// @param maxAge_ Maximum acceptable snapshot age in seconds
    /// @return stale True when no cache exists or cache is older than maxAge_
    function isStale(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) external view returns (bool stale);
}
