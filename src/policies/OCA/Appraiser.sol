/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import "src/Kernel.sol";
import {IAppraiser} from "src/policies/OCA/interfaces/IAppraiser.sol";
import {ROLESv1, RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import {TRSRYv1_1, Category as TreasuryCategory, toCategory as toTreasuryCategory} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {SPPLYv1, toCategory as toSupplyCategory} from "src/modules/SPPLY/SPPLY.v1.sol";

/// @title      Appraiser
/// @notice     The Appraiser contract calculates and stores the value of assets, treasury categories, and value metrics.
/// @dev        This contract defines the following roles:
///             - appraiser_admin: The role that can update moving averages
///             - appraiser_store: The role that can store observations
contract Appraiser is IAppraiser, Policy, RolesConsumer {
    using FixedPointMathLib for uint256;

    // ========== EVENTS ========== //

    event AssetObservation(address indexed asset, uint256 value, uint48 timestamp);
    event CategoryObservation(TreasuryCategory indexed category, uint256 value, uint48 timestamp);
    event MetricObservation(Metric indexed metric, uint256 value, uint48 timestamp);

    // ========== ERRORS ========== //

    /// @notice                 Indicates that the value of `asset_` could not be calculated
    ///
    /// @param asset_           The address of the asset that could not be valued
    error Appraiser_ValueCallFailed(address asset_);

    /// @notice                 Indicates that the value of `asset_` is zero
    ///
    /// @param asset_           The address of the asset that has a value of zero
    error Appraiser_ValueZero(address asset_);

    /// @notice                 Indicates that invalid parameters were provided
    ///
    /// @param index            The index of the invalid parameter
    /// @param params           The parameters that were provided
    error Appraiser_InvalidParams(uint256 index, bytes params);

    /// @notice                 Indicates an invalid lastObservationTime when updating an asset value moving average
    ///
    /// @param asset_           The address of the asset that was observed
    /// @param lastObservationTime_  The timestamp of the last observation
    /// @param blockTimestamp_   The current block timestamp
    error Appraiser_ParamsLastObservationTimeInvalid_Asset(
        address asset_,
        uint48 lastObservationTime_,
        uint48 blockTimestamp_
    );

    /// @notice                 Indicates an invalid moving average duration when updating an asset value moving average
    ///
    /// @param asset_           The address of the asset that was observed
    /// @param movingAverageDuration_  The moving average duration
    /// @param observationFrequency_  The observation frequency
    error Appraiser_ParamsMovingAverageDurationInvalid_Asset(
        address asset_,
        uint32 movingAverageDuration_,
        uint32 observationFrequency_
    );

    /// @notice                 Indicates an invalid observation count when updating an asset value moving average
    ///
    /// @param asset_           The address of the asset that was observed
    /// @param observationCount_  The number of observations provided
    /// @param numObservations_  The number of observations expected
    error Appraiser_ParamsInvalidObservationCount_Asset(
        address asset_,
        uint256 observationCount_,
        uint256 numObservations_
    );

    /// @notice                 Indicates an invalid observation when updating an asset value moving average
    ///
    /// @param asset_           The address of the asset that was observed
    /// @param index_           The index of the invalid observation
    error Appraiser_ParamsObservationZero_Asset(address asset_, uint256 index_);

    /// @notice                 Indicates that insufficient time has elapsed since the last asset value observation
    ///
    /// @param asset_           The address of the asset that was observed
    /// @param lastObservation_  The timestamp of the last observation
    error Appraiser_InsufficientTimeElapsed_Asset(address asset_, uint48 lastObservation_);

    /// @notice                 Indicates an invalid lastObservationTime when updating a category value moving average
    ///
    /// @param category_           The category that was observed
    /// @param lastObservationTime_  The timestamp of the last observation
    /// @param blockTimestamp_   The current block timestamp
    error Appraiser_ParamsLastObservationTimeInvalid_Category(
        TreasuryCategory category_,
        uint48 lastObservationTime_,
        uint48 blockTimestamp_
    );

    /// @notice                 Indicates an invalid moving average duration when updating a category value moving average
    ///
    /// @param category_           The category that was observed
    /// @param movingAverageDuration_  The moving average duration
    /// @param observationFrequency_  The observation frequency
    error Appraiser_ParamsMovingAverageDurationInvalid_Category(
        TreasuryCategory category_,
        uint32 movingAverageDuration_,
        uint32 observationFrequency_
    );

    /// @notice                 Indicates an invalid observation count when updating a category value moving average
    ///
    /// @param category_           The category that was observed
    /// @param observationCount_  The number of observations provided
    /// @param numObservations_  The number of observations expected
    error Appraiser_ParamsInvalidObservationCount_Category(
        TreasuryCategory category_,
        uint256 observationCount_,
        uint256 numObservations_
    );

    /// @notice                 Indicates an invalid observation when updating a category value moving average
    ///
    /// @param category_           The category that was observed
    /// @param index_           The index of the invalid observation
    error Appraiser_ParamsObservationZero_Category(TreasuryCategory category_, uint256 index_);

    /// @notice                 Indicates that insufficient time has elapsed since the last treasury category value observation
    ///
    /// @param category_        The treasury category that was observed
    /// @param lastObservation_  The timestamp of the last observation
    error Appraiser_InsufficientTimeElapsed_Category(
        TreasuryCategory category_,
        uint48 lastObservation_
    );

    /// @notice                 Indicates an invalid lastObservationTime when updating a metric value moving average
    ///
    /// @param metric_           The metric that was observed
    /// @param lastObservationTime_  The timestamp of the last observation
    /// @param blockTimestamp_   The current block timestamp
    error Appraiser_ParamsLastObservationTimeInvalid_Metric(
        Metric metric_,
        uint48 lastObservationTime_,
        uint48 blockTimestamp_
    );

    /// @notice                 Indicates an invalid moving average duration when updating a metric value moving average
    ///
    /// @param metric_           The metric that was observed
    /// @param movingAverageDuration_  The moving average duration
    /// @param observationFrequency_  The observation frequency
    error Appraiser_ParamsMovingAverageDurationInvalid_Metric(
        Metric metric_,
        uint32 movingAverageDuration_,
        uint32 observationFrequency_
    );

    /// @notice                 Indicates an invalid observation count when updating a metric value moving average
    ///
    /// @param metric_           The metric that was observed
    /// @param observationCount_  The number of observations provided
    /// @param numObservations_  The number of observations expected
    error Appraiser_ParamsInvalidObservationCount_Metric(
        Metric metric_,
        uint256 observationCount_,
        uint256 numObservations_
    );

    /// @notice                 Indicates an invalid observation when updating a metric value moving average
    ///
    /// @param metric_           The metric that was observed
    /// @param index_           The index of the invalid observation
    error Appraiser_ParamsObservationZero_Metric(Metric metric_, uint256 index_);

    /// @notice                 Indicates that insufficient time has elapsed since the last metric observation
    ///
    /// @param metric_          The metric that was observed
    /// @param lastObservation_  The timestamp of the last observation
    error Appraiser_InsufficientTimeElapsed_Metric(Metric metric_, uint48 lastObservation_);

    // ========== STATE ========== //

    // Modules
    TRSRYv1_1 internal TRSRY;
    SPPLYv1 internal SPPLY;
    PRICEv2 internal PRICE;

    // Storage of protocol variables to avoid extra external calls
    address internal ohm;
    address internal gohm;
    uint256 internal constant OHM_SCALE = 1e9;
    uint256 internal priceScale;
    uint32 public observationFrequency;
    uint8 public decimals;

    // Cache
    mapping(Metric => Cache) public metricCache;
    mapping(address => Cache) public assetValueCache;
    mapping(TreasuryCategory => Cache) public categoryValueCache;

    // Moving Averages
    mapping(Metric => MovingAverage) public metricMovingAverage;
    mapping(address => MovingAverage) public assetValueMovingAverage;
    mapping(TreasuryCategory => MovingAverage) public categoryValueMovingAverage;

    //============================================================================================//
    //                                     POLICY SETUP                                           //
    //============================================================================================//

    constructor(Kernel kernel_, uint32 observationFrequency_) Policy(kernel_) {
        observationFrequency = observationFrequency_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("PRICE");
        dependencies[1] = toKeycode("SPPLY");
        dependencies[2] = toKeycode("TRSRY");
        dependencies[3] = toKeycode("ROLES");

        PRICE = PRICEv2(getModuleAddress(dependencies[0]));
        SPPLY = SPPLYv1(getModuleAddress(dependencies[1]));
        TRSRY = TRSRYv1_1(getModuleAddress(dependencies[2]));
        ROLES = ROLESv1(getModuleAddress(dependencies[3]));

        (uint8 PRICE_MAJOR, ) = PRICE.VERSION();
        (uint8 SPPLY_MAJOR, ) = SPPLY.VERSION();
        (uint8 TRSRY_MAJOR, uint8 TRSRY_MINOR) = TRSRY.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([2, 1, 1]);
        if (PRICE_MAJOR != 2 || SPPLY_MAJOR != 1 || TRSRY_MAJOR != 1 || ROLES_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Check TRSRY minor version
        if (TRSRY_MINOR < 1) revert Policy_WrongModuleVersion(expected);

        ohm = address(SPPLY.ohm());
        gohm = address(SPPLY.gohm());
        decimals = PRICE.decimals();
        priceScale = 10 ** decimals;
    }

    /// @notice     Returns the current version of the policy
    /// @dev        This is useful for distinguishing between different versions of the policy
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       ASSET VALUES                                         //
    //============================================================================================//

    /// @inheritdoc IAppraiser
    function getAssetValue(address asset_) external view override returns (uint256) {
        // Get the cached asset value
        (uint256 value, uint48 timestamp) = getAssetValue(asset_, Variant.LAST);

        // Try to use the last value, must be updated on the current timestamp
        if (timestamp == uint48(block.timestamp)) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getAssetValue(asset_, Variant.CURRENT);

        return value;
    }

    /// @inheritdoc IAppraiser
    /// @dev        Will revert if:
    /// @dev        - The max age is greater than the current timestamp
    function getAssetValue(
        address asset_,
        uint48 maxAge_
    ) external view override returns (uint256) {
        // Check that max age is valid
        if (maxAge_ >= uint48(block.timestamp))
            revert Appraiser_InvalidParams(1, abi.encode(maxAge_));

        // Get the cached asset value
        (uint256 value, uint48 timestamp) = getAssetValue(asset_, Variant.LAST);

        // Try to use the last value, must be no older than maxAge_
        if (timestamp >= uint48(block.timestamp) - maxAge_) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getAssetValue(asset_, Variant.CURRENT);

        return value;
    }

    /// @inheritdoc IAppraiser
    function getAssetValue(
        address asset_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        if (variant_ == Variant.LAST) {
            return (assetValueCache[asset_].value, assetValueCache[asset_].timestamp);
        } else if (variant_ == Variant.CURRENT) {
            return _assetValue(asset_, false);
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            return _assetMovingAverage(asset_);
        } else {
            revert Appraiser_InvalidParams(1, abi.encode(variant_));
        }
    }

    /// @notice             Calculates the value of the protocols holdings of `asset_`
    ///
    /// @param asset_       The address of the asset to get the value of
    /// @param excludeOhm_  Whether to exclude OHM from the value calculation
    /// @return             uint256     The value of the asset (in terms of `decimals`)
    /// @return             uint48      The timestamp at which the value was calculated
    function _assetValue(address asset_, bool excludeOhm_) internal view returns (uint256, uint48) {
        if (excludeOhm_ == true && (asset_ == ohm || asset_ == gohm)) {
            return (0, uint48(block.timestamp));
        }

        // Get current asset price, should be in price decimals configured on PRICE
        (uint256 price, ) = PRICE.getPrice(asset_, PRICEv2.Variant.CURRENT);

        // Get current asset balance, should be in the decimals of the asset
        (uint256 balance, ) = TRSRY.getAssetBalance(asset_, TRSRYv1_1.Variant.CURRENT);

        // Calculate the value of the protocols holdings of the asset
        uint256 value = price.mulDivDown(balance, 10 ** ERC20(asset_).decimals());

        return (value, uint48(block.timestamp));
    }

    /// @notice         Calculates the moving average of protocol holdings of `asset_`
    ///
    /// @param asset_   The address of the asset to get the value of
    /// @return         The moving average of the asset (in terms of `decimals`)
    /// @return         The last observation timestamp
    function _assetMovingAverage(address asset_) internal view returns (uint256, uint48) {
        // Load asset data
        MovingAverage storage assetMA = assetValueMovingAverage[asset_];

        // Calculate moving average
        uint256 movingAverage = assetMA.cumulativeObs / assetMA.numObservations;

        // Return moving average and time
        return (movingAverage, assetMA.lastObservationTime);
    }

    /// @inheritdoc IAppraiser
    function getCategoryValue(TreasuryCategory category_) external view override returns (uint256) {
        // Get the cached category value
        (uint256 value, uint48 timestamp) = getCategoryValue(category_, Variant.LAST);

        // Try to use the last value, must be updated on the current timestamp
        if (timestamp == uint48(block.timestamp)) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getCategoryValue(category_, Variant.CURRENT);

        return value;
    }

    /// @inheritdoc IAppraiser
    /// @dev        Will revert if:
    /// @dev        - The max age is greater than the current timestamp
    function getCategoryValue(
        TreasuryCategory category_,
        uint48 maxAge_
    ) external view override returns (uint256) {
        // Check that max age is valid
        if (maxAge_ >= uint48(block.timestamp))
            revert Appraiser_InvalidParams(1, abi.encode(maxAge_));

        // Get the cached category value
        (uint256 value, uint48 timestamp) = getCategoryValue(category_, Variant.LAST);

        // Try to use the last value, must be no older than maxAge_
        if (timestamp >= uint48(block.timestamp) - maxAge_) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getCategoryValue(category_, Variant.CURRENT);

        return value;
    }

    /// @inheritdoc IAppraiser
    function getCategoryValue(
        TreasuryCategory category_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        if (variant_ == Variant.LAST) {
            return (categoryValueCache[category_].value, categoryValueCache[category_].timestamp);
        } else if (variant_ == Variant.CURRENT) {
            return _categoryValue(category_, false);
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            return _categoryMovingAverage(category_);
        } else {
            revert Appraiser_InvalidParams(1, abi.encode(variant_));
        }
    }

    /// @notice             Calculates the value of the asset holdings in `category_`
    ///
    /// @param category_    The TRSRY category to get the value of
    /// @param excludeOhm_  Whether to exclude OHM from the value calculation
    /// @return             The value of the assets in the category (in terms of `decimals`)
    /// @return             The timestamp at which the value was calculated
    function _categoryValue(
        TreasuryCategory category_,
        bool excludeOhm_
    ) internal view returns (uint256, uint48) {
        // Get the assets in the category
        address[] memory assets = TRSRY.getAssetsByCategory(category_);

        // Get the value of each asset in the category
        uint256 value;
        uint256 len = assets.length;
        for (uint256 i; i < len; ) {
            (uint256 assetValue, ) = _assetValue(assets[i], excludeOhm_);
            value += assetValue;
            unchecked {
                ++i;
            }
        }

        return (value, uint48(block.timestamp));
    }

    /// @notice             Calculates the moving average of the asset holdings in `category_`
    ///
    /// @param category_    The TRSRY category to get the value of
    /// @return             The moving average of the assets in the category (in terms of `decimals`)
    /// @return             The last observation timestamp
    function _categoryMovingAverage(
        TreasuryCategory category_
    ) internal view returns (uint256, uint48) {
        // Load category data
        MovingAverage storage categoryMA = categoryValueMovingAverage[category_];

        // Calculate moving average
        uint256 movingAverage = categoryMA.cumulativeObs / categoryMA.numObservations;

        // Return moving average and time
        return (movingAverage, categoryMA.lastObservationTime);
    }

    //============================================================================================//
    //                                       VALUE METRICS                                        //
    //============================================================================================//

    /// @inheritdoc IAppraiser
    /// @dev        Optimistically uses the cached value if it has been updated this block, otherwise calculates value dynamically
    function getMetric(Metric metric_) external view override returns (uint256) {
        // Get the cached value of the metric
        (uint256 value, uint48 timestamp) = getMetric(metric_, Variant.LAST);

        // Try to use the last value, must be updated on the current timestamp
        if (timestamp == uint48(block.timestamp)) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getMetric(metric_, Variant.CURRENT);

        return value;
    }

    /// @inheritdoc IAppraiser
    /// @dev        Will revert if:
    /// @dev        - The max age is greater than the current timestamp
    function getMetric(Metric metric_, uint48 maxAge_) external view override returns (uint256) {
        // Check that max age is valid
        if (maxAge_ >= uint48(block.timestamp))
            revert Appraiser_InvalidParams(1, abi.encode(maxAge_));

        // Get the cached value of the metric
        (uint256 value, uint48 timestamp) = getMetric(metric_, Variant.LAST);

        // Try to use the last value, must be no older than maxAge_
        if (timestamp >= uint48(block.timestamp) - maxAge_) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getMetric(metric_, Variant.CURRENT);

        return value;
    }

    /// @inheritdoc IAppraiser
    function getMetric(
        Metric metric_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        if (variant_ == Variant.LAST) {
            return (metricCache[metric_].value, metricCache[metric_].timestamp);
        } else if (variant_ == Variant.CURRENT) {
            if (metric_ == Metric.BACKING) {
                return (_backing(), uint48(block.timestamp));
            } else if (metric_ == Metric.LIQUID_BACKING) {
                return (_liquidBacking(), uint48(block.timestamp));
            } else if (metric_ == Metric.LIQUID_BACKING_PER_BACKED_OHM) {
                return (_liquidBackingPerBackedOhm(), uint48(block.timestamp));
            } else if (metric_ == Metric.MARKET_VALUE) {
                return (_marketValue(), uint48(block.timestamp));
            } else if (metric_ == Metric.MARKET_CAP) {
                return (_marketCap(), uint48(block.timestamp));
            } else if (metric_ == Metric.PREMIUM) {
                return (_premium(), uint48(block.timestamp));
            } else if (metric_ == Metric.THIRTY_DAY_OHM_VOLATILITY) {
                return (_thirtyDayOhmVolatility(), uint48(block.timestamp));
            } else {
                revert Appraiser_InvalidParams(0, abi.encode(metric_));
            }
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            return _metricMovingAverage(metric_);
        } else {
            revert Appraiser_InvalidParams(1, abi.encode(variant_));
        }
    }

    /// @notice         Calculates the moving average value of a metric
    ///
    /// @param metric_  The metric to get the value of
    /// @return         The moving average of the metric (in terms of `decimals`)
    /// @return         The last observation timestamp
    function _metricMovingAverage(Metric metric_) internal view returns (uint256, uint48) {
        // Load metric data
        MovingAverage storage metricMA = metricMovingAverage[metric_];

        // Calculate moving average
        uint256 movingAverage = metricMA.cumulativeObs / metricMA.numObservations;

        // Return moving average and time
        return (movingAverage, metricMA.lastObservationTime);
    }

    /// @notice         Calculates the value of backing
    /// @notice         Backing is defined as:
    /// @notice         - The market value of all assets owned by the protocol
    /// @notice         - Excluding: OHM held by the protocol
    /// @notice         - Excluding: OHM in protocol-owned liquidity
    ///
    /// @return         The value of the protocol backing (in terms of `decimals`)
    function _backing() internal view returns (uint256) {
        // Get list of assets owned by the protocol
        address[] memory assets = TRSRY.getAssets();

        // Get the addresses of POL assets in the treasury
        address[] memory polAssets = TRSRY.getAssetsByCategory(
            toTreasuryCategory("protocol-owned-liquidity")
        );

        // Calculate the value of all the non-POL assets
        uint256 value;
        uint256 len = assets.length;
        for (uint256 i; i < len; ) {
            if (assets[i] != ohm && assets[i] != gohm) {
                (uint256 assetValue, ) = _assetValue(assets[i], true);
                if (!_inArray(assets[i], polAssets)) {
                    value += assetValue;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Get the POL reserves from the SPPLY module
        SPPLYv1.Reserves[] memory reserves = SPPLY.getReservesByCategory(
            toSupplyCategory("protocol-owned-liquidity")
        );

        len = reserves.length;
        for (uint256 i; i < len; ) {
            uint256 tokens = reserves[i].tokens.length;
            for (uint256 j; j < tokens; ) {
                if (reserves[i].tokens[j] != ohm && reserves[i].tokens[j] != gohm) {
                    // Get current asset price
                    (uint256 price, ) = PRICE.getPrice(
                        reserves[i].tokens[j],
                        PRICEv2.Variant.CURRENT
                    );
                    // Calculate current asset valuation
                    value += price.mulDivDown(
                        reserves[i].balances[j],
                        10 ** ERC20(reserves[i].tokens[j]).decimals()
                    );
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
        return value;
    }

    /// @notice         Calculates the value of liquid backing
    /// @notice         Liquid backing is defined as:
    /// @notice         - Backing
    /// @notice         - Excluding: illiquid assets
    ///
    /// @return         The value of liquid backing (in terms of `decimals`)
    function _liquidBacking() internal view returns (uint256) {
        // Get total backing
        uint256 backing = _backing();

        // Get value of assets categorized as illiquid
        (uint256 illiquidValue, ) = _categoryValue(toTreasuryCategory("illiquid"), true);

        // Subtract illiquid value from total backing
        return backing - illiquidValue;
    }

    /// @notice         Calculates the value of liquid backing per backed OHM (LBBO)
    /// @notice         LBBO is defined as:
    /// @notice         - Liquid backing
    /// @notice         - Divided by: OHM backed supply
    ///
    /// @return         The value of LBBO (in terms of `decimals`)
    function _liquidBackingPerBackedOhm() internal view returns (uint256) {
        // Get liquid backing
        uint256 liquidBacking = _liquidBacking();

        // Get supply of backed ohm (in OHM decimals)
        (uint256 backedSupply, ) = SPPLY.getMetric(
            SPPLYv1.Metric.BACKED_SUPPLY,
            SPPLYv1.Variant.CURRENT
        );

        // Divide liquid backing by backed supply
        // and correct scale
        return liquidBacking.mulDivDown(priceScale, backedSupply) / OHM_SCALE;
    }

    /// @notice         Calculates the market value of the treasury
    /// @notice         Market value is defined as:
    /// @notice         - The market value of all assets owned by the protocol
    /// @notice         - Excluding: OHM held by the protocol
    /// @notice         - Including: OHM in protocol-owned liquidity
    ///
    /// @return         The market value (in terms of `decimals`)
    function _marketValue() internal view returns (uint256) {
        // Get list of assets owned by the protocol
        address[] memory assets = TRSRY.getAssets();

        // Get the value of each asset
        uint256 value;
        uint256 len = assets.length;
        for (uint256 i; i < len; ) {
            (uint256 assetValue, ) = _assetValue(assets[i], false);
            value += assetValue;
            unchecked {
                ++i;
            }
        }

        return value;
    }

    /// @notice         Calculates the market cap of OHM
    /// @notice         Market cap is defined as:
    /// @notice         - The circulating supply of OHM
    /// @notice         - Multiplied by: The price of OHM
    ///
    /// @return         The market cap (in terms of `decimals`)
    function _marketCap() internal view returns (uint256) {
        // Get supply of ohm (in OHM decimals)
        (uint256 supply, ) = SPPLY.getMetric(
            SPPLYv1.Metric.CIRCULATING_SUPPLY,
            SPPLYv1.Variant.CURRENT
        );

        // Get price of ohm
        (uint256 price, ) = PRICE.getPrice(ohm, PRICEv2.Variant.CURRENT);

        // Multiply supply by price
        // and correct scale
        return supply.mulDivDown(price, OHM_SCALE);
    }

    /// @notice         Calculates the premium of OHM
    /// @notice         Premium is defined as:
    /// @notice         - The market cap of OHM
    /// @notice         - Divided by: The market value of the treasury
    ///
    /// @return         The premium (in terms of `decimals`)
    function _premium() internal view returns (uint256) {
        // Get market cap of OHM
        uint256 marketCap = _marketCap();

        // Get market value of treasury
        uint256 marketValue = _marketValue();

        // Divide market cap by market value of treasury
        return marketCap.mulDivDown(priceScale, marketValue);
    }

    /// @notice         Calculates the 30 day volatility of OHM
    /// @notice         Volatility is defined as:
    /// @notice         - The standard deviation of the percent change in price over the last 30 days
    ///
    /// @return         The 30 day volatility (in terms of `decimals`)
    function _thirtyDayOhmVolatility() internal view returns (uint256) {
        // Get OHM price data from price module
        PRICEv2.Asset memory data = PRICE.getAssetData(ohm);

        // Check that the number of observations (90) and duration (30 days) is correct (30 days, 8 hour increments)
        if (
            !data.storeMovingAverage ||
            data.numObservations != 90 ||
            data.movingAverageDuration != uint32(30 days)
        ) {
            revert Appraiser_ValueCallFailed(ohm);
        }

        // Calculate percent changes for each observation to the next
        uint256 len = data.numObservations - 1;
        uint256[] memory changes = new uint256[](len);
        uint256 sum; // used for mean calculation
        for (uint256 i; i < len; i++) {
            uint256 obsIndex = (data.nextObsIndex + i) % data.numObservations;
            changes[i] =
                (data.obs[(obsIndex + 1) % data.numObservations] * priceScale) /
                data.obs[obsIndex];
            sum += changes[i];
        }

        // Calculate mean of percent changes
        uint256 meanChange = sum / len;

        // Calculate standard deviation of percent changes
        uint256 stdDev;
        for (uint256 i; i < len; i++) {
            if (changes[i] >= meanChange) {
                stdDev += ((changes[i] - meanChange) ** 2);
            } else {
                stdDev += ((meanChange - changes[i]) ** 2);
            }
        }
        stdDev = FixedPointMathLib.sqrt(stdDev / len);

        // Calculate and return annual volatility
        return stdDev * 33; // annual std dev = period std dev * sqrt(periods per year), in this case there are 365 * 3 = 1095 periods per year. sqrt(1095) = 33.097...
    }

    //============================================================================================//
    //                                       CACHING                                              //
    //============================================================================================//

    /// @inheritdoc IAppraiser
    /// @dev        Gated to prevent manipulation of the cached value
    function storeAssetValue(address asset_) external override onlyRole("appraiser_store") {
        (uint256 value, uint48 timestamp) = getAssetValue(asset_, Variant.CURRENT);
        assetValueCache[asset_] = Cache(value, timestamp);
    }

    /// @inheritdoc IAppraiser
    /// @dev        Gated to prevent manipulation of the cached value
    function storeCategoryValue(
        TreasuryCategory category_
    ) external override onlyRole("appraiser_store") {
        (uint256 value, uint48 timestamp) = getCategoryValue(category_, Variant.CURRENT);
        categoryValueCache[category_] = Cache(value, timestamp);
    }

    /// @inheritdoc IAppraiser
    /// @dev        Gated to prevent manipulation of the cached value
    function storeMetric(Metric metric_) external override onlyRole("appraiser_store") {
        (uint256 result, uint48 timestamp) = getMetric(metric_, Variant.CURRENT);
        metricCache[metric_] = Cache(result, timestamp);
    }

    //============================================================================================//
    //                                       MOVING AVERAGES                                      //
    //============================================================================================//

    /// @inheritdoc IAppraiser
    function updateAssetMovingAverage(
        address asset_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external override onlyRole("appraiser_admin") {
        MovingAverage storage assetMA = assetValueMovingAverage[asset_];

        // Remove existing data, if any
        if (assetMA.obs.length > 0) delete assetMA.obs;

        // Ensure last observation time is not in the future
        if (lastObservationTime_ > block.timestamp)
            revert Appraiser_ParamsLastObservationTimeInvalid_Asset(
                asset_,
                lastObservationTime_,
                uint48(block.timestamp)
            );

        // Validate moving average parameters
        if (movingAverageDuration_ == 0 || movingAverageDuration_ % observationFrequency != 0)
            revert Appraiser_ParamsMovingAverageDurationInvalid_Asset(
                asset_,
                movingAverageDuration_,
                observationFrequency
            );

        uint16 numObservations = uint16(movingAverageDuration_ / observationFrequency);
        if (observations_.length != numObservations || numObservations < 2)
            revert Appraiser_ParamsInvalidObservationCount_Asset(
                asset_,
                observations_.length,
                numObservations
            );

        // Set moving average parameters
        assetMA.movingAverageDuration = movingAverageDuration_;
        assetMA.nextObsIndex = 0;
        assetMA.numObservations = numObservations;
        assetMA.lastObservationTime = lastObservationTime_;
        assetMA.cumulativeObs = 0; // reset to zero before adding new observations
        for (uint256 i; i < numObservations; ) {
            if (observations_[i] == 0) revert Appraiser_ParamsObservationZero_Asset(asset_, i);

            assetMA.cumulativeObs += observations_[i];
            assetMA.obs.push(observations_[i]);
            unchecked {
                ++i;
            }
        }

        // Emit stored event for the new cached value
        emit AssetObservation(asset_, observations_[numObservations - 1], lastObservationTime_);
    }

    /// @inheritdoc IAppraiser
    function storeAssetObservation(address asset_) external override onlyRole("appraiser_store") {
        MovingAverage storage assetMA = assetValueMovingAverage[asset_];

        // Check that sufficient time has passed to record a new observation
        uint48 lastObservationTime = assetMA.lastObservationTime;
        if (lastObservationTime + observationFrequency > block.timestamp)
            revert Appraiser_InsufficientTimeElapsed_Asset(asset_, lastObservationTime);

        // Get the current value for the asset
        (uint256 value, uint48 timestamp) = getAssetValue(asset_, Variant.CURRENT);

        // Store the data in the obs index
        uint256 oldestPrice = assetMA.obs[assetMA.nextObsIndex];
        assetMA.obs[assetMA.nextObsIndex] = value;

        // Update the last observation time and increment the next index
        assetMA.lastObservationTime = timestamp;
        assetMA.nextObsIndex = (assetMA.nextObsIndex + 1) % assetMA.numObservations;

        // Update the cumulative observation
        assetMA.cumulativeObs = assetMA.cumulativeObs + value - oldestPrice;

        // Emit event
        emit AssetObservation(asset_, value, timestamp);
    }

    /// @inheritdoc IAppraiser
    function getAssetMovingAverageData(
        address asset_
    ) external view override returns (MovingAverage memory) {
        return assetValueMovingAverage[asset_];
    }

    /// @inheritdoc IAppraiser
    function updateCategoryMovingAverage(
        TreasuryCategory category_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external override onlyRole("appraiser_admin") {
        MovingAverage storage categoryMA = categoryValueMovingAverage[category_];

        // Remove existing data, if any
        if (categoryMA.obs.length > 0) delete categoryMA.obs;

        // Ensure last observation time is not in the future
        if (lastObservationTime_ > block.timestamp)
            revert Appraiser_ParamsLastObservationTimeInvalid_Category(
                category_,
                lastObservationTime_,
                uint48(block.timestamp)
            );

        // Validate moving average parameters
        if (movingAverageDuration_ == 0 || movingAverageDuration_ % observationFrequency != 0)
            revert Appraiser_ParamsMovingAverageDurationInvalid_Category(
                category_,
                movingAverageDuration_,
                observationFrequency
            );

        uint16 numObservations = uint16(movingAverageDuration_ / observationFrequency);
        if (observations_.length != numObservations || numObservations < 2)
            revert Appraiser_ParamsInvalidObservationCount_Category(
                category_,
                observations_.length,
                numObservations
            );

        // Set moving average parameters
        categoryMA.movingAverageDuration = movingAverageDuration_;
        categoryMA.nextObsIndex = 0;
        categoryMA.numObservations = numObservations;
        categoryMA.lastObservationTime = lastObservationTime_;
        categoryMA.cumulativeObs = 0; // reset to zero before adding new observations
        for (uint256 i; i < numObservations; ) {
            if (observations_[i] == 0)
                revert Appraiser_ParamsObservationZero_Category(category_, i);

            categoryMA.cumulativeObs += observations_[i];
            categoryMA.obs.push(observations_[i]);
            unchecked {
                ++i;
            }
        }

        // Emit stored event for the new cached value
        emit CategoryObservation(
            category_,
            observations_[numObservations - 1],
            lastObservationTime_
        );
    }

    /// @inheritdoc IAppraiser
    function storeCategoryObservation(
        TreasuryCategory category_
    ) external override onlyRole("appraiser_store") {
        MovingAverage storage categoryMA = categoryValueMovingAverage[category_];

        // Check that sufficient time has passed to record a new observation
        uint48 lastObservationTime = categoryMA.lastObservationTime;
        if (lastObservationTime + observationFrequency > block.timestamp)
            revert Appraiser_InsufficientTimeElapsed_Category(category_, lastObservationTime);

        // Get the current value for the category
        (uint256 value, uint48 timestamp) = getCategoryValue(category_, Variant.CURRENT);

        // Store the data in the obs index
        uint256 oldestPrice = categoryMA.obs[categoryMA.nextObsIndex];
        categoryMA.obs[categoryMA.nextObsIndex] = value;

        // Update the last observation time and increment the next index
        categoryMA.lastObservationTime = timestamp;
        categoryMA.nextObsIndex = (categoryMA.nextObsIndex + 1) % categoryMA.numObservations;

        // Update the cumulative observation
        categoryMA.cumulativeObs = categoryMA.cumulativeObs + value - oldestPrice;

        // Emit event
        emit CategoryObservation(category_, value, timestamp);
    }

    /// @inheritdoc IAppraiser
    function getCategoryMovingAverageData(
        TreasuryCategory category_
    ) external view override returns (MovingAverage memory) {
        return categoryValueMovingAverage[category_];
    }

    /// @inheritdoc IAppraiser
    function updateMetricMovingAverage(
        Metric metric_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external override onlyRole("appraiser_admin") {
        MovingAverage storage metricMA = metricMovingAverage[metric_];

        // Remove existing data, if any
        if (metricMA.obs.length > 0) delete metricMA.obs;

        // Ensure last observation time is not in the future
        if (lastObservationTime_ > block.timestamp)
            revert Appraiser_ParamsLastObservationTimeInvalid_Metric(
                metric_,
                lastObservationTime_,
                uint48(block.timestamp)
            );

        // Validate moving average parameters
        if (movingAverageDuration_ == 0 || movingAverageDuration_ % observationFrequency != 0)
            revert Appraiser_ParamsMovingAverageDurationInvalid_Metric(
                metric_,
                movingAverageDuration_,
                observationFrequency
            );

        uint16 numObservations = uint16(movingAverageDuration_ / observationFrequency);
        if (observations_.length != numObservations || numObservations < 2)
            revert Appraiser_ParamsInvalidObservationCount_Metric(
                metric_,
                observations_.length,
                numObservations
            );

        // Set moving average parameters
        metricMA.movingAverageDuration = movingAverageDuration_;
        metricMA.nextObsIndex = 0;
        metricMA.numObservations = numObservations;
        metricMA.lastObservationTime = lastObservationTime_;
        metricMA.cumulativeObs = 0; // reset to zero before adding new observations
        for (uint256 i; i < numObservations; ) {
            if (observations_[i] == 0) revert Appraiser_ParamsObservationZero_Metric(metric_, i);

            metricMA.cumulativeObs += observations_[i];
            metricMA.obs.push(observations_[i]);
            unchecked {
                ++i;
            }
        }

        // Emit stored event for the new cached value
        emit MetricObservation(metric_, observations_[numObservations - 1], lastObservationTime_);
    }

    /// @inheritdoc IAppraiser
    function storeMetricObservation(Metric metric_) external override onlyRole("appraiser_store") {
        MovingAverage storage metricMA = metricMovingAverage[metric_];

        // Check that sufficient time has passed to record a new observation
        uint48 lastObservationTime = metricMA.lastObservationTime;
        if (lastObservationTime + observationFrequency > block.timestamp)
            revert Appraiser_InsufficientTimeElapsed_Metric(metric_, lastObservationTime);

        // Get the current value for the metric
        (uint256 value, uint48 timestamp) = getMetric(metric_, Variant.CURRENT);

        // Store the data in the obs index
        uint256 oldestPrice = metricMA.obs[metricMA.nextObsIndex];
        metricMA.obs[metricMA.nextObsIndex] = value;

        // Update the last observation time and increment the next index
        metricMA.lastObservationTime = timestamp;
        metricMA.nextObsIndex = (metricMA.nextObsIndex + 1) % metricMA.numObservations;

        // Update the cumulative observation
        metricMA.cumulativeObs = metricMA.cumulativeObs + value - oldestPrice;

        // Emit event
        emit MetricObservation(metric_, value, timestamp);
    }

    /// @inheritdoc IAppraiser
    function getMetricMovingAverageData(
        Metric metric_
    ) external view override returns (MovingAverage memory) {
        return metricMovingAverage[metric_];
    }

    /// @inheritdoc IAppraiser
    function getObservationFrequency() external view override returns (uint32) {
        return observationFrequency;
    }

    //============================================================================================//
    //                                       UTILITY                                              //
    //============================================================================================//

    function _inArray(address item_, address[] memory array_) internal pure returns (bool) {
        // Check if item is in array
        uint256 len = array_.length;
        for (uint256 i; i < len; ) {
            if (array_[i] == item_) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }
}
