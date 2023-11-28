/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import "src/Kernel.sol";
import {IAppraiser} from "src/policies/OCA/interfaces/IAppraiser.sol";
import {TRSRYv1_1, Category as TreasuryCategory, toCategory as toTreasuryCategory} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {SPPLYv1, toCategory as toSupplyCategory} from "src/modules/SPPLY/SPPLY.v1.sol";

contract Appraiser is IAppraiser, Policy {
    // ========== EVENTS ========== //

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

    // ========== STATE ========== //

    // Modules
    TRSRYv1_1 internal TRSRY;
    SPPLYv1 internal SPPLY;
    PRICEv2 internal PRICE;

    // Storage of protocol variables to avoid extra external calls
    address internal ohm;
    uint256 internal constant OHM_SCALE = 1e9;
    uint256 internal priceScale;
    uint8 public decimals;

    // Cache
    mapping(Metric => Cache) public metricCache;
    mapping(address => Cache) public assetValueCache;
    mapping(TreasuryCategory => Cache) public categoryValueCache;

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

        (uint8 PRICE_MAJOR, ) = PRICE.VERSION();
        (uint8 SPPLY_MAJOR, ) = SPPLY.VERSION();
        (uint8 TRSRY_MAJOR, uint8 TRSRY_MINOR) = TRSRY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([2, 1, 1]);
        if (PRICE_MAJOR != 2 || SPPLY_MAJOR != 1 || TRSRY_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Check TRSRY minor version
        if (TRSRY_MINOR < 1) revert Policy_WrongModuleVersion(expected);

        ohm = address(SPPLY.ohm());
        decimals = PRICE.decimals();
        priceScale = 10 ** decimals;
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

    /// @inheritdoc IAppraiser
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

    /// @notice         Calculates the value of the protocols holdings of `asset_`
    ///
    /// @param asset_   The address of the asset to get the value of
    /// @return         The value of the asset (in terms of `decimals`)
    /// @return         The timestamp at which the value was calculated
    function _assetValue(address asset_) internal view returns (uint256, uint48) {
        // Get current asset price, should be in price decimals configured on PRICE
        (uint256 price, ) = PRICE.getPrice(asset_, PRICEv2.Variant.CURRENT);

        // Get current asset balance, should be in the decimals of the asset
        (uint256 balance, ) = TRSRY.getAssetBalance(asset_, TRSRYv1_1.Variant.CURRENT);

        // Calculate the value of the protocols holdings of the asset
        uint256 value = (price * balance) / (10 ** ERC20(asset_).decimals());

        return (value, uint48(block.timestamp));
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
    function getCategoryValue(
        TreasuryCategory category_,
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

    /// @inheritdoc IAppraiser
    function getCategoryValue(
        TreasuryCategory category_,
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

    /// @notice             Calculates the value of the asset holdings in `category_`
    ///
    /// @param category_    The TRSRY category to get the value of
    /// @return             The value of the assets in the category (in terms of `decimals`)
    /// @return             The timestamp at which the value was calculated
    function _categoryValue(TreasuryCategory category_) internal view returns (uint256, uint48) {
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
    function getMetric(Metric metric_, uint48 maxAge_) external view override returns (uint256) {
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
        } else {
            revert Appraiser_InvalidParams(1, abi.encode(variant_));
        }
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
            if (assets[i] != ohm) {
                (uint256 assetValue, ) = _assetValue(assets[i]);
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
                if (reserves[i].tokens[j] != ohm) {
                    // Get current asset price
                    (uint256 price, ) = PRICE.getPrice(
                        reserves[i].tokens[j],
                        PRICEv2.Variant.CURRENT
                    );
                    // Calculate current asset valuation
                    value +=
                        (price * reserves[i].balances[j]) /
                        (10 ** ERC20(reserves[i].tokens[j]).decimals());
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
        (uint256 illiquidValue, ) = _categoryValue(toTreasuryCategory("illiquid"));

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
        return ((liquidBacking * priceScale) / backedSupply) / OHM_SCALE;
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
            (uint256 assetValue, ) = _assetValue(assets[i]);
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
        return (supply * price) / OHM_SCALE;
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
        return (marketCap * priceScale) / marketValue;
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
    function storeAssetValue(address asset_) external override {
        (uint256 value, uint48 timestamp) = getAssetValue(asset_, Variant.CURRENT);
        assetValueCache[asset_] = Cache(value, timestamp);
    }

    /// @inheritdoc IAppraiser
    function storeCategoryValue(TreasuryCategory category_) external override {
        (uint256 value, uint48 timestamp) = getCategoryValue(category_, Variant.CURRENT);
        categoryValueCache[category_] = Cache(value, timestamp);
    }

    /// @inheritdoc IAppraiser
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
