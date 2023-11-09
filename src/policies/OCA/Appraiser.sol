/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import "src/Kernel.sol";
import {IAppraiser} from "src/policies/OCA/interfaces/IAppraiser.sol";
import {TRSRYv1_1, Category, toCategory} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {SPPLYv1} from "src/modules/SPPLY/SPPLY.v1.sol";

contract Appraiser is IAppraiser, Policy {
    // ========== EVENTS ========== //

    // ========== ERRORS ========== //
    error Appraiser_ValueCallFailed(address asset_);
    error Appraiser_ValueZero(address asset_);
    error Appraiser_InvalidParams(uint256 index, bytes params);
    error Appraiser_InvalidCalculation(address asset_, Variant variant_);

    // ========== STATE ========== //

    // Modules
    TRSRYv1_1 internal TRSRY;
    SPPLYv1 internal SPPLY;
    PRICEv2 internal PRICE;

    // Storage of protocol variables to avoid extra external calls
    address internal ohm;
    uint256 internal constant OHM_SCALE = 1e9;
    uint256 internal priceScale;

    // Cache
    mapping(Metric => Cache) public metricCache;
    mapping(address => Cache) public assetValueCache;
    mapping(Category => Cache) public categoryValueCache;

    //============================================================================================//
    //                                     POLICY SETUP                                           //
    //============================================================================================//

    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("PRICE");
        dependencies[1] = toKeycode("SPPLY");
        dependencies[2] = toKeycode("TRSRY");

        PRICE = PRICEv2(getModuleAddress(dependencies[0]));
        SPPLY = SPPLYv1(getModuleAddress(dependencies[1]));
        TRSRY = TRSRYv1_1(getModuleAddress(dependencies[2]));
        ohm = address(SPPLY.ohm());
        priceScale = 10 ** PRICE.decimals();
    }

    //============================================================================================//
    //                                       ASSET VALUES                                         //
    //============================================================================================//

    function getAssetValue(address asset_) external view override returns (uint256) {
        // Get the cached asset value
        (uint256 value, uint48 timestamp) = getAssetValue(asset_, Variant.LAST);

        // Try to use the last value, must be updated on the current timestamp
        if (timestamp == uint48(block.timestamp)) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getAssetValue(asset_, Variant.CURRENT);

        return value;
    }

    function getAssetValue(
        address asset_,
        uint48 maxAge_
    ) external view override returns (uint256) {
        // Get the cached asset value
        (uint256 value, uint48 timestamp) = getAssetValue(asset_, Variant.LAST);

        // Try to use the last value, must be no older than maxAge_
        if (timestamp >= uint48(block.timestamp) - maxAge_) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getAssetValue(asset_, Variant.CURRENT);

        return value;
    }

    function getAssetValue(
        address asset_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        if (variant_ == Variant.LAST) {
            return (assetValueCache[asset_].value, assetValueCache[asset_].timestamp);
        } else if (variant_ == Variant.CURRENT) {
            return _assetValue(asset_);
        } else {
            revert Appraiser_InvalidParams(1, abi.encode(variant_));
        }
    }

    function _assetValue(address asset_) internal view returns (uint256, uint48) {
        // Get current asset price, should be in price decimals configured on PRICE
        (uint256 price, ) = PRICE.getPrice(asset_, PRICEv2.Variant.CURRENT);

        // Get current asset balance, should be in the decimals of the asset
        (uint256 balance, ) = TRSRY.getAssetBalance(asset_, TRSRYv1_1.Variant.CURRENT);

        // Calculate the value of the protocols holdings of the asset
        uint256 value = (price * balance) / (10 ** ERC20(asset_).decimals());

        return (value, uint48(block.timestamp));
    }

    function getCategoryValue(Category category_) external view override returns (uint256) {
        // Get the cached category value
        (uint256 value, uint48 timestamp) = getCategoryValue(category_, Variant.LAST);

        // Try to use the last value, must be updated on the current timestamp
        if (timestamp == uint48(block.timestamp)) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getCategoryValue(category_, Variant.CURRENT);

        return value;
    }

    function getCategoryValue(
        Category category_,
        uint48 maxAge_
    ) external view override returns (uint256) {
        // Get the cached category value
        (uint256 value, uint48 timestamp) = getCategoryValue(category_, Variant.LAST);

        // Try to use the last value, must be no older than maxAge_
        if (timestamp >= uint48(block.timestamp) - maxAge_) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getCategoryValue(category_, Variant.CURRENT);

        return value;
    }

    function getCategoryValue(
        Category category_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        if (variant_ == Variant.LAST) {
            return (categoryValueCache[category_].value, categoryValueCache[category_].timestamp);
        } else if (variant_ == Variant.CURRENT) {
            return _categoryValue(category_);
        } else {
            revert Appraiser_InvalidParams(1, abi.encode(variant_));
        }
    }

    function _categoryValue(Category category_) internal view returns (uint256, uint48) {
        // Get the assets in the category
        address[] memory assets = TRSRY.getAssetsByCategory(category_);

        // Get the value of each asset in the category
        uint256 value;
        uint256 len = assets.length;
        for (uint256 i; i < len; ) {
            (uint256 assetValue, ) = _assetValue(assets[i]);
            value += assetValue;
            unchecked {
                ++i;
            }
        }

        return (value, uint48(block.timestamp));
    }

    //============================================================================================//
    //                                       VALUE METRICS                                        //
    //============================================================================================//

    /// @notice Returns the current value of the metric
    /// @dev Optimistically uses the cached value if it has been updated this block, otherwise calculates value dynamically
    function getMetric(Metric metric_) external view override returns (uint256) {
        // Get the cached value of the metric
        (uint256 value, uint48 timestamp) = getMetric(metric_, Variant.LAST);

        // Try to use the last value, must be updated on the current timestamp
        if (timestamp == uint48(block.timestamp)) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getMetric(metric_, Variant.CURRENT);

        return value;
    }

    /// @notice Returns a value no older than the provided age
    function getMetric(Metric metric_, uint48 maxAge_) external view override returns (uint256) {
        // Get the cached value of the metric
        (uint256 value, uint48 timestamp) = getMetric(metric_, Variant.LAST);

        // Try to use the last value, must be no older than maxAge_
        if (timestamp >= uint48(block.timestamp) - maxAge_) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getMetric(metric_, Variant.CURRENT);

        return value;
    }

    /// @notice Returns the requested variant of the metric and the timestamp at which it was calculated
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
        } else {
            revert Appraiser_InvalidParams(1, abi.encode(variant_));
        }
    }

    function _backing() internal view returns (uint256) {
        // Get list of assets owned by the protocol
        address[] memory assets = TRSRY.getAssets();

        // Get the addresses of POL assets in the treasury
        address[] memory polAssets = TRSRY.getAssetsByCategory(
            toCategory("protocol-owned-liquidity")
        );

        uint256 value;
        uint256 len = assets.length;
        for (uint256 i; i < len; ) {
            if (assets[i] != ohm) {
                (uint256 assetValue, ) = _assetValue(assets[i]);
                if (_inArray(assets[i], polAssets)) {
                    // TODO dividing by 2 only works with 50/50 xyk pools. Need to make more general
                    // Another to do it could be to get the POL supply from SPPLY module, calculate its value,
                    // and then subtract it from the total market value of the treasury
                    assetValue >> 1; // divide by 2, bitshifting is cheaper than division
                }
                value += assetValue;
            }
            unchecked {
                ++i;
            }
        }

        return value;
    }

    function _liquidBacking() internal view returns (uint256) {
        // Get total backing
        uint256 backing = _backing();

        // Get value of assets categorized as illiquid
        (uint256 illiquidValue, ) = _categoryValue(toCategory("illiquid"));

        // Subtract illiquid value from total backing
        return backing - illiquidValue;
    }

    function _liquidBackingPerBackedOhm() internal view returns (uint256) {
        // Get liquid backing
        uint256 liquidBacking = _liquidBacking();

        // Get supply of backed ohm
        (uint256 backedSupply, ) = SPPLY.getMetric(
            SPPLYv1.Metric.BACKED_SUPPLY,
            SPPLYv1.Variant.CURRENT
        );

        // Divide liquid backing by backed supply
        return (liquidBacking * OHM_SCALE) / backedSupply;
    }

    function _marketValue() internal view returns (uint256) {
        // Get list of assets owned by the protocol
        address[] memory assets = TRSRY.getAssets();

        // Get the value of each asset
        uint256 value;
        uint256 len = assets.length;
        for (uint256 i; i < len; ) {
            (uint256 assetValue, ) = _assetValue(assets[i]);
            value += assetValue;
            unchecked {
                ++i;
            }
        }

        return value;
    }

    function _marketCap() internal view returns (uint256) {
        // Get supply of ohm
        (uint256 supply, ) = SPPLY.getMetric(SPPLYv1.Metric.TOTAL_SUPPLY, SPPLYv1.Variant.CURRENT);

        // Get price of ohm
        (uint256 price, ) = PRICE.getPrice(ohm, PRICEv2.Variant.CURRENT);

        // Multiply supply by price
        return (supply * price) / OHM_SCALE;
    }

    // returns value in PRICE.decimals() units
    function _premium() internal view returns (uint256) {
        // Get market cap of OHM
        uint256 marketCap = _marketCap();

        // Get market value of treasury
        uint256 marketValue = _marketValue();

        // Divide market cap by market value of treasury
        return (marketCap * priceScale) / marketValue;
    }

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
            stdDev += ((changes[i] - meanChange) ** 2);
        }
        stdDev = FixedPointMathLib.sqrt(stdDev / len);

        // Calculate and return annual volatility
        return stdDev * 33; // annual std dev = period std dev * sqrt(periods per year), in this case there are 365 * 3 = 1095 periods per year. sqrt(1095) = 33.097...
    }

    //============================================================================================//
    //                                       CACHING                                              //
    //============================================================================================//

    function storeAssetValue(address asset_) external override {
        (uint256 value, uint48 timestamp) = getAssetValue(asset_, Variant.CURRENT);
        assetValueCache[asset_] = Cache(value, timestamp);
    }

    function storeCategoryValue(Category category_) external override {
        (uint256 value, uint48 timestamp) = getCategoryValue(category_, Variant.CURRENT);
        categoryValueCache[category_] = Cache(value, timestamp);
    }

    function storeMetric(Metric metric_) external override {
        (uint256 result, uint48 timestamp) = getMetric(metric_, Variant.CURRENT);
        metricCache[metric_] = Cache(result, timestamp);
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
