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
    /// @return address The base token address
    function baseToken() external pure returns (address);

    /// @notice The quote token address
    ///
    /// @return address The quote token address
    function quoteToken() external pure returns (address);

    /// @notice The name of the oracle
    ///
    /// @return string The name
    function name() external pure returns (string memory);
}
