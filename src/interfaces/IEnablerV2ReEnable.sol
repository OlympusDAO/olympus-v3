// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IEnablerV2} from "src/interfaces/IEnablerV2.sol";

/// @title IEnablerV2ReEnable
/// @notice The external interface of a parameterless re-enable extension for an
///         `IEnablerV2` implementation.
/// @dev The extension is intended to allow a caller distinct from the principal
///      enabler, such as a manager that does not hold the admin role, to return
///      the contract to the enabled state after a disable without supplying the
///      calldata payload that the original `enable` would require. The extension
///      is therefore only meaningful once the contract has been enabled at least
///      once through the standard `IEnabler.enable` entry point.
interface IEnablerV2ReEnable is IEnablerV2 {
    // ========== ERRORS ========== //

    /// @notice Thrown when `reEnable` is invoked on a contract that has never been
    ///         enabled.
    error NeverEnabled();

    // ========== STATE-CHANGING FUNCTIONS ========== //

    /// @notice Returns the contract to the enabled state without consuming a calldata
    ///         payload.
    /// @dev The implementation is expected to gate the call behind its own access
    ///      control and to revert when the contract is currently enabled or when it
    ///      has never been enabled.
    function reEnable() external;
}
