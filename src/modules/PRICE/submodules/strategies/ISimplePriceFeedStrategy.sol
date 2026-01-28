// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title Interface for simple price aggregation strategies
interface ISimplePriceFeedStrategy {
    /// @notice Parameters for deviation-based price aggregation strategies
    ///
    /// @param  deviationBps                Deviation threshold in basis points (100 = 1%, max 9999)
    /// @param  revertOnInsufficientCount   If true, revert when there are an insufficient number of valid prices. Otherwise, a best effort is made to return a price.
    struct DeviationParams {
        uint16 deviationBps;
        bool revertOnInsufficientCount;
    }

    /// @notice Returns the average of non-zero prices in the array
    ///
    /// @param  prices_  Array of prices from multiple feeds (minimum 2 elements)
    /// @param  params_  Bool encoded as bytes - must be exactly 32 bytes
    /// @return price    The resolved price (average of non-zero prices)
    function getAveragePrice(
        uint256[] memory prices_,
        bytes memory params_
    ) external pure returns (uint256 price);

    /// @notice Returns the median of non-zero prices in the array
    ///
    /// @param  prices_  Array of prices from multiple feeds (minimum 3 elements)
    /// @param  params_  Bool encoded as bytes - must be exactly 32 bytes
    /// @return price    The resolved price (median of non-zero prices)
    function getMedianPrice(
        uint256[] memory prices_,
        bytes memory params_
    ) external pure returns (uint256 price);

    /// @notice Returns the average of prices, excluding those deviating from the average benchmark
    ///
    /// @dev    Iteratively filters out deviating prices and returns the average of remaining prices.
    /// @dev    This is a "consensus" strategy - outliers are removed until all remaining prices agree.
    ///
    /// @param  prices_  Array of prices from multiple feeds (minimum 3 elements)
    /// @param  params_  Encoded DeviationParams struct (64 bytes)
    /// @return price    The resolved price (average of non-deviating prices)
    function getAveragePriceExcludingDeviations(
        uint256[] memory prices_,
        bytes memory params_
    ) external pure returns (uint256 price);

    /// @notice Returns the average of prices, or the average if min/max deviate from the average benchmark
    ///
    /// @dev    Checks if min or max prices deviate from the average. Returns average if deviation detected, otherwise first price.
    /// @dev    This is a "deviation check" strategy - single check to decide between two return values.
    ///
    /// @param  prices_  Array of prices from multiple feeds (minimum 2 elements)
    /// @param  params_  Encoded DeviationParams struct (64 bytes)
    /// @return price    The resolved price (average if deviation detected, first price otherwise)
    function getAveragePriceIfDeviation(
        uint256[] memory prices_,
        bytes memory params_
    ) external pure returns (uint256 price);

    /// @notice Returns the first non-zero price, or the median if prices deviate from the average
    ///
    /// @dev    Checks if min or max prices deviate from the average. Returns median if deviation detected, otherwise first price.
    ///
    /// @param  prices_  Array of prices from multiple feeds (minimum 3 elements)
    /// @param  params_  Encoded DeviationParams struct (64 bytes)
    /// @return price    The resolved price (median if deviation detected, first price otherwise)
    function getMedianPriceIfDeviation(
        uint256[] memory prices_,
        bytes memory params_
    ) external pure returns (uint256 price);
}
