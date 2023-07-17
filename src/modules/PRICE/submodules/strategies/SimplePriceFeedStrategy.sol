/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {QuickSort} from "libraries/QuickSort.sol";

/// @title      SimplePriceFeedStrategy
/// @notice     The functions in this contract provide PRICEv2 strategies that can be used to handle
///             the results from multiple price feeds
contract SimplePriceFeedStrategy is PriceSubmodule {
    using QuickSort for uint256[];

    /// @notice     This is the expected length of bytes for the parameters to the deviation strategies
    uint8 internal constant DEVIATION_PARAMS_LENGTH = 32;

    // ========== ERRORS ========== //

    /// @notice                 Indicates that the number of prices provided to the strategy is invalid
    /// @param priceCount_      The number of prices provided to the strategy
    /// @param minPriceCount_   The minimum number of prices required by the strategy
    error SimpleStrategy_PriceCountInvalid(uint256 priceCount_, uint256 minPriceCount_);

    /// @notice                 Indicates that the parameters provided to the strategy are invalid
    /// @param params_          The parameters provided to the strategy
    error SimpleStrategy_ParamsInvalid(bytes params_);

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.SIMPLESTRATEGY");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice        Returns a new array with only the non-zero elements of the input array
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
    ///                 If non-zero values should not be included in the average, filter them prior.
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
    ///                 It assumes that the price array is sorted in ascending order.
    ///                 If non-zero values should not be included in the median, filter them prior.
    ///
    /// @param prices_  Array of prices
    /// @return         The median price or 0
    function _getMedianPrice(uint256[] memory prices_) internal pure returns (uint256) {
        uint256 pricesLen = prices_.length;

        // If all price feeds are down, no median can be calculated
        if (pricesLen == 0) return 0;

        // If there is only one price, return it
        if (pricesLen == 1) return prices_[0];

        // If there are an even number of prices, return the average of the two middle prices
        if (pricesLen % 2 == 0) {
            uint256 middlePrice1 = prices_[pricesLen / 2 - 1];
            uint256 middlePrice2 = prices_[pricesLen / 2];
            return (middlePrice1 + middlePrice2) / 2;
        }

        // Otherwise return the median price
        return prices_[(pricesLen - 1) / 2];
    }

    /// @notice         Returns a new array with the same values as the input array, sorted using the QuickSort library
    /// @dev            This is done to avoid unpredictable behaviour when sorting an array in-place
    /// @param array_   Array of uint256 values
    /// @return         Array of uint256 values, sorted in ascending order
    function _sort(uint256[] memory array_) internal pure returns (uint256[] memory) {
        // Create a new array of the same length
        uint256[] memory sortedArray = new uint256[](array_.length);

        // Copy the array into the new array
        for (uint256 i = 0; i < array_.length; i++) {
            sortedArray[i] = array_[i];
        }

        // Sort the new array
        sortedArray.sort();

        return sortedArray;
    }

    // ========== STRATEGY FUNCTIONS ========== //

    /// @notice         Returns the first non-zero price in the array.
    ///
    /// @dev            Reverts if:
    ///                 - The length of prices_ array is 0, which would represent a mis-configuration.
    ///
    ///                 If a non-zero price cannot be found, 0 will be returned.
    ///
    /// @param prices_  Array of prices
    /// @param params_  Unused
    /// @return         The resolved price
    function getFirstNonZeroPrice(
        uint256[] memory prices_,
        bytes memory params_
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
    ///                 the deviation from the average is greater than the deviationBps (specified in `params_`).
    ///
    /// @dev            This strategy is useful to smooth out price volatility.
    ///
    ///                 Non-zero prices in the array are ignored, to allow for
    ///                 handling of price lookup sources that return errors.
    ///                 Otherwise, an asset with any zero price would result in
    ///                 no price being returned at all.
    ///
    ///                 If no deviation is detected, the first non-zero price in the array is returned.
    ///                 If there are not enough non-zero array elements to calculate an average (< 2), the first non-zero price in the array (or 0) is returned.
    ///
    ///                 Will revert if:
    ///                 - The number of elements in the `prices_` array is less than 2, since it would represent a mis-configuration.
    ///                 - The deviationBps is 0.
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

        // If there are no non-zero prices, return 0
        if (nonZeroPrices.length == 0) return 0;

        // If there are not enough non-zero prices to calculate an average, return the first non-zero price
        uint256 firstPrice = nonZeroPrices[0];
        if (nonZeroPrices.length == 1) return firstPrice;

        // Get the average and abort if there's a problem
        // Cache first non-zero price since the array is sorted in place
        uint256 firstNonZeroPrice = nonZeroPrices[0];
        uint256[] memory sortedPrices = nonZeroPrices.sort();
        uint256 averagePrice = _getAveragePrice(sortedPrices);

        if (params_.length != DEVIATION_PARAMS_LENGTH) revert SimpleStrategy_ParamsInvalid(params_);
        uint256 deviationBps = abi.decode(params_, (uint256));
        if (deviationBps == 0) revert SimpleStrategy_ParamsInvalid(params_);

        // Check the deviation of the minimum from the average
        uint256 minPrice = sortedPrices[0];
        if (((averagePrice - minPrice) * 10000) / averagePrice > deviationBps) return averagePrice;

        // Check the deviation of the maximum from the average
        uint256 maxPrice = sortedPrices[sortedPrices.length - 1];
        if (((maxPrice - averagePrice) * 10000) / averagePrice > deviationBps) return averagePrice;

        // Otherwise, return the first non-zero value
        return firstNonZeroPrice;
    }

    /// @notice         This strategy returns the median of the non-zero prices in the array if
    ///                 the deviation from the average is greater than the deviationBps (specified in `params_`).
    ///
    /// @dev            This strategy is useful to smooth out price volatility.
    ///
    ///                 Non-zero prices in the array are ignored, to allow for
    ///                 handling of price lookup sources that return errors.
    ///                 Otherwise, an asset with any zero price would result in
    ///                 no price being returned at all.
    ///
    ///                 If no deviation is detected, the first non-zero price in the array is returned.
    ///                 If there are not enough non-zero array elements to calculate a median (< 3), the first non-zero price in the array (or 0) is returned.
    ///
    ///                 Will revert if:
    ///                 - The number of elements in the `prices_` array is less than 3, since it would represent a mis-configuration.
    ///                 - The deviationBps is 0.
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

        // If there are no non-zero prices, return 0
        if (nonZeroPrices.length == 0) return 0;

        // If there are not enough non-zero prices to calculate a median, return the first non-zero price
        uint256 firstPrice = nonZeroPrices[0];
        if (nonZeroPrices.length < 3) return firstPrice;

        // Get the average and median and abort if there's a problem

        // Cache first non-zero price since the array is sorted in place
        uint256 firstNonZeroPrice = nonZeroPrices[0];
        uint256[] memory sortedPrices = nonZeroPrices.sort();

        // The following two values are guaranteed to not be 0 since sortedPrices only contains non-zero values and has a length of 3+
        uint256 averagePrice = _getAveragePrice(sortedPrices);
        uint256 medianPrice = _getMedianPrice(sortedPrices);

        if (params_.length != DEVIATION_PARAMS_LENGTH) revert SimpleStrategy_ParamsInvalid(params_);
        uint256 deviationBps = abi.decode(params_, (uint256));
        if (deviationBps == 0) revert SimpleStrategy_ParamsInvalid(params_);

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
    ///
    /// @dev            If there are no non-zero prices in the array, 0 will be returned. This ensures that a situation
    //                  where all price feeds are down is handled gracefully.
    ///
    ///                 Will revert if:
    ///                 - The number of elements in the `prices_` array is less than 2 (which would represent a mis-configuration)
    ///
    ///                 Non-zero prices in the array are ignored, to allow for
    ///                 handling of price lookup sources that return errors.
    ///                 Otherwise, an asset with any zero price would result in
    ///                 no price being returned at all.
    ///
    /// @param prices_  Array of prices
    /// @param params_  Unused
    /// @return         The resolved price
    function getAveragePrice(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        // Handle misconfiguration
        if (prices_.length < 2) revert SimpleStrategy_PriceCountInvalid(prices_.length, 2);

        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);

        return _getAveragePrice(nonZeroPrices);
    }

    /// @notice         This strategy returns the median of the non-zero prices in the array.
    ///
    /// @dev            If the array has an even number of non-zero prices, the average of the two middle
    ///                 prices is returned.
    ///
    ///                 Non-zero prices in the array are ignored, to allow for
    ///                 handling of price lookup sources that return errors.
    ///                 Otherwise, an asset with any zero price would result in
    ///                 no price being returned at all.
    ///
    ///                 If there are not enough non-zero array elements to calculate a median (< 3), the first non-zero price is returned.
    ///
    ///                 Will revert if:
    ///                 - The number of elements in the `prices_` array is less than 3, since it would represent a mis-configuration.
    ///
    /// @param prices_  Array of prices
    /// @param params_  Unused
    /// @return         The resolved price
    function getMedianPrice(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        // Misconfiguration
        if (prices_.length < 3) revert SimpleStrategy_PriceCountInvalid(prices_.length, 3);

        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);

        uint256 nonZeroPricesLen = nonZeroPrices.length;
        // Can only calculate a median if there are 3+ non-zero prices
        if (nonZeroPricesLen == 0) return 0;
        if (nonZeroPricesLen < 3) return nonZeroPrices[0];

        // Sort the prices
        uint256[] memory sortedPrices = _sort(nonZeroPrices);

        return _getMedianPrice(sortedPrices);
    }
}
