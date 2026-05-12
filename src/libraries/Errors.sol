// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title Errors
/// @notice Common custom errors shared across contracts.
library Errors {
    /// @notice Thrown when the account is not authorized to perform the action.
    /// @dev Intended for access control checks in contracts that do not use the `ROLES` module.
    /// @param account The unauthorized account.
    /// @param reason An identifier of the role or capability the account was expected to hold (e.g. "owner").
    error Unauthorized(address account, string reason);

    /// @notice Thrown when a recipient address is invalid (e.g. the zero address).
    error InvalidRecipient();

    /// @notice Thrown when an input argument fails.
    /// @param parameter A short identifier of the offending input (e.g. the parameter name).
    error BadInput(string parameter);
}
