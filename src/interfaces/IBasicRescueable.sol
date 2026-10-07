// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title IBasicRescueable
/// @notice Interface for contracts that allow a privileged rescue of accidentally-sent assets.
/// @dev Unlike `IRescueable`, the rescue does not take a recipient argument: the destination of
///      the rescued balance is determined entirely by the implementation.
interface IBasicRescueable {
    /// @notice Rescues `token_` assets accidentally sent to this contract.
    /// @dev The implementation is expected to gate the caller and may reject, or cap the rescued
    ///      amount for, assets that are tracked by its internal accounting.
    /// @param token_ The token to rescue, or
    ///        the EIP-7528 native sentinel for the native asset (if implemented).
    function rescue(address token_) external;
}
