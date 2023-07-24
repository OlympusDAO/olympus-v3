/// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {Category} from "src/modules/TRSRY/TRSRY.v1.sol";

interface IValuation {
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

    function getAssetValue(address asset_) external view returns (uint256);

    function getAssetValue(address asset_, uint48 maxAge_) external view returns (uint256);

    function getAssetValue(
        address asset_,
        Variant variant_
    ) external view returns (uint256, uint48);

    function getCategoryValue(Category category_) external view returns (uint256);

    function getCategoryValue(Category category_, uint48 maxAge_) external view returns (uint256);

    function getCategoryValue(
        Category category_,
        Variant variant_
    ) external view returns (uint256, uint48);

    //============================================================================================//
    //                                       VALUE METRICS                                        //
    //============================================================================================//

    /// @notice Returns the current value of the metric
    /// @dev Optimistically uses the cached value if it has been updated this block, otherwise calculates value dynamically
    function getMetric(Metric metric_) external view returns (uint256);

    /// @notice Returns a value no older than the provided age
    function getMetric(Metric metric_, uint48 maxAge_) external view returns (uint256);

    /// @notice Returns the requested variant of the metric and the timestamp at which it was calculated
    function getMetric(Metric metric_, Variant variant_) external view returns (uint256, uint48);

    //============================================================================================//
    //                                       CACHING                                              //
    //============================================================================================//

    function storeAssetValue(address asset_) external;

    function storeCategoryValue(Category category_) external;

    function storeMetric(Metric metric_) external;
}
