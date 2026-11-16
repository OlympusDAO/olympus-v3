// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @title  IPriceCache
/// @author OlympusDAO
/// @notice Interface for caching explicit asset/quote pair snapshots
interface IPriceCache {
    /// @notice Thrown when this policy is no longer active in Kernel
    error PriceCache_PolicyNotActive();

    /// @notice Thrown when a required module version is unsupported
    ///
    /// @param  keycode Module keycode
    /// @param  major   Module major version
    /// @param  minor   Module minor version
    error PriceCache_UnsupportedModuleVersion(bytes5 keycode, uint8 major, uint8 minor);

    /// @notice Thrown when a required module does not implement an interface
    ///
    /// @param  keycode     Module keycode
    /// @param  interfaceId Interface identifier, as specified in ERC-165
    error PriceCache_UnsupportedModuleInterface(bytes5 keycode, bytes4 interfaceId);

    /// @notice Thrown when an asset/quote pair is invalid
    ///
    /// @param  asset_  Asset in requested orientation
    /// @param  quote_  Quote in requested orientation
    error PriceCache_InvalidPair(address asset_, address quote_);

    /// @notice Thrown when a non-contract asset is not registered in PRICE
    ///
    /// @param asset_   Non-contract asset identifier
    error PriceCache_NonContractAssetNotRegistered(address asset_);

    /// @notice Thrown when a non-contract asset has no cache decimals configured
    ///
    /// @param asset_   Non-contract asset identifier
    error PriceCache_NonContractAssetDecimalsNotRegistered(address asset_);

    /// @notice Thrown when a non-contract asset has no cache symbol configured
    ///
    /// @param asset_   Non-contract asset identifier
    error PriceCache_NonContractAssetSymbolNotRegistered(address asset_);

    /// @notice Thrown when the asset identifier is invalid for the requested cache operation
    ///
    /// @param asset_   Asset identifier
    error PriceCache_InvalidAsset(address asset_);

    /// @notice Thrown when a non-contract asset symbol is invalid
    error PriceCache_InvalidAssetSymbol();

    /// @notice Return the USD decimal scale used by cached pair legs
    ///
    /// @return decimals_   USD decimal scale for cached assetPriceUsd/quotePriceUsd values
    function decimals() external view returns (uint8 decimals_);

    /// @notice Pair cache snapshot in requested orientation
    ///
    /// @param assetPriceUsd    Cached asset USD price
    /// @param quotePriceUsd    Cached quote USD price
    /// @param updatedAt        Timestamp of snapshot write
    /// @param roundId          Monotonic pair cache write counter
    struct CachedPrice {
        uint256 assetPriceUsd;
        uint256 quotePriceUsd;
        uint48 updatedAt;
        uint80 roundId;
    }

    /// @notice Stored metadata for a non-contract asset
    ///
    /// @param registered    Whether metadata is configured for the asset
    /// @param decimals      Amount decimal scale for the asset
    /// @param symbol        Display symbol for the asset
    struct NonContractAssetMetadata {
        bool registered;
        uint8 decimals;
        string symbol;
    }

    /// @notice Internal pair snapshot storage in canonical token order
    ///
    /// @param token0PriceUsd    Cached USD price for the lower-sorted asset
    /// @param token1PriceUsd    Cached USD price for the higher-sorted asset
    /// @param updatedAt         Timestamp of snapshot write
    /// @param roundId           Monotonic pair cache write counter
    /// @param token0Epoch       Asset invalidation epoch for token0 at cache time
    /// @param token1Epoch       Asset invalidation epoch for token1 at cache time
    struct PairSnapshot {
        uint256 token0PriceUsd;
        uint256 token1PriceUsd;
        uint48 updatedAt;
        uint80 roundId;
        uint64 token0Epoch;
        uint64 token1Epoch;
    }

    /// @notice Cache an explicit asset/quote pair snapshot
    ///
    /// @param asset_   Asset in requested orientation
    /// @param quote_   Quote in requested orientation
    function cachePrice(address asset_, address quote_) external;

    /// @notice Return the amount decimal scale used for `asset_` quote conversion
    ///
    /// @param asset_       Asset identifier
    /// @return decimals_   Amount decimal scale for `asset_`
    function assetDecimals(address asset_) external view returns (uint8 decimals_);

    /// @notice Return the symbol used for naming and display of `asset_`
    ///
    /// @param asset_       Asset identifier
    /// @return symbol_     Symbol for `asset_`
    function assetSymbol(address asset_) external view returns (string memory symbol_);

    /// @notice Set the metadata for a registered non-contract asset
    ///
    /// @param asset_       Non-contract asset identifier
    /// @param decimals_    Amount decimal scale for `asset_`
    /// @param symbol_      Display symbol for `asset_`
    function setNonContractAssetMetadata(
        address asset_,
        uint8 decimals_,
        string calldata symbol_
    ) external;

    /// @notice Remove the configured metadata for a non-contract asset
    ///
    /// @param asset_   Non-contract asset identifier
    function removeNonContractAssetMetadata(address asset_) external;

    /// @notice Cache an explicit pair only when stale for maxAge_
    ///
    /// @param asset_   Asset in requested orientation
    /// @param quote_   Quote in requested orientation
    /// @param maxAge_  Maximum acceptable snapshot age in seconds
    function cachePriceIfNecessary(address asset_, address quote_, uint48 maxAge_) external;

    /// @notice Get the last cached snapshot for a pair in requested orientation
    /// @dev    Returns a zeroed snapshot for valid pairs when no snapshot exists in the current cache epoch
    ///
    /// @param asset_       Asset in requested orientation
    /// @param quote_       Quote in requested orientation
    /// @return cachedPrice Last cached pair snapshot data; all fields are zero when no snapshot exists
    function getCachedPrice(
        address asset_,
        address quote_
    ) external view returns (CachedPrice memory cachedPrice);

    /// @notice Return whether pair snapshot is stale for maxAge_
    ///
    /// @param asset_   Asset in requested orientation
    /// @param quote_   Quote in requested orientation
    /// @param maxAge_  Maximum acceptable snapshot age in seconds
    /// @return stale   True when no cache exists or cache is older than maxAge_
    function isStale(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) external view returns (bool stale);
}
