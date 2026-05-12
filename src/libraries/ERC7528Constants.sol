// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/// @title ERC7528Constants
/// @notice Constants defined by EIP-7528 for representing the native asset in interfaces
///         that otherwise expect an ERC20 address.
/// @dev See https://eips.ethereum.org/EIPS/eip-7528.
library ERC7528Constants {
    /// @notice Sentinel address representing the native asset.
    address internal constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
}
