// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IReEnabler
/// @notice The external interface of a contract that exposes a parameterless `reEnable`
///         entry point.
interface IReEnabler {
    // ========== ERRORS ========== //

    /// @notice Thrown when `reEnable` is invoked on a contract that has never been enabled.
    error NeverEnabled();

    // ========== STATE-CHANGING FUNCTIONS ========== //

    /// @notice Returns the contract to the enabled state without consuming a calldata payload.
    function reEnable() external;
}
