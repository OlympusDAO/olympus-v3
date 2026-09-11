// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Config Operator
/// @notice Shared surface for contracts that delegate configuration changes to one operator.
interface IConfigOperator {
    // ========== ERRORS ========== //

    /// @notice Thrown when an account is not the configured operator or cannot rotate it.
    /// @param caller_ Unauthorized account.
    error ConfigOperator_Unauthorized(address caller_);

    /// @notice Thrown when the operator to set is the one already configured. The zero address
    ///         is a value here too: revoking an operator that is already unset reverts.
    error ConfigOperator_Unchanged();

    // ========== EVENTS ========== //

    /// @notice Emitted when the delegated configuration operator changes.
    /// @param configOperator New operator, or zero when delegated access is revoked.
    event ConfigOperatorSet(address indexed configOperator);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the address allowed to execute delegated configuration changes.
    /// @return configOperator_ Config operator, or zero when delegated access is revoked.
    function configOperator() external view returns (address configOperator_);

    // ========== STATE-CHANGING FUNCTIONS ========== //

    /// @notice Immediately replaces the delegated configuration operator.
    /// @dev The implementation defines caller authorization. Setting zero revokes delegated
    ///      access. Setting the operator already configured reverts with
    ///      `ConfigOperator_Unchanged`, after the authorization check.
    /// @param configOperator_ New config operator address.
    function setConfigOperator(address configOperator_) external;
}
