// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IOracle} from "src/interfaces/morpho/IOracle.sol";

/// @title  IMorphoOracle
/// @author OlympusDAO
/// @notice Interface for a Morpho oracle
interface IMorphoOracle is IOracle {
    // ========== ERRORS ========== //

    /// @notice Thrown when the oracle is not enabled
    error MorphoOracle_NotEnabled();

    /// @notice Thrown when collateral/loan timestamps resolve to different sources/times
    ///
    /// @param  collateralTimestamp_    The resolved collateral timestamp
    /// @param  loanTimestamp_          The resolved loan timestamp
    error MorphoOracle_InconsistentTimestamps(uint48 collateralTimestamp_, uint48 loanTimestamp_);

    /// @notice Thrown when the cached prices are stale
    ///
    /// @param  timestamp_  The shared cached timestamp used for collateral and loan prices
    /// @param  maxAge_     The configured maximum cache age
    error MorphoOracle_Stale(uint48 timestamp_, uint48 maxAge_);

    // ========== FUNCTIONS ========== //

    /// @notice The collateral token address
    ///
    /// @return collateralToken_    The collateral token address
    function collateralToken() external view returns (address collateralToken_);

    /// @notice The loan token address
    ///
    /// @return loantoken_  The loan token address
    function loanToken() external view returns (address loantoken_);

    /// @notice The maximum allowed age for cached prices
    ///
    /// @return maxAge_  The configured maximum cache age in seconds
    function maxAge() external view returns (uint48 maxAge_);

    /// @notice The scale factor for the oracle
    ///
    /// @return scaleFactor_    The scale factor
    function scaleFactor() external view returns (uint256 scaleFactor_);

    /// @notice The name of the oracle
    ///
    /// @return name_   The name
    function name() external view returns (string memory name_);

    /// @notice Returns whether the cached feed state is stale.
    ///
    /// @return isStale_    Returns true if timestamps are inconsistent, unset, or older than maxAge.
    function isStale() external view returns (bool isStale_);

    /// @notice Returns the shared cached timestamp used for quote resolution.
    ///
    /// @return timestamp_  Returns the timestamp of the cached prices
    function timestamp() external view returns (uint48 timestamp_);
}
