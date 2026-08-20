// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title IBurnableERC20
/// @notice The minimal interface for an ERC20 token exposing a self-burn function.
interface IBurnableERC20 {
    /// @notice Burns the `amount_` tokens held by the caller.
    /// @param amount_ The number of the tokens to burn.
    function burn(uint256 amount_) external;
}
