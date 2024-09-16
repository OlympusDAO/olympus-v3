// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "src/Kernel.sol";

/// @title  Olympus Clearinghouse Registry
/// @notice Olympus Clearinghouse Registry (Module) Contract
/// @dev    The Olympus Clearinghouse Registry Module tracks the lending facilities that the Olympus
///         protocol deploys to satisfy the Cooler Loan demand. This allows for a single-soure of truth
///         for reporting purposes around the total Treasury holdings as well as its projected receivables.
abstract contract CHREGv1 is Module {
    // =========  ERRORS ========= //

    error CHREG_InvalidConstructor();
    error CHREG_NotActivated(address clearinghouse_);
    error CHREG_AlreadyActivated(address clearinghouse_);

    // ========= EVENTS ========= //

    /// @notice Logs whenever a Clearinghouse is activated.
    ///         If it is the first time, it is also added to the registry.
    event ClearinghouseActivated(address indexed clearinghouse);

    /// @notice Logs whenever an active Clearinghouse is deactivated.
    event ClearinghouseDeactivated(address indexed clearinghouse);

    // ========= STATE ========= //

    /// @notice Count of active and historical clearinghouses.
    /// @dev    These are useless variables in contracts, but useful for any frontends
    ///         or off-chain requests where the array is not easily accessible.
    uint256 public activeCount;
    uint256 public registryCount;

    /// @notice Tracks the addresses of all the active Clearinghouses.
    address[] public active;

    /// @notice Historical record of all the Clearinghouse addresses.
    address[] public registry;

    // ========= FUNCTIONS ========= //

    /// @notice Adds a Clearinghouse to the registry.
    ///         Only callable by permissioned policies.
    /// @param  clearinghouse_ The address of the clearinghouse.
    function activateClearinghouse(address clearinghouse_) external virtual;

    /// @notice Deactivates a clearinghouse from the registry.
    ///         Only callable by permissioned policies.
    /// @param  clearinghouse_ The address of the clearginhouse.
    function deactivateClearinghouse(address clearinghouse_) external virtual;
}
