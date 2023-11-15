/// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {Category} from "src/modules/TRSRY/TRSRY.v1.sol";

interface IAppraiser {
    // ========== DATA STRUCTURES ========== //
    enum Variant {
        CURRENT,
        LAST
    }

    enum Metric {
        BACKING,
        LIQUID_BACKING,
        LIQUID_BACKING_PER_BACKED_OHM,
        MARKET_VALUE,
        MARKET_CAP,
        PREMIUM,
        THIRTY_DAY_OHM_VOLATILITY
    }

    struct Cache {
        uint256 value;
        uint48 timestamp;
    }

    //============================================================================================//
    //                                       ASSET VALUES                                         //
    //============================================================================================//

    /// @notice         Returns the current value of the holdings of `asset_`
    ///
    /// @param asset_   The address of the asset to get the value of
    /// @return         The value of the asset in the module's configured decimals
    function getAssetValue(address asset_) external view returns (uint256);

    /// @notice         Returns the current value of the holdings of `asset_`, no older than `maxAge_`
    ///
    /// @param asset_   The address of the asset to get the value of
    /// @param maxAge_  The maximum age (in seconds) of the cached value
    /// @return         The value of the asset in the module's configured decimals
    function getAssetValue(address asset_, uint48 maxAge_) external view returns (uint256);

    /// @notice         Returns the requested variant of the asset value
    ///
    /// @param asset_   The address of the asset to get the value of
    /// @param variant_ The variant of the value to return
    /// @return         The value of the asset in the module's configured decimals
    /// @return         The timestamp at which the value was calculated
    function getAssetValue(
        address asset_,
        Variant variant_
    ) external view returns (uint256, uint48);

    /// @notice             Returns the current value of the assets in `category_`
    ///
    /// @param category_    The TRSRY category to get the value of
    /// @return             The value of the assets in the category in the module's configured decimals
    function getCategoryValue(Category category_) external view returns (uint256);

    /// @notice             Returns the value of the assets in `category_`, no older than `maxAge_`
    ///
    /// @param category_    The TRSRY category to get the value of
    /// @param maxAge_      The maximum age (in seconds) of the cached value
    /// @return             The value of the assets in the category in the module's configured decimals
    function getCategoryValue(Category category_, uint48 maxAge_) external view returns (uint256);

    /// @notice             Returns the requested variant of the category value
    ///
    /// @param category_    The TRSRY category to get the value of
    /// @param variant_     The variant of the value to return
    /// @return             The value of the assets in the category in the module's configured decimals
    /// @return             The timestamp at which the value was calculated
    function getCategoryValue(
        Category category_,
        Variant variant_
    ) external view returns (uint256, uint48);

    //============================================================================================//
    //                                       VALUE METRICS                                        //
    //============================================================================================//

    /// @notice         Returns the current value of the metric
    ///
    /// @param metric_  The Metric to get the value of
    /// @return         The value of the metric in the module's configured decimals
    function getMetric(Metric metric_) external view returns (uint256);

    /// @notice         Returns a value for the metric, no older than the provided age
    ///
    /// @param metric_  The Metric to get the value of
    /// @param maxAge_  The maximum age (in seconds) of the cached value
    /// @return         The value of the metric in the module's configured decimals
    function getMetric(Metric metric_, uint48 maxAge_) external view returns (uint256);

    /// @notice         Returns the requested variant of the metric and the timestamp at which it was calculated
    ///
    /// @param metric_  The Metric to get the value of
    /// @param variant_ The variant of the value to return
    /// @return         The value of the metric in the module's configured decimals
    /// @return         The timestamp at which the value was calculated
    function getMetric(Metric metric_, Variant variant_) external view returns (uint256, uint48);

    //============================================================================================//
    //                                       CACHING                                              //
    //============================================================================================//

    /// @notice         Caches the current value of `asset_` holdings
    ///
    /// @param asset_   The address of the asset
    function storeAssetValue(address asset_) external;

    /// @notice             Caches the current value of asset holdings in `category_`
    ///
    /// @param category_    The TRSRY category
    function storeCategoryValue(Category category_) external;

    /// @notice         Caches the current value of the metric
    ///
    /// @param metric_  The Metric to cache the value of
    function storeMetric(Metric metric_) external;
}
