// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title  IPeriodicTaskManager
/// @notice Interface for a contract that can manage periodic tasks with ordering capabilities
interface IPeriodicTaskManager {
    // ========== EVENTS ========== //

    /// @notice Emitted when a periodic task is added
    ///
    /// @param task_ The address of the periodic task
    /// @param index_ The index where the task was added
    event PeriodicTaskAdded(address indexed task_, bytes4 customSelector_, uint256 indexed index_);

    /// @notice Emitted when a periodic task is removed
    ///
    /// @param task_ The address of the periodic task
    /// @param index_ The index where the task was removed from
    event PeriodicTaskRemoved(address indexed task_, uint256 indexed index_);

    // ========== ERRORS ========== //

    /// @notice Error thrown when trying to remove a task that doesn't exist
    error PeriodicTaskManager_TaskNotFound(address task_);

    /// @notice Error thrown when trying to add a task that already exists
    error PeriodicTaskManager_TaskAlreadyExists(address task_);

    /// @notice Error thrown when the provided task address is zero
    error PeriodicTaskManager_ZeroAddress();

    /// @notice Error thrown when the provided task does not implement the IPeriodicTask interface
    error PeriodicTaskManager_NotPeriodicTask(address task_);

    /// @notice Error thrown when a custom selector fails
    error PeriodicTaskManager_CustomSelectorFailed(
        address task_,
        bytes4 customSelector_,
        bytes reason_
    );

    // ========== TASK MANAGEMENT FUNCTIONS ========== //

    /// @notice Adds a periodic task to the end of the task list
    /// @dev    This function should be protected by a role check for the "admin" role
    ///
    /// @param  task_ The periodic task to add
    function addPeriodicTask(address task_) external;

    /// @notice Adds a periodic task at a specific index in the task list
    /// @dev    This function should be protected by a role check for the "admin" role
    /// @dev    If the index is greater than the current length, the task will be added at the end
    ///
    /// @param  task_           The periodic task to add
    /// @param  customSelector_ The custom selector to use for the task (or 0)
    /// @param  index_          The index where to insert the task
    function addPeriodicTaskAtIndex(address task_, bytes4 customSelector_, uint256 index_) external;

    /// @notice Removes a periodic task from the task list
    /// @dev    This function should be protected by a role check for the "admin" role
    ///
    /// @param  task_ The periodic task to remove
    function removePeriodicTask(address task_) external;

    /// @notice Removes a periodic task at a specific index
    /// @dev    This function should be protected by a role check for the "admin" role
    ///
    /// @param  index_ The index of the task to remove
    function removePeriodicTaskAtIndex(uint256 index_) external;

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Gets the total number of periodic tasks
    ///
    /// @return _taskCount  The number of periodic tasks
    function getPeriodicTaskCount() external view returns (uint256 _taskCount);

    /// @notice Gets a periodic task at a specific index
    ///
    /// @param  index_          The index of the task to get
    /// @return _task           The address of the periodic task at the specified index
    /// @return _customSelector The custom selector for the task (or 0)
    function getPeriodicTaskAtIndex(
        uint256 index_
    ) external view returns (address _task, bytes4 _customSelector);

    /// @notice Gets all periodic tasks
    ///
    /// @return _tasks              An array of all periodic tasks in order
    /// @return _customSelectors    An array of all custom selectors in order
    function getPeriodicTasks()
        external
        view
        returns (address[] memory _tasks, bytes4[] memory _customSelectors);

    /// @notice Gets the index of a specific periodic task
    ///
    /// @param  task_   The periodic task to find
    /// @return _index  The index of the task, or type(uint256).max if not found
    function getPeriodicTaskIndex(address task_) external view returns (uint256 _index);

    /// @notice Checks if a periodic task exists in the manager
    ///
    /// @param  task_   The periodic task to check
    /// @return _exists True if the task exists, false otherwise
    function hasPeriodicTask(address task_) external view returns (bool _exists);
}
