// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title IClearinghouseReserve
/// @notice Minimal interface for reading a Clearinghouse's reserve (debt) token.
interface IClearinghouseReserve {
    /// @notice Returns the reserve (debt) token of the Clearinghouse.
    function reserve() external view returns (address);
}
