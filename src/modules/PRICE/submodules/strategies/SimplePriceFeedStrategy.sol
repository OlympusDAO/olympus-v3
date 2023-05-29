/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {QuickSort} from "libraries/QuickSort.sol";

contract SimplePriceFeedStrategy is PriceSubmodule {
    // ========== ERRORS ========== //

    error SimpleStrategy_PriceCountInvalid();
    error SimpleStrategy_PriceZero();
    error SimpleStrategy_ParamsRequired();

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.SIMPLESTRATEGY");
    }

    // ========== HELPER FUNCTIONS ========== //

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
    /// @return uint256 The resolved price
    function getFirstNonZeroPrice(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        // Can't work with 0 length
        if (prices_.length == 0) revert SimpleStrategy_PriceCountInvalid();

        // Iterate through the array and return the first non-zero price
        for (uint256 i = 0; i < prices_.length; i++) {
            if (prices_[i] != 0) return prices_[i];
        }

        // If we have reached this far, there are only 0 prices in the array
        return 0;
    }

    /// @notice         This strategy returns the average of the non-zero prices in the array if
    ///                 the deviation from the average is greater than the deviationBps (specified in params_).
    ///
    ///                 @dev This strategy is useful to smooth out price volatility.
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
    ///                 - The number of elements in the prices_ array is less than 2, since it would represent a mis-configuration.
    ///                 - The deviationBps is 0.
    ///
    /// @param prices_  Array of prices
    /// @param params_  DeviationParams struct encoded as bytes
    /// @return uint256 The resolved price
    function getAverageIfDeviation(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        // Can't work with  < 2 length
        if (prices_.length < 2) revert SimpleStrategy_PriceCountInvalid();

        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);

        // If there are no non-zero prices, return 0
        if (nonZeroPrices.length == 0) return 0;

        // If there are not enough non-zero prices to calculate an average, return the first non-zero price
        if (nonZeroPrices.length == 1) return nonZeroPrices[0];

        // Get the average and abort if there's a problem
        uint256[] memory sortedPrices = QuickSort.sort(nonZeroPrices);
        uint256 averagePrice = getAveragePrice(sortedPrices, params_);

        if (params_.length == 0) revert SimpleStrategy_ParamsRequired();
        uint256 deviationBps = abi.decode(params_, (uint256));
        if (deviationBps == 0) revert SimpleStrategy_ParamsRequired();

        // Check the deviation of the minimum from the average
        uint256 minPrice = sortedPrices[0];
        if (((averagePrice - minPrice) * 10000) / averagePrice > deviationBps) return averagePrice;

        // Check the deviation of the maximum from the average
        uint256 maxPrice = sortedPrices[sortedPrices.length - 1];
        if (((maxPrice - averagePrice) * 10000) / maxPrice > deviationBps) return averagePrice;

        // Otherwise, return the first value
        return nonZeroPrices[0];
    }

    /// @notice         This strategy returns the median of the non-zero prices in the array if
    ///                 the deviation from the average is greater than the deviationBps (specified in params_).
    ///
    /// @dev            If no deviation is detected, the first price in the array is returned.
    ///                 This strategy is useful to smooth out price volatility.
    ///
    ///                 Non-zero prices in the array are ignored, to allow for
    ///                 handling of price lookup sources that return errors.
    ///                 Otherwise, an asset with any zero price would result in
    ///                 no price being returned at all.
    ///
    ///                 Will revert if:
    ///                 - The number of non-zero elements in the prices_ array is less than 2
    ///                 - The deviationBps is 0
    ///
    /// @param prices_  Array of prices
    /// @param params_  DeviationParams struct encoded as bytes
    /// @return uint256 The resolved price
    function getMedianIfDeviation(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);

        // Can't work with  < 2 length
        if (nonZeroPrices.length < 2) revert SimpleStrategy_PriceCountInvalid();

        // Get the average and median and abort if there's a problem
        uint256[] memory sortedPrices = QuickSort.sort(nonZeroPrices);
        uint256 averagePrice = getAveragePrice(sortedPrices, params_);
        uint256 medianPrice = getMedianPrice(sortedPrices, params_);

        if (params_.length == 0) revert SimpleStrategy_ParamsRequired();
        uint256 deviationBps = abi.decode(params_, (uint256));
        if (deviationBps == 0) revert SimpleStrategy_ParamsRequired();

        // Check the deviation of the minimum from the average
        uint256 minPrice = sortedPrices[0];
        if (((averagePrice - minPrice) * 10000) / averagePrice > deviationBps) return medianPrice;

        // Check the deviation of the maximum from the average
        uint256 maxPrice = sortedPrices[sortedPrices.length - 1];
        if (((maxPrice - averagePrice) * 10000) / maxPrice > deviationBps) return medianPrice;

        // Otherwise, return the first value
        return prices_[0];
    }

    /// @notice         This strategy returns the average of the non-zero prices in the array.
    ///
    /// @dev            Will revert if:
    ///                 - The number of non-zero elements in the prices_ array is 0
    ///
    ///                 Non-zero prices in the array are ignored, to allow for
    ///                 handling of price lookup sources that return errors.
    ///                 Otherwise, an asset with any zero price would result in
    ///                 no price being returned at all.
    ///
    /// @param prices_  Array of prices
    /// @param params_  Unused
    /// @return uint256 The resolved price
    function getAveragePrice(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);

        uint256 pricesLen = nonZeroPrices.length;
        // Can't calculate the average if there are no prices
        if (pricesLen == 0) revert SimpleStrategy_PriceCountInvalid();

        uint256 priceTotal;
        for (uint256 i = 0; i < pricesLen; i++) {
            priceTotal += nonZeroPrices[i];
        }

        return priceTotal / pricesLen;
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
    ///                 Will revert if:
    ///                 - The number of non-zero elements in the prices_ array is 0
    ///
    /// @param prices_  Array of prices
    /// @param params_  Unused
    /// @return uint256 The resolved price
    function getMedianPrice(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        uint256[] memory nonZeroPrices = _getNonZeroArray(prices_);

        uint256 pricesLen = nonZeroPrices.length;
        // Can only calculate a median if there are 3+ prices
        if (pricesLen < 3) return getAveragePrice(nonZeroPrices, params_);

        // Sort the prices
        uint256[] memory sortedPrices = QuickSort.sort(nonZeroPrices);

        // If there are an even number of prices, return the average of the two middle prices
        if (pricesLen % 2 == 0) {
            uint256 middlePrice1 = sortedPrices[pricesLen / 2 - 1];
            uint256 middlePrice2 = sortedPrices[pricesLen / 2];
            return (middlePrice1 + middlePrice2) / 2;
        }

        // Otherwise return the median price
        return sortedPrices[(pricesLen - 1) / 2];
    }
}
