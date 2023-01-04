// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "src/Kernel.sol";

/// @title  Olympus Liquidity AMO Registry
/// @notice Olympus Liquidity AMO Registry (Module) Contract
/// @dev    The Olympus Liquidity AMO Registry Module tracks the single-sided liquidity AMOs
///         that are approved to be used by the Olympus protocol. This allows for a single-soure
///         of truth for reporting purposes around total OHM deployed and net emissions.
abstract contract LQREGv1 is Module {
    // ========= EVENTS ========= //

    event AmoAdded(address indexed amo);
    event AmoRemoved(address indexed amo);

    // ========= ERRORS ========= //

    error LQREG_RemovalMismatch();

    // ========= STATE ========= //

    /// @notice Count of active AMOs
    /// @dev    This is a useless variable in contracts but useful for any frontends or
    ///         off-chain requests where the array is not easily accessible.
    uint256 public activeAMOCount;

    /// @notice Tracks all active AMOs
    address[] public activeAMOs;

    // ========= FUNCTIONS ========= //

    /// @notice Adds an AMO to the registry
    /// @param amo_ The address of the AMO to add
    function addAMO(address amo_) external virtual;

    /// @notice Removes an AMO from the registry
    /// @param amo_ The address of the AMO to remove
    function removeAMO(uint256 index_, address amo_) external virtual;
}
