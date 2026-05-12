// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IRescueable
/// @notice Interface for contracts that allow privileged rescue of accidentally-sent assets.
/// @dev The native asset is identified using the EIP-7528 sentinel address
///      (`ERC7528Constants.NATIVE_ASSET`).
interface IRescueable {
    // ========= FUNCTIONS ========= //

    /// @notice Rescues assets accidentally sent to this contract.
    ///
    /// @param token_ The token to rescue, or the EIP-7528 native sentinel for the native asset.
    /// @param to_ The recipient of the rescued assets.
    function rescue(address token_, address payable to_) external;
}
