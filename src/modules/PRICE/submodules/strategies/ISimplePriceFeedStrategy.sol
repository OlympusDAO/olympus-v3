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

    /// @notice Returns the average of prices that do not deviate from a benchmark
    ///
    /// @param  prices_  Array of prices from multiple feeds
    /// @param  params_  Encoded DeviationParams struct (64 bytes)
    /// @return price    The resolved price (average of non-deviating prices)
    function getAveragePriceExcludingDeviations(
        uint256[] memory prices_,
        bytes memory params_
    ) external pure returns (uint256 price);
}
