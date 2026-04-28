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

    /// @notice Thrown when the cached direct-pair USD legs are invalid
    error MorphoOracle_InvalidPrice();

    /// @notice Thrown when the direct pair cache timestamp is stale
    ///
    /// @param  cachedTimestamp               The cached timestamp used for the collateral/loan pair
    /// @param  latestPermissibleTimestamp    The oldest permissible timestamp (`block.timestamp - maxAge()`)
    error MorphoOracle_Stale(uint256 cachedTimestamp, uint256 latestPermissibleTimestamp);

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
    /// @return isStale_    Returns true if the pair cache is unset or older than maxAge.
    function isStale() external view returns (bool isStale_);

    /// @notice Returns the cached timestamp for the collateral/loan pair.
    ///
    /// @return timestamp_  Returns the timestamp of the cached prices
    function timestamp() external view returns (uint48 timestamp_);
}
