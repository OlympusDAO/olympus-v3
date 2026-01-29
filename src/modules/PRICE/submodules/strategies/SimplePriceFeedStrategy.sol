/// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

// Interfaces
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";

// Libraries
import {Deviation} from "src/libraries/Deviation.sol";
import {QuickSort} from "src/libraries/QuickSort.sol";

// Bophades
import {Module} from "src/Kernel.sol";
import {PriceSubmodule} from "modules/PRICE/PRICE.v2.sol";
import {Submodule, SubKeycode, toSubKeycode} from "src/Submodules.sol";

/// @title      SimplePriceFeedStrategy
/// @author     0xJem
/// @notice     The functions in this contract provide PRICEv2 strategies that can be used to handle
/// @notice     the results from multiple price feeds
contract SimplePriceFeedStrategy is PriceSubmodule, ISimplePriceFeedStrategy {
    using QuickSort for uint256[];

    /// @notice     This is the expected length of bytes for the parameters to the deviation strategies
    uint8 internal constant DEVIATION_PARAMS_LENGTH = 64;

    /// @notice     Represents a 0% deviation, which is invalid
    uint256 internal constant DEVIATION_MIN = 0;

    /// @notice     Represents a 100% deviation, which is invalid
    uint256 internal constant DEVIATION_MAX = 10_000;

    // ========== ERRORS ========== //

    /// @notice                 Indicates that the number of prices provided to the strategy is invalid
    ///
    /// @param priceCount_      The number of prices provided to the strategy
    /// @param minPriceCount_   The minimum number of prices required by the strategy
    error SimpleStrategy_PriceCountInvalid(uint256 priceCount_, uint256 minPriceCount_);

    /// @notice                 Indicates that the parameters provided to the strategy are invalid
    ///
    /// @param params_          The parameters provided to the strategy
    error SimpleStrategy_ParamsInvalid(bytes params_);

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    /// @inheritdoc      Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.SIMPLESTRATEGY");
    }

    /// @inheritdoc      Submodule
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice        Returns a new array with only the non-zero elements of the input array
    ///
    /// @param  array_  Array of uint256 values
    /// @return uint256[]  Array of non-zero uint256 values
    function _getNonZeroArray(uint256[] memory array_) internal pure returns (uint256[] memory) {
        // Determine the number of non-zero array elements
        uint256 nonZeroCount = 0;
        for (uint256 i = 0; i < array_.length; i++) {
            if (array_[i] != 0) nonZeroCount++;
        }

        // Create a new array with only the non-zero elements
        uint256[] memory nonZeroArray = new uint256[](nonZeroCount);
        uint256 nonZeroIndex = 0;
        for (uint256 i = 0; i < array_.length; i++) {
            if (array_[i] != 0) {
                nonZeroArray[nonZeroIndex] = array_[i];
                nonZeroIndex++;
            }
        }

        return nonZeroArray;
    }

    /// @notice         Returns the average of the prices in the array
    /// @dev            This function will calculate the average of all values in the array.
    /// @dev            If non-zero values should not be included in the average, filter them prior.
    ///
    /// @param  prices_  Array of prices
    /// @return uint256  The average price or 0
    function _getAveragePrice(uint256[] memory prices_) internal pure returns (uint256) {
        uint256 pricesLen = prices_.length;

        // If all price feeds are down, no average can be calculated
        if (pricesLen == 0) return 0;

        uint256 priceTotal;
        for (uint256 i = 0; i < pricesLen; i++) {
            priceTotal += prices_[i];
        }

        return priceTotal / pricesLen;
    }

    /// @notice         Returns the median of the prices in the array
    /// @dev            This function will calculate the median of all values in the array.
    /// @dev            It assumes that the price array is sorted in ascending order.
    /// @dev            The function assumes there are at least 3 prices in the array.
    /// @dev            If there are only two prices, the average of the two will be returned.
    /// @dev            If non-zero values should not be included in the median, filter them prior.
    ///
    /// @param  prices_  Array of prices
    /// @return uint256  The median price
    function _getMedianPrice(uint256[] memory prices_) internal pure returns (uint256) {
        uint256 pricesLen = prices_.length;

        // If there are an even number of prices, return the average of the two middle prices
        if (pricesLen % 2 == 0) {
            uint256 middlePrice1 = prices_[pricesLen / 2 - 1];
            uint256 middlePrice2 = prices_[pricesLen / 2];
            return (middlePrice1 + middlePrice2) / 2;
        }

        // Otherwise return the median price
        // Don't need to subtract 1 from pricesLen to get midpoint index
        // since integer division will round down
        return prices_[pricesLen / 2];
    }

    // ========== STRATEGY FUNCTIONS ========== //

    /// @notice         Returns the first non-zero price in the array.
    /// @dev            Reverts if:
    /// @dev            - The length of prices_ array is 0, which would represent a mis-configuration.
    ///
    /// @dev            If a non-zero price cannot be found, 0 will be returned.
    ///
    /// @param  prices_  Array of prices
    /// @return uint256  The resolved price
    function getFirstNonZeroPrice(
        uint256[] memory prices_,
        bytes memory
    ) public pure returns (uint256) {
        // Can't work with 0 length
        uint256 pricesLen = prices_.length;
        if (pricesLen == 0) revert SimpleStrategy_PriceCountInvalid(pricesLen, 1);

        // Iterate through the array and return the first non-zero price
        for (uint256 i = 0; i < pricesLen; i++) {
            if (prices_[i] != 0) return prices_[i];
        }

        // If we have reached this far, there are only 0 prices in the array
        return 0;
    }

    /// @inheritdoc ISimplePriceFeedStrategy
    /// @dev    Uses average as benchmark for deviation calculation.
    /// @dev    If no deviation detected, returns the first non-zero price.
    function getAveragePriceIfDeviation(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        /*
            CASE HANDLING SUMMARY
            =====================

            Configuration Issues (always revert):
            - Input array < 2 elements: misconfiguration
            - Invalid params: wrong length or invalid deviationBps

            Runtime Issues (handled based on revertOnInsufficientCount flag):
            | Scenario                | flag=false              | flag=true           |
            |-------------------------|-------------------------|---------------------|
            | All prices zero         | Revert                  | Revert              |
            | 1 non-zero price        | Return that price       | Revert              |
            | 2+ non-zero prices      | Check deviation         | Check deviation     |

            RATIONALE:
            - 0 prices always reverts (no data is an error)
            - flag=false: Best effort mode (accept single source)
            - flag=true: Strict mode (require 2+ sources)
        */

        // ========== CONFIGURATION VALIDATION ==========
        if (prices_.length < 2) revert SimpleStrategy_PriceCountInvalid(prices_.length, 2);

        // ========== PARAMETER DECODING ==========
        ISimplePriceFeedStrategy.DeviationParams memory params = _decodeDeviationParams(params_);

        // ========== ZERO PRICE FILTERING ==========
        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);
        uint256 nonZeroPricesLen = nonZeroPrices.length;

        // 0 prices = no data, always revert
        if (nonZeroPricesLen == 0) revert SimpleStrategy_PriceCountInvalid(0, 2);

        // 1 price = check flag
        if (nonZeroPricesLen == 1) {
            if (params.revertOnInsufficientCount) revert SimpleStrategy_PriceCountInvalid(1, 2);
            return nonZeroPrices[0]; // flag=false: accept single source
        }

        // ========== 2+ PRICES: CHECK DEVIATION ==========
        uint256[] memory sortedPrices = nonZeroPrices.sort();
        uint256 averagePrice = _getAveragePrice(sortedPrices);

        // Check the deviation of the minimum from the average
        uint256 minPrice = sortedPrices[0];
        if (Deviation.isDeviating(minPrice, averagePrice, params.deviationBps, DEVIATION_MAX))
            return averagePrice;

        // Check the deviation of the maximum from the average
        uint256 maxPrice = sortedPrices[sortedPrices.length - 1];
        if (Deviation.isDeviating(maxPrice, averagePrice, params.deviationBps, DEVIATION_MAX))
            return averagePrice;

        // No deviation detected, return the first non-zero price
        return nonZeroPrices[0];
    }

    /// @inheritdoc ISimplePriceFeedStrategy
    /// @dev    Uses median as benchmark for deviation calculation.
    /// @dev    Falls back to getAveragePriceIfDeviation if fewer than 3 non-zero prices.
    function getMedianPriceIfDeviation(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        /*
            CASE HANDLING SUMMARY
            =====================

            Configuration Issues (always revert):
            - Input array < 3 elements: misconfiguration
            - Invalid params: wrong length or invalid deviationBps

            Runtime Issues (handled based on revertOnInsufficientCount flag):
            | Scenario                | flag=false              | flag=true           |
            |-------------------------|-------------------------|---------------------|
            | All prices zero         | Revert                  | Revert              |
            | 1 non-zero price        | Return that price       | Revert              |
            | 2 non-zero prices       | Return average          | Revert              |
            | 3+ non-zero prices      | Check deviation         | Check deviation     |

            RATIONALE:
            - 0 prices always reverts (no data is an error)
            - flag=false: Best effort mode (accept 1-2 sources)
            - flag=true: Strict mode (require 3+ sources for median)
        */

        // ========== CONFIGURATION VALIDATION ==========
        if (prices_.length < 3) revert SimpleStrategy_PriceCountInvalid(prices_.length, 3);

        // ========== PARAMETER DECODING ==========
        ISimplePriceFeedStrategy.DeviationParams memory params = _decodeDeviationParams(params_);

        // ========== ZERO PRICE FILTERING ==========
        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);
        uint256 nonZeroPricesLen = nonZeroPrices.length;

        // 0 prices = no data, always revert
        if (nonZeroPricesLen == 0) revert SimpleStrategy_PriceCountInvalid(0, 3);

        // Cache first non-zero price before sorting
        uint256 firstNonZeroPrice = nonZeroPrices[0];

        // 1 price = check flag
        if (nonZeroPricesLen == 1) {
            if (params.revertOnInsufficientCount) revert SimpleStrategy_PriceCountInvalid(1, 3);
            return nonZeroPrices[0]; // flag=false: accept single source
        }

        // 2 prices = check flag (median requires 3+)
        if (nonZeroPricesLen == 2) {
            if (params.revertOnInsufficientCount) revert SimpleStrategy_PriceCountInvalid(2, 3);
            // flag=false: check deviation and return appropriate value
            uint256 twoPriceAverage = _getAveragePrice(nonZeroPrices);
            // Check if prices deviate from average
            if (
                Deviation.isDeviating(
                    nonZeroPrices[0],
                    twoPriceAverage,
                    params.deviationBps,
                    DEVIATION_MAX
                ) ||
                Deviation.isDeviating(
                    nonZeroPrices[1],
                    twoPriceAverage,
                    params.deviationBps,
                    DEVIATION_MAX
                )
            ) {
                return twoPriceAverage;
            }
            // No deviation, return first price
            return firstNonZeroPrice;
        }

        // ========== 3+ PRICES: CHECK DEVIATION ==========
        uint256[] memory sortedPrices = nonZeroPrices.sort();

        // Get the average and median
        uint256 averagePrice = _getAveragePrice(sortedPrices);
        uint256 medianPrice = _getMedianPrice(sortedPrices);

        // Check the deviation of the minimum from the average
        uint256 minPrice = sortedPrices[0];
        if (Deviation.isDeviating(minPrice, averagePrice, params.deviationBps, DEVIATION_MAX))
            return medianPrice;

        // Check the deviation of the maximum from the average
        uint256 maxPrice = sortedPrices[sortedPrices.length - 1];
        if (Deviation.isDeviating(maxPrice, averagePrice, params.deviationBps, DEVIATION_MAX))
            return medianPrice;

        // No deviation detected, return the first non-zero value
        return firstNonZeroPrice;
    }

    /// @inheritdoc ISimplePriceFeedStrategy
    /// @dev    Zero prices are ignored to handle failing price feeds gracefully.
    /// @dev    In strict mode, reverts if fewer than 2 non-zero prices exist.
    function getAveragePrice(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        /*
            CASE HANDLING SUMMARY
            =====================

            Configuration Issues (always revert):
            - Input array < 2 elements: misconfiguration
            - Invalid params: wrong length (must be exactly 32 bytes)

            Runtime Issues (handled based on revertOnInsufficientCount flag):
            | Scenario                | flag=false              | flag=true           |
            |-------------------------|-------------------------|---------------------|
            | All prices zero         | Revert                  | Revert              |
            | 1 non-zero price        | Return that price       | Revert              |
            | 2+ non-zero prices      | Return average          | Return average      |

            RATIONALE:
            - 0 prices always reverts (no data is an error)
            - flag=false: Best effort mode (accept single source)
            - flag=true: Strict mode (require 2+ sources for average)
        */

        // ========== CONFIGURATION VALIDATION ==========
        if (prices_.length < 2) revert SimpleStrategy_PriceCountInvalid(prices_.length, 2);

        // ========== PARAMETER DECODING ==========
        if (params_.length != 32) revert SimpleStrategy_ParamsInvalid(params_);
        bool revertOnInsufficientCount = abi.decode(params_, (bool));

        // ========== ZERO PRICE FILTERING ==========
        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);
        uint256 nonZeroPricesLen = nonZeroPrices.length;

        // 0 prices = no data, always revert
        if (nonZeroPricesLen == 0) revert SimpleStrategy_PriceCountInvalid(0, 2);

        // 1 price = check flag
        if (nonZeroPricesLen == 1) {
            if (revertOnInsufficientCount) revert SimpleStrategy_PriceCountInvalid(1, 2);
            return nonZeroPrices[0]; // flag=false: accept single source
        }

        // ========== 2+ PRICES: CALCULATE AVERAGE ==========
        return _getAveragePrice(nonZeroPrices);
    }

    /// @inheritdoc ISimplePriceFeedStrategy
    /// @dev    If even number of prices, returns average of two middle values.
    /// @dev    Zero prices are ignored to handle failing price feeds gracefully.
    /// @dev    In strict mode, reverts if fewer than 3 non-zero prices exist.
    function getMedianPrice(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        /*
            CASE HANDLING SUMMARY
            =====================

            Configuration Issues (always revert):
            - Input array < 3 elements: misconfiguration
            - Invalid params: wrong length (must be exactly 32 bytes)

            Runtime Issues (handled based on revertOnInsufficientCount flag):
            | Scenario                | flag=false              | flag=true           |
            |-------------------------|-------------------------|---------------------|
            | All prices zero         | Revert                  | Revert              |
            | 1 non-zero price        | Return that price       | Revert              |
            | 2 non-zero prices       | Return average          | Revert              |
            | 3+ non-zero prices      | Return median           | Return median       |

            RATIONALE:
            - 0 prices always reverts (no data is an error)
            - flag=false: Best effort mode (accept single source)
            - flag=true: Strict mode (require 3+ sources for median)
        */

        // ========== CONFIGURATION VALIDATION ==========
        if (prices_.length < 3) revert SimpleStrategy_PriceCountInvalid(prices_.length, 3);

        // ========== PARAMETER DECODING ==========
        if (params_.length != 32) revert SimpleStrategy_ParamsInvalid(params_);
        bool revertOnInsufficientCount = abi.decode(params_, (bool));

        // ========== ZERO PRICE FILTERING ==========
        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);
        uint256 nonZeroPricesLen = nonZeroPrices.length;

        // 0 prices = no data, always revert
        if (nonZeroPricesLen == 0) revert SimpleStrategy_PriceCountInvalid(0, 3);

        // 1 price = check flag
        if (nonZeroPricesLen == 1) {
            if (revertOnInsufficientCount) revert SimpleStrategy_PriceCountInvalid(1, 3);
            return nonZeroPrices[0]; // flag=false: accept single source
        }

        // 2 prices = check flag (median requires 3+)
        if (nonZeroPricesLen == 2) {
            if (revertOnInsufficientCount) revert SimpleStrategy_PriceCountInvalid(2, 3);
            // flag=false: fall back to average using filtered array
            return _getAveragePrice(nonZeroPrices);
        }

        // ========== 3+ PRICES: CALCULATE MEDIAN ==========
        // Sort the prices
        uint256[] memory sortedPrices = nonZeroPrices.sort();

        return _getMedianPrice(sortedPrices);
    }

    /// @inheritdoc ISimplePriceFeedStrategy
    /// @dev    Validates input parameters and filters outliers before computing average.
    /// @dev    Reverts if fewer than 3 prices are provided (configuration error).
    /// @dev    Reverts if no valid prices remain after filtering (no data error).
    function getAveragePriceExcludingDeviations(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        /*
            CASE HANDLING SUMMARY
            =====================

            Configuration Issues (always revert):
            - Input array < 3 elements: misconfiguration
            - Invalid params: wrong length or deviationBps out of bounds

            Runtime Issues (handled based on revertOnInsufficientCount flag):
            | Scenario                | flag=false              | flag=true           |
            |-------------------------|-------------------------|---------------------|
            | All prices zero         | Revert                  | Revert              |
            | 1 non-zero price        | Return that price       | Revert              |
            | 2 non-zero prices       | Use avg as benchmark    | Use avg as benchmark|
            | 3+ non-zero prices      | Use median as benchmark | Use median as bench |
            | All prices excluded     | Revert                  | Revert              |
            | 1 price remains         | Return that price       | Revert              |

            RATIONALE:
            - 0 prices always reverts (no data is an error)
            - flag=false: Accept single source (best effort)
            - flag=true: Require 2+ sources (strict mode, recommended)
        */

        // ========== CONFIGURATION VALIDATION ==========
        if (prices_.length < 3) revert SimpleStrategy_PriceCountInvalid(prices_.length, 3);

        // ========== PARAMETER DECODING ==========
        ISimplePriceFeedStrategy.DeviationParams memory params = _decodeDeviationParams(params_);

        // ========== ZERO PRICE FILTERING ==========
        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);
        uint256 nonZeroCount = nonZeroPrices.length;

        // 0 prices = no data, always revert
        if (nonZeroCount == 0) revert SimpleStrategy_PriceCountInvalid(0, 2);

        // 1 price = check flag
        if (nonZeroCount == 1) {
            if (params.revertOnInsufficientCount) revert SimpleStrategy_PriceCountInvalid(1, 2);
            return nonZeroPrices[0]; // flag=false: accept single source
        }

        // ========== 2 PRICES: USE AVERAGE AS BENCHMARK ==========
        if (nonZeroCount == 2) {
            // Note: Addition may overflow if prices are unreasonably large. This is acceptable
            // as price feeds typically use 18 decimals with reasonable market values.
            uint256 averagePrice = (nonZeroPrices[0] + nonZeroPrices[1]) / 2;

            // Single pass: collect valid prices (max 2)
            uint256[2] memory twoPriceValidPrices;
            uint256 twoPriceValidCount = 0;
            for (uint256 i = 0; i < 2; i++) {
                if (
                    !Deviation.isDeviating(
                        nonZeroPrices[i],
                        averagePrice,
                        params.deviationBps,
                        DEVIATION_MAX
                    )
                ) {
                    twoPriceValidPrices[twoPriceValidCount] = nonZeroPrices[i];
                    twoPriceValidCount++;
                }
            }

            // 0 prices = no data, always revert
            if (twoPriceValidCount == 0) revert SimpleStrategy_PriceCountInvalid(0, 2);

            // 1 price = check flag
            if (twoPriceValidCount == 1 && params.revertOnInsufficientCount)
                revert SimpleStrategy_PriceCountInvalid(1, 2);

            return (twoPriceValidPrices[0] + twoPriceValidPrices[1]) / twoPriceValidCount;
        }

        // ========== 3+ PRICES: USE MEDIAN AS BENCHMARK ==========
        uint256[] memory sortedPrices = nonZeroPrices.sort();
        uint256 medianPrice = _getMedianPrice(sortedPrices);

        // Filter by deviation from median
        (uint256[] memory validPrices, uint256 validCount) = _filterByDeviation(
            sortedPrices,
            medianPrice,
            params.deviationBps,
            2
        );

        // 1 price = check flag
        if (validCount == 1 && params.revertOnInsufficientCount)
            revert SimpleStrategy_PriceCountInvalid(1, 2);

        // Sum valid prices (only the filled portion of the array)
        // Note: Accumulation may overflow if prices are unreasonably large. This is acceptable
        // as price feeds typically use 18 decimals with reasonable market values.
        uint256 multiPriceSum = 0;
        for (uint256 i = 0; i < validCount; i++) {
            multiPriceSum += validPrices[i];
        }
        return multiPriceSum / validCount;
    }

    /// @inheritdoc ISimplePriceFeedStrategy
    /// @dev    Validates input parameters and filters outliers before computing median.
    /// @dev    Reverts if fewer than 3 prices are provided (configuration error).
    /// @dev    Reverts if no valid prices remain after filtering (no data error).
    function getMedianPriceExcludingDeviations(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        /*
            CASE HANDLING SUMMARY
            =====================

            Configuration Issues (always revert):
            - Input array < 3 elements: misconfiguration
            - Invalid params: wrong length or deviationBps out of bounds

            Runtime Issues (handled based on revertOnInsufficientCount flag):
            | Scenario                | flag=false              | flag=true           |
            |-------------------------|-------------------------|---------------------|
            | All prices zero         | Revert                  | Revert              |
            | 1 non-zero price        | Return that price       | Revert              |
            | 2 non-zero prices       | Use avg as benchmark    | Revert              |
            | 3+ non-zero prices      | Use median as benchmark | Use median as bench |
            | All prices excluded     | Revert                  | Revert              |
            | 1 price remains         | Return that price       | Revert              |
            | 2 prices remain         | Return average          | Revert              |
            | 3+ prices remain        | Return median           | Return median       |

            RATIONALE:
            - 0 prices always reverts (no data is an error)
            - flag=false: Accept 1-2 sources (best effort)
            - flag=true: Require 3+ sources for median (strict mode, recommended)
            - Median is used as benchmark for 3+ prices (same as getAveragePriceExcludingDeviations)
        */

        // ========== CONFIGURATION VALIDATION ==========
        if (prices_.length < 3) revert SimpleStrategy_PriceCountInvalid(prices_.length, 3);

        // ========== PARAMETER DECODING ==========
        ISimplePriceFeedStrategy.DeviationParams memory params = _decodeDeviationParams(params_);

        // ========== ZERO PRICE FILTERING ==========
        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);
        uint256 nonZeroCount = nonZeroPrices.length;

        // 0 prices = no data, always revert
        if (nonZeroCount == 0) revert SimpleStrategy_PriceCountInvalid(0, 3);

        // 1 price = check flag (median requires 3+ sources)
        if (nonZeroCount == 1) {
            if (params.revertOnInsufficientCount) revert SimpleStrategy_PriceCountInvalid(1, 3);
            return nonZeroPrices[0]; // flag=false: accept single source
        }

        // 2 prices = check flag (median requires 3+ sources in strict mode)
        if (nonZeroCount == 2) {
            if (params.revertOnInsufficientCount) revert SimpleStrategy_PriceCountInvalid(2, 3);
            // flag=false: continue with deviation checking using average as benchmark
            // Note: Addition may overflow if prices are unreasonably large. This is acceptable
            // as price feeds typically use 18 decimals with reasonable market values.
            uint256 averagePrice = (nonZeroPrices[0] + nonZeroPrices[1]) / 2;

            // Single pass: collect valid prices (max 2)
            uint256[2] memory twoPriceValidPrices;
            uint256 twoPriceValidCount = 0;
            for (uint256 i = 0; i < 2; i++) {
                if (
                    !Deviation.isDeviating(
                        nonZeroPrices[i],
                        averagePrice,
                        params.deviationBps,
                        DEVIATION_MAX
                    )
                ) {
                    twoPriceValidPrices[twoPriceValidCount] = nonZeroPrices[i];
                    twoPriceValidCount++;
                }
            }

            // 0 prices = no data, always revert
            if (twoPriceValidCount == 0) revert SimpleStrategy_PriceCountInvalid(0, 2);

            // 1 price = return that price
            // 2 prices = return average
            return (twoPriceValidPrices[0] + twoPriceValidPrices[1]) / twoPriceValidCount;
        }

        // ========== 3+ PRICES: USE MEDIAN AS BENCHMARK ==========
        // Note: Using median (not average) as benchmark for the deviation check
        // This is the same approach as getAveragePriceExcludingDeviations
        // Using median as benchmark prevents the case where all values deviate from their own average
        uint256[] memory sortedPrices = nonZeroPrices.sort();
        uint256 medianPrice = _getMedianPrice(sortedPrices);

        // Filter by deviation from median
        (uint256[] memory validPrices, uint256 validCount) = _filterByDeviation(
            sortedPrices,
            medianPrice,
            params.deviationBps,
            3
        );

        // 1 price = check flag (median requires 3+ sources)
        if (validCount == 1 && params.revertOnInsufficientCount)
            revert SimpleStrategy_PriceCountInvalid(1, 3);

        // 2 prices = check flag, then return average
        if (validCount == 2) {
            if (params.revertOnInsufficientCount) revert SimpleStrategy_PriceCountInvalid(2, 3);

            // Note: Addition may overflow if prices are unreasonably large. This is acceptable
            // as price feeds typically use 18 decimals with reasonable market values.
            return (validPrices[0] + validPrices[1]) / 2;
        }

        // 3+ prices: return median of valid prices
        // Note: validPrices is already sorted since we iterated through sortedPrices in order
        return _getMedianPrice(validPrices);
    }

    // ========== PARAMETER DECODING HELPERS ==========

    /// @notice         Decodes and validates DeviationParams from calldata
    /// @dev            Reverts if params length is invalid or deviationBps is out of bounds
    ///
    /// @param  params_  Encoded DeviationParams bytes
    /// @return DeviationParams  Decoded DeviationParams struct
    function _decodeDeviationParams(
        bytes memory params_
    ) internal pure returns (ISimplePriceFeedStrategy.DeviationParams memory) {
        // DeviationParams encoding: uint16 (32 bytes) + bool (32 bytes) = 64 bytes
        if (params_.length != DEVIATION_PARAMS_LENGTH) revert SimpleStrategy_ParamsInvalid(params_);
        ISimplePriceFeedStrategy.DeviationParams memory params = abi.decode(
            params_,
            (ISimplePriceFeedStrategy.DeviationParams)
        );

        // Validate deviation bounds (must be > 0 and < 10000)
        if (params.deviationBps <= DEVIATION_MIN || params.deviationBps >= DEVIATION_MAX)
            revert SimpleStrategy_ParamsInvalid(params_);

        return params;
    }

    /// @notice         Filters prices by deviation from a benchmark value
    /// @dev            Returns a sorted array of non-deviating prices and the count
    ///
    /// @param  prices_            Sorted array of prices to filter
    /// @param  benchmark_         The benchmark value to check deviation against
    /// @param  deviationBps_      The accepted deviation in basis points
    /// @param  minExpectedCount_  Minimum number of prices required (for error reporting)
    /// @return validPrices_       Sorted array of non-deviating prices
    /// @return validCount_        Number of non-deviating prices found
    function _filterByDeviation(
        uint256[] memory prices_,
        uint256 benchmark_,
        uint16 deviationBps_,
        uint256 minExpectedCount_
    ) internal pure returns (uint256[] memory validPrices_, uint256 validCount_) {
        uint256 pricesCount = prices_.length;

        // First pass: count valid prices to size array correctly
        validCount_ = 0;
        for (uint256 i = 0; i < pricesCount; i++) {
            if (!Deviation.isDeviating(prices_[i], benchmark_, deviationBps_, DEVIATION_MAX)) {
                validCount_++;
            }
        }

        // 0 prices = no data, always revert
        if (validCount_ == 0) revert SimpleStrategy_PriceCountInvalid(0, minExpectedCount_);

        // Second pass: collect valid prices into correctly sized array
        validPrices_ = new uint256[](validCount_);
        uint256 index = 0;
        for (uint256 i = 0; i < pricesCount; i++) {
            if (!Deviation.isDeviating(prices_[i], benchmark_, deviationBps_, DEVIATION_MAX)) {
                validPrices_[index] = prices_[i];
                index++;
            }
        }
    }
}
/// forge-lint: disable-end(mixed-case-function)
