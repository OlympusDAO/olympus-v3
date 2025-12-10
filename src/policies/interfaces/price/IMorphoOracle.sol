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

    // ========== FUNCTIONS ========== //

    /// @notice The collateral token address
    /// @return address The collateral token address
    function collateralToken() external pure returns (address);

    /// @notice The loan token address
    /// @return address The loan token address
    function loanToken() external pure returns (address);

    /// @notice The scale factor for the oracle
    /// @return uint256 The scale factor
    function scaleFactor() external pure returns (uint256);

    /// @notice The name of the oracle
    /// @return string The name
    function name() external pure returns (string memory);
}
