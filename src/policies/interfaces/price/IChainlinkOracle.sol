// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";

/// @title  IChainlinkOracle
/// @author OlympusDAO
/// @notice Interface for a Chainlink-compatible oracle
interface IChainlinkOracle is AggregatorV2V3Interface {
    // ========== ERRORS ========== //

    /// @notice Thrown when the oracle is not enabled
    error ChainlinkOracle_NotEnabled();

    /// @notice Thrown when requested round data is not available
    error ChainlinkOracle_NoDataPresent();

    /// @notice Thrown when the last timestamp is not consistent
    ///
    /// @param  baseTimestamp   The timestamp of the base token
    /// @param  quoteTimestamp  The timestamp of the quote token
    error ChainlinkOracle_InconsistentTimestamps(uint48 baseTimestamp, uint48 quoteTimestamp);

    // ========== FUNCTIONS ========== //

    /// @notice The base token address
    ///
    /// @return baseToken_  The base token address
    function baseToken() external view returns (address baseToken_);

    /// @notice The quote token address
    ///
    /// @return quoteToken_ The quote token address
    function quoteToken() external view returns (address quoteToken_);

    /// @notice The maximum allowed age for cached prices
    ///
    /// @return maxAge_  The configured maximum cache age in seconds
    function maxAge() external view returns (uint48 maxAge_);

    /// @notice The name of the oracle
    ///
    /// @return name_   The name
    function name() external view returns (string memory name_);

    /// @notice Returns whether the feed should be considered stale for round consumers.
    ///
    /// @return isStale_    true if the feed is stale or has mismatched timestamps
    function isStale() external view returns (bool isStale_);
}
