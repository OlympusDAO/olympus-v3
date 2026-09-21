// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";

/// @title Price Cacher Interface
/// @notice Periodic task that refreshes an independently configured set of PriceCache pairs.
interface IPriceCacher is IPeriodicTask {
    /// @notice One asset/quote pair refreshed by the periodic task.
    /// @param asset Asset priced by the cache.
    /// @param quote Quote asset used for the cached pair.
    struct AssetPair {
        address asset;
        address quote;
    }

    /// @notice Thrown when a required address is zero.
    error PriceCacher_ZeroAddress();

    /// @notice Thrown when a candidate does not implement the required PriceCache interfaces.
    /// @param priceCache Rejected candidate.
    error PriceCacher_InvalidPriceCache(address priceCache);

    /// @notice Thrown when a candidate reports an unsupported major version.
    /// @param priceCache Rejected candidate.
    /// @param major Reported major version.
    /// @param minor Reported minor version.
    error PriceCacher_UnsupportedPriceCacheVersion(address priceCache, uint8 major, uint8 minor);

    /// @notice Thrown when a candidate belongs to another Kernel.
    /// @param expectedKernel Kernel governing PriceCacher.
    /// @param actualKernel Kernel reported by the candidate.
    error PriceCacher_PriceCacheKernelMismatch(address expectedKernel, address actualKernel);

    /// @notice Thrown when an asset pair has a zero address or identical legs.
    error PriceCacher_InvalidAssetPair();

    /// @notice Thrown when an asset pair is already configured.
    /// @param asset Asset in the duplicate pair.
    /// @param quote Quote in the duplicate pair.
    error PriceCacher_AssetPairAlreadyAdded(address asset, address quote);

    /// @notice Thrown when an asset pair is not configured.
    /// @param asset Asset in the missing pair.
    /// @param quote Quote in the missing pair.
    error PriceCacher_AssetPairNotFound(address asset, address quote);

    /// @notice Thrown when the externally callable task body is not invoked by PriceCacher itself.
    error PriceCacher_OnlySelf();

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

    /// @notice Executes the periodic cache task.
    /// @dev Returns without work while disabled or when PriceCache is inactive or disabled.
    ///      Ordinary reverts are contained, but no configurable gas limit is imposed. Gas
    ///      exhaustion can prevent later Heart work or finalization.
    function execute() external override;

    /// @notice Executes the task body through an unbounded external self-call.
    /// @dev Reverts unless called by this contract. The outer call catches ordinary failures.
    function selfExecuteTask() external;

    /// @notice Sets the PriceCache used by the task.
    /// @dev Callable only by OCG admin. The candidate must implement the required interfaces,
    ///      report major version 1, belong to the same Kernel, and support every configured
    ///      asset pair.
    function setPriceCache(address priceCache) external;

    /// @notice Adds an asset/quote pair to the periodic cache set.
    /// @dev Callable only by OCG admin while the task is enabled or disabled. Reverts for zero
    ///      addresses, an identical asset and quote, an existing pair, or a pair that the current
    ///      PriceCache cannot support.
    function addAssetPair(address asset, address quote) external;

    /// @notice Removes an asset/quote pair from the periodic cache set.
    /// @dev Callable only by OCG admin while the task is enabled or disabled. Removal may reorder
    ///      the remaining pairs and permits the configured set to become empty. A pair can be
    ///      removed even when it is no longer supported by PriceCache.
    function removeAssetPair(address asset, address quote) external;

    /// @notice Returns the configured PriceCache.
    function priceCache() external view returns (address priceCache_);

    /// @notice Returns the independently configured asset/quote pairs.
    function getAssetPairs() external view returns (AssetPair[] memory pairs);
}
