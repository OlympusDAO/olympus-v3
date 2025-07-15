// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/// @title IReserveWrapper
/// @notice Interface for the ReserveWrapper policy
interface IReserveWrapper {
    // ========== EVENTS ========== //

    event ReserveWrapped(address indexed reserve, address indexed sReserve, uint256 amount);

    // ========== ERRORS ========== //

    error ReserveWrapper_ZeroAddress();

    error ReserveWrapper_AssetMismatch();

    // ========== FUNCTIONS ========== //

    /// @notice Returns the address of the reserve token
    function getReserve() external view returns (address);

    /// @notice Returns the address of the sReserve token
    function getSReserve() external view returns (address);
}
