/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {QuickSort} from "libraries/QuickSort.sol";
import {Deviation} from "libraries/Deviation.sol";

/// @title      SimplePriceFeedStrategy
/// @author     0xJem
/// @notice     The functions in this contract provide PRICEv2 strategies that can be used to handle
/// @notice     the results from multiple price feeds
contract SimplePriceFeedStrategy is PriceSubmodule {
    using QuickSort for uint256[];

    /// @notice     This is the expected length of bytes for the parameters to the deviation strategies
    uint8 internal constant DEVIATION_PARAMS_LENGTH = 32;

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
        major = 1;
        minor = 0;
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice        Returns a new array with only the non-zero elements of the input array
    ///
    /// @param array_  Array of uint256 values
    /// @return        Array of non-zero uint256 values
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
    /// @param prices_  Array of prices
    /// @return         The average price or 0
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
    /// @param prices_  Array of prices
    /// @return         The median price
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
    /// @param prices_  Array of prices
    /// @return         The resolved price
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

    /// @notice         This strategy returns the average of the non-zero prices in the array if
    /// @notice         the deviation from the average is greater than the deviationBps (specified in `params_`).
    ///
    /// @dev            This strategy is useful to smooth out price volatility.
    ///
    /// @dev            Zero prices in the array are ignored, to allow for
    /// @dev            handling of price lookup sources that return errors.
    /// @dev            Otherwise, an asset with any zero price would result in
    /// @dev            no price being returned at all.
    ///
    /// @dev            If no deviation is detected, the first non-zero price in the array is returned.
    /// @dev            If there are not enough non-zero array elements to calculate an average (< 2), the first non-zero price in the array (or 0) is returned.
    ///
    /// @dev            Will revert if:
    /// @dev            - The number of elements in the `prices_` array is less than 2, since it would represent a mis-configuration.
    /// @dev            - The deviationBps is `DEVIATION_MIN` or greater than or equal to `DEVIATION_MAX`.
    ///
    /// @param prices_  Array of prices
    /// @param params_  uint256 encoded as bytes
    /// @return         The resolved price
    function getAveragePriceIfDeviation(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        // Can't work with  < 2 length
        if (prices_.length < 2) revert SimpleStrategy_PriceCountInvalid(prices_.length, 2);

        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);

        // Return 0 if all prices are 0
        if (nonZeroPrices.length == 0) return 0;

        // Cache first non-zero price since the array is sorted in place
        uint256 firstNonZeroPrice = nonZeroPrices[0];

        // If there are not enough non-zero prices to calculate an average, return the first non-zero price
        if (nonZeroPrices.length == 1) return firstNonZeroPrice;

        // Get the average and abort if there's a problem
        uint256[] memory sortedPrices = nonZeroPrices.sort();
        uint256 averagePrice = _getAveragePrice(sortedPrices);

        if (params_.length != DEVIATION_PARAMS_LENGTH) revert SimpleStrategy_ParamsInvalid(params_);
        uint256 deviationBps = abi.decode(params_, (uint256));
        // Not necessary to use `Deviation.isDeviatingWithBpsCheck()` thanks to this check
        if (deviationBps <= DEVIATION_MIN || deviationBps >= DEVIATION_MAX)
            revert SimpleStrategy_ParamsInvalid(params_);

        // Check the deviation of the minimum from the average
        uint256 minPrice = sortedPrices[0];
        if (Deviation.isDeviating(minPrice, averagePrice, deviationBps, DEVIATION_MAX))
            return averagePrice;

        // Check the deviation of the maximum from the average
        uint256 maxPrice = sortedPrices[sortedPrices.length - 1];
        if (Deviation.isDeviating(maxPrice, averagePrice, deviationBps, DEVIATION_MAX))
            return averagePrice;

        // Otherwise, return the first non-zero value
        return firstNonZeroPrice;
    }

    /// @notice         This strategy returns the median of the non-zero prices in the array if
    /// @notice         the deviation from the average is greater than the deviationBps (specified in `params_`).
    ///
    /// @dev            This strategy is useful to smooth out price volatility.
    ///
    /// @dev            Zero prices in the array are ignored, to allow for
    /// @dev            handling of price lookup sources that return errors.
    /// @dev            Otherwise, an asset with any zero price would result in
    /// @dev            no price being returned at all.
    ///
    /// @dev            If no deviation is detected, the first non-zero price in the array is returned.
    /// @dev            If there are not enough non-zero array elements to calculate a median (< 3), this function falls back to `getAveragePriceIfDeviation()`.
    ///
    /// @dev            Will revert if:
    /// @dev            - The number of elements in the `prices_` array is less than 3, since it would represent a mis-configuration.
    /// @dev            - The deviationBps is 0.
    /// @dev            - The deviationBps is `DEVIATION_MIN` or greater than or equal to `DEVIATION_MAX`.
    ///
    /// @param prices_  Array of prices
    /// @param params_  uint256 encoded as bytes
    /// @return         The resolved price
    function getMedianPriceIfDeviation(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        // Misconfiguration
        if (prices_.length < 3) revert SimpleStrategy_PriceCountInvalid(prices_.length, 3);

        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);

        // Return 0 if all prices are 0
        if (nonZeroPrices.length == 0) return 0;

        // Cache first non-zero price since the array is sorted in place
        uint256 firstNonZeroPrice = nonZeroPrices[0];

        // If there are not enough non-zero prices to calculate a median, pass it on to `getAveragePriceIfDeviation()`
        if (nonZeroPrices.length < 3) return getAveragePriceIfDeviation(prices_, params_);

        uint256[] memory sortedPrices = nonZeroPrices.sort();

        // Get the average and median and abort if there's a problem
        // The following two values are guaranteed to not be 0 since sortedPrices only contains non-zero values and has a length of 3+
        uint256 averagePrice = _getAveragePrice(sortedPrices);
        uint256 medianPrice = _getMedianPrice(sortedPrices);

        if (params_.length != DEVIATION_PARAMS_LENGTH) revert SimpleStrategy_ParamsInvalid(params_);
        uint256 deviationBps = abi.decode(params_, (uint256));
        if (deviationBps <= DEVIATION_MIN || deviationBps >= DEVIATION_MAX)
            revert SimpleStrategy_ParamsInvalid(params_);

        // Check the deviation of the minimum from the average
        uint256 minPrice = sortedPrices[0];
        if (((averagePrice - minPrice) * 10000) / averagePrice > deviationBps) return medianPrice;

        // Check the deviation of the maximum from the average
        uint256 maxPrice = sortedPrices[sortedPrices.length - 1];
        if (((maxPrice - averagePrice) * 10000) / averagePrice > deviationBps) return medianPrice;

        // Otherwise, return the first non-zero value
        return firstNonZeroPrice;
    }

    /// @notice         This strategy returns the average of the non-zero prices in the array.
    /// @dev            Return 0 if all prices in the array are zero. This ensures that a situation
    /// @dev            where all price feeds are down is handled gracefully.
    ///
    /// @dev            Will revert if:
    /// @dev            - The number of elements in the `prices_` array is less than 2 (which would represent a mis-configuration)
    ///
    /// @dev            Zero prices in the array are ignored, to allow for
    /// @dev            handling of price lookup sources that return errors.
    /// @dev            Otherwise, an asset with any zero price would result in
    /// @dev            no price being returned at all.
    ///
    /// @param prices_  Array of prices
    /// @return         The resolved price
    function getAveragePrice(uint256[] memory prices_, bytes memory) public pure returns (uint256) {
        // Handle misconfiguration
        if (prices_.length < 2) revert SimpleStrategy_PriceCountInvalid(prices_.length, 2);

        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);

        return _getAveragePrice(nonZeroPrices);
    }

    /// @notice         This strategy returns the median of the non-zero prices in the array.
    /// @dev            If the array has an even number of non-zero prices, the average of the two middle
    /// @dev            prices is returned.
    ///
    /// @dev            Zero prices in the array are ignored, to allow for
    /// @dev            handling of price lookup sources that return errors.
    /// @dev            Otherwise, an asset with any zero price would result in
    /// @dev            no price being returned at all.
    ///
    /// @dev            If there are not enough non-zero array elements to calculate a median (< 3), the values are passed on to `getAveragePrice()`.
    ///
    /// @dev            Will revert if:
    /// @dev            - The number of elements in the `prices_` array is less than 3, since it would represent a mis-configuration.
    ///
    /// @param prices_  Array of prices
    /// @return         The resolved price
    function getMedianPrice(uint256[] memory prices_, bytes memory) public pure returns (uint256) {
        // Misconfiguration
        if (prices_.length < 3) revert SimpleStrategy_PriceCountInvalid(prices_.length, 3);

        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);

        uint256 nonZeroPricesLen = nonZeroPrices.length;
        // Can only calculate a median if there are 3+ non-zero prices
        if (nonZeroPricesLen == 0) return 0;
        if (nonZeroPricesLen < 3) return getAveragePrice(prices_, "");

        // Sort the prices
        uint256[] memory sortedPrices = nonZeroPrices.sort();

        return _getMedianPrice(sortedPrices);
    }
}
