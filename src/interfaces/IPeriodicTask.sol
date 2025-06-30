// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title  IPeriodicTask
/// @notice Interface for a contract that can perform a task at a specified interval
interface IPeriodicTask {
    // ========== FUNCTIONS ========== //

    /// @notice Executes the periodic task
    /// @dev    Guidelines for implementing functions:
    /// @dev    - The implementing function is responsible for checking if the task is due to be executed.
    /// @dev    - The implementing function should avoid reverting, as that would cause the calling contract to revert.
    /// @dev    - The implementing function should be protected by a role check for the "heart" role.
    function execute() external;
}
