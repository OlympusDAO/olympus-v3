// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title IEnabler
/// @notice Interface for contracts that can be enabled and disabled
/// @dev    This is designed for usage by periphery contracts that cannot inherit from `PolicyEnabler`. Authorization is deliberately left open to the implementing contract.
interface IEnabler {
    // ============ EVENTS ============ //

    /// @notice Emitted when the contract is enabled
    event Enabled();

    /// @notice Emitted when the contract is disabled
    event Disabled();

    // ============ ERRORS ============ //

    /// @notice Thrown when the contract is not enabled
    error NotEnabled();

    /// @notice Thrown when the contract is not disabled
    error NotDisabled();

    // ============ FUNCTIONS ============ //

    /// @notice         Returns true if the contract is enabled
    /// @return enabled True if the contract is enabled, false otherwise
    function isEnabled() external view returns (bool enabled);

    /// @notice             Enables the contract
    /// @dev                Implementing contracts should implement permissioning logic
    ///
    /// @param enableData_  Optional data to pass to a custom enable function
    function enable(bytes calldata enableData_) external;

    /// @notice             Disables the contract
    /// @dev                Implementing contracts should implement permissioning logic
    ///
    /// @param disableData_ Optional data to pass to a custom disable function
    function disable(bytes calldata disableData_) external;
}
