// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Price Cacher Task Interface
/// @notice Periodic task that refreshes an independently configured set of PriceCache pairs.
interface IPriceCacherTask {
    // ========== EVENTS ========== //

    /// @notice Emitted when the task's PriceCache dependency changes.
    /// @param priceCache New PriceCache address.
    event PriceCacheSet(address indexed priceCache);

    /// @notice Emitted when the aggregate self-call fails.
    /// @param reason First four bytes of the revert data.
    event ExecutionFailed(bytes4 reason);

    /// @notice Emitted when one configured pair cannot be refreshed.
    /// @param priceCache PriceCache used for the attempt.
    /// @param asset Asset in the failed pair.
    /// @param quote Quote in the failed pair.
    /// @param reason First four bytes of the revert data.
    event PairCacheFailed(
        address indexed priceCache,
        address indexed asset,
        address indexed quote,
        bytes4 reason
    );

    /// @notice Emitted when an asset pair is added.
    /// @param asset Asset in the added pair.
    /// @param quote Quote in the added pair.
    event AssetPairAdded(address indexed asset, address indexed quote);

    /// @notice Emitted when an asset pair is removed.
    /// @param asset Asset in the removed pair.
    /// @param quote Quote in the removed pair.
    event AssetPairRemoved(address indexed asset, address indexed quote);

    // ========== ERRORS ========== //

    /// @notice Lifecycle payloads must be empty.
    error PriceCacherTask_InvalidData();

    /// @notice Thrown when a required address is zero.
    error PriceCacherTask_ZeroAddress();

    /// @notice Thrown when the requested cache is already selected.
    /// @param priceCache Unchanged cache address.
    error PriceCacherTask_UnchangedAddress(address priceCache);

    /// @notice Thrown when a candidate does not implement the required PriceCache interfaces.
    /// @param priceCache Rejected candidate.
    error PriceCacherTask_InvalidPriceCache(address priceCache);

    /// @notice Thrown when an asset pair has a zero address or identical legs.
    error PriceCacherTask_InvalidAssetPair();

    /// @notice Thrown when an asset pair is already configured.
    /// @param asset Asset in the duplicate pair.
    /// @param quote Quote in the duplicate pair.
    error PriceCacherTask_AssetPairAlreadyAdded(address asset, address quote);

    /// @notice Thrown when an asset pair is not configured.
    /// @param asset Asset in the missing pair.
    /// @param quote Quote in the missing pair.
    error PriceCacherTask_AssetPairNotFound(address asset, address quote);

    /// @notice Thrown when the externally callable task body is not invoked by PriceCacherTask itself.
    error PriceCacherTask_OnlySelf();

    /// @notice This policy must be Kernel-active.
    /// @param policy Inactive policy.
    error PriceCacherTask_PolicyInactive(address policy);

    // ========== STRUCTS ========== //

    /// @notice One asset/quote pair refreshed by the periodic task.
    /// @param asset Asset priced by the cache.
    /// @param quote Quote asset used for the cached pair.
    struct AssetPair {
        address asset;
        address quote;
    }

    // ========== FUNCTIONS ========== //

    /// @notice Sets the PriceCache used by the task.
    /// @dev Callable only by OCG admin. The candidate must implement the required interfaces,
    ///      belong to the same Kernel, and support every configured asset pair.
    function setPriceCache(address priceCache) external;

    /// @notice Adds an asset/quote pair to the periodic cache set.
    /// @dev Callable by price_admin or OCG admin while the task is enabled or disabled.
    function addAssetPair(address asset, address quote) external;

    /// @notice Removes an asset/quote pair from the periodic cache set.
    /// @dev Callable by price_admin or OCG admin while the task is enabled or disabled. Removal may reorder
    ///      the remaining pairs and permits the configured set to become empty. A pair can be
    ///      removed even when it is no longer supported by PriceCache.
    function removeAssetPair(address asset, address quote) external;

    /// @notice Returns the configured PriceCache.
    function priceCache() external view returns (address priceCache_);

    /// @notice Returns the independently configured asset/quote pairs.
    function getAssetPairs() external view returns (AssetPair[] memory pairs);
}
