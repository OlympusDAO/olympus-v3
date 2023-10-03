// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "src/Kernel.sol";

/// @title  Olympus Clearinghouse Registry
/// @notice Olympus Clearinghouse Registry (Module) Contract
/// @dev    The Olympus Clearinghouse Registry Module tracks the leanding facilities that the Olympus
///         protocol deploys to satisfy the Cooler Loan demand. This allows for a single-soure of truth
///         for reporting purposes around the total Treasury holdings as well as its projected receivables.
abstract contract CHREGv1 is Module {
    // =========  ERRORS ========= //

    error Module_OnlyKernelExecutor(address caller_);

    // ========= EVENTS ========= //

    event ClearinghouseActivated(address indexed clearinghouse);
    event ClearinghouseDeactivated(address indexed clearinghouse);

    // ========= STATE ========= //

    /// @notice Count of active clearinghouses.
    /// @dev    This is a useless variable in contracts but useful for any frontends or
    ///         off-chain requests where the array is not easily accessible.
    uint256 public activeCount;

    /// @notice Tracks the addresses of all the active Clearinghouses.
    address[] public active;

    /// @notice Historical record of all the Clearinghouse the addresses.
    address[] public registry;

    // ========= FUNCTIONS ========= //

    /// @notice Modifier to check if caller is the kerneñ executor.
    modifier onlyKernelExecutor() {
        if (msg.sender != kernel.executor()) revert Module_OnlyKernelExecutor(msg.sender);
        _;
    }

    /// @notice Adds a Clearinghouse to the registry.
    ///         Only callable by permissioned policies.
    /// @param  clearinghouse_ The address of the clearinghouse.
    function activateClearinghouse(address clearinghouse_) external virtual;

    /// @notice Adds a Clearinghouse to the registry.
    ///         Only callable by the kernel executor.
    /// @param  clearinghouse_ The address of the clearinghouse.
    function manuallyActivateClearinghouse(address clearinghouse_) external virtual;

    /// @notice Deactivates a clearinghouse from the registry.
    ///         Only callable by permissioned policies.
    /// @param  clearinghouse_ The address of the clearginhouse.
    function deactivateClearinghouse(address clearinghouse_) external virtual;

    /// @notice Deactivates a clearinghouse from the registry.
    ///         Only callable by the kernel executor.
    /// @param  clearinghouse_ The address of the clearginhouse.
    function manuallyDeactivateClearinghouse(address clearinghouse_) external virtual;
}
