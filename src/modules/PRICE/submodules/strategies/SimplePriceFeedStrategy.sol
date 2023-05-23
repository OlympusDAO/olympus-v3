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
        return toSubKeycode("PRICE.SMPLSTRGY");
    }

    // ========== STRATEGY FUNCTIONS ========== //

    /// @notice Returns the first price in the array
    /// @dev Reverts if:
    /// - The prices_ array is empty
    ///
    /// @param prices_ Array of prices
    /// @param params_ Unused
    /// @return price_ The resolved price
    function getFirstPrice(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        // Can't work with 0 length
        if (prices_.length == 0) revert SimpleStrategy_PriceCountInvalid();

        // Return error if price is 0
        if (prices_[0] == 0) revert SimpleStrategy_PriceZero();

        return prices_[0];
    }

    /// @notice This strategy returns the average of the prices in the array if
    /// the deviation from the average is greater than the deviationBps (specified in params_).
    ///
    /// @dev If no deviation is detected, the first price in the array is returned.
    /// This strategy is useful to smooth out price volatility
    ///
    /// Will revert if:
    /// - The number of elements in the prices_ array is less than 2
    /// - Any price in the array is 0 (since it uses getAveragePrice)
    /// - The deviationBps is 0
    ///
    /// @param prices_ Array of prices
    /// @param params_ DeviationParams struct encoded as bytes
    /// @return price_ The resolved price
    function getAverageIfDeviation(
        uint256[] memory prices_,
        bytes memory params_
    ) public view returns (uint256) {
        // Can't work with  < 2 length
        if (prices_.length < 2) revert SimpleStrategy_PriceCountInvalid();

        // Get the average and abort if there's a problem
        uint256[] memory sortedPrices = QuickSort.sort(prices_);
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
        return prices_[0];
    }

    /// @notice This strategy returns the median of the prices in the array if
    /// the deviation from the average is greater than the deviationBps (specified in params_).
    ///
    /// @dev If no deviation is detected, the first price in the array is returned.
    /// This strategy is useful to smooth out price volatility
    ///
    /// Will revert if:
    /// - The number of elements in the prices_ array is less than 2
    /// - Any price in the array is 0 (since it uses getAveragePrice)
    /// - The deviationBps is 0
    ///
    /// @param prices_ Array of prices
    /// @param params_ DeviationParams struct encoded as bytes
    /// @return price_ The resolved price
    function getMedianIfDeviation(
        uint256[] memory prices_,
        bytes memory params_
    ) public view returns (uint256) {
        // Can't work with  < 2 length
        if (prices_.length < 2) revert SimpleStrategy_PriceCountInvalid();

        // Get the average and median and abort if there's a problem
        uint256[] memory sortedPrices = QuickSort.sort(prices_);
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

    /// @notice This strategy returns the average of the prices in the array.
    /// @dev Will revert if:
    /// - The number of elements in the prices_ array is 0
    /// - Any price in the array is 0
    ///
    /// @param prices_ Array of prices
    /// @param params_ Unused
    /// @return price_ The resolved price
    function getAveragePrice(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        uint256 pricesLen = prices_.length;
        // Can't calculate the average if there are no prices
        if (pricesLen == 0) revert SimpleStrategy_PriceCountInvalid();

        uint256 priceTotal;
        for (uint256 i = 0; i < pricesLen; i++) {
            // Can't calculate the average if a price feed has not returned a value
            if (prices_[i] == 0) revert SimpleStrategy_PriceZero();

            priceTotal += prices_[i];
        }

        return priceTotal / pricesLen;
    }

    /// @notice This strategy returns the median of the prices in the array.
    /// @dev If the array has an even number of prices, the average of the two middle prices is returned.
    ///
    /// Will revert if:
    /// - The number of elements in the prices_ array is 0
    /// - Any price in the array is 0
    ///
    /// @param prices_ Array of prices
    /// @param params_ Unused
    /// @return price_ The resolved price
    function getMedianPrice(
        uint256[] memory prices_,
        bytes memory params_
    ) public pure returns (uint256) {
        uint256 pricesLen = prices_.length;
        // Can only calculate a median if there are 3+ prices
        if (pricesLen < 3) return getAveragePrice(prices_, params_);

        // Sort the prices
        uint256[] memory sortedPrices = QuickSort.sort(prices_);

        // Abort if there are zero prices
        for (uint256 i = 0; i < pricesLen; i++) {
            if (sortedPrices[i] == 0) revert SimpleStrategy_PriceZero();
        }

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
