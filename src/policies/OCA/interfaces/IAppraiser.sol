/// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {Category} from "src/modules/TRSRY/TRSRY.v1.sol";

interface IAppraiser {
    // ========== DATA STRUCTURES ========== //
    enum Variant {
        CURRENT,
        LAST,
        MOVINGAVERAGE
    }

    enum Metric {
        BACKING,
        LIQUID_BACKING,
        LIQUID_BACKING_PER_BACKED_OHM,
        MARKET_VALUE,
        MARKET_CAP,
        PREMIUM
    }

    struct Cache {
        uint256 value;
        uint48 timestamp;
    }

    struct MovingAverage {
        uint32 movingAverageDuration; // the duration of the moving average
        uint16 nextObsIndex; // the index of obs at which the next observation will be stored
        uint16 numObservations;
        uint48 lastObservationTime;
        uint256 cumulativeObs;
        uint256[] obs;
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

    //============================================================================================//
    //                                       MOVING AVERAGES                                      //
    //============================================================================================//

    /// @notice         Updates the configuration for an asset value moving average
    ///
    /// @param asset_   The address of the asset to update the moving average configuration for
    /// @param movingAverageDuration_ The duration of the moving average
    /// @param lastObservationTime_ The timestamp of the last observation
    /// @param observations_ The observations to set
    function updateAssetMovingAverage(
        address asset_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external;

    /// @notice         Stores observation for asset value moving average
    ///
    /// @param asset_   The address of the asset to store the observation for
    function storeAssetObservation(address asset_) external;

    /// @notice         Gets the moving average configuration for an asset
    ///
    /// @param asset_   The address of the asset to get the moving average configuration for
    /// @return         The moving average configuration
    function getAssetMovingAverageData(address asset_) external view returns (MovingAverage memory);

    /// @notice         Updates the configuration for a category value moving average
    ///
    /// @param category_   The category to update the moving average configuration for
    /// @param movingAverageDuration_ The duration of the moving average
    /// @param lastObservationTime_ The timestamp of the last observation
    /// @param observations_ The observations to set
    function updateCategoryMovingAverage(
        Category category_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external;

    /// @notice             Stores observation for category value moving average
    ///
    /// @param category_    The TRSRY category to store the observation for
    function storeCategoryObservation(Category category_) external;

    /// @notice         Gets the moving average configuration for a category
    ///
    /// @param category_   The category to get the moving average configuration for
    /// @return         The moving average configuration
    function getCategoryMovingAverageData(
        Category category_
    ) external view returns (MovingAverage memory);

    /// @notice         Updates the configuration for a metric value moving average
    ///
    /// @param metric_   The metric to update the moving average configuration for
    /// @param movingAverageDuration_ The duration of the moving average
    /// @param lastObservationTime_ The timestamp of the last observation
    /// @param observations_ The observations to set
    function updateMetricMovingAverage(
        Metric metric_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external;

    /// @notice         Stores observation for metric moving average
    ///
    /// @param metric_ The Metric to store the observation for
    function storeMetricObservation(Metric metric_) external;

    /// @notice         Gets the moving average configuration for a metric
    ///
    /// @param metric_   The metric to get the moving average configuration for
    /// @return         The moving average configuration
    function getMetricMovingAverageData(
        Metric metric_
    ) external view returns (MovingAverage memory);

    /// @notice         Gets the observation frequency for the moving average
    ///
    /// @return         uint32      The observation frequency
    function getObservationFrequency() external view returns (uint32);
}
