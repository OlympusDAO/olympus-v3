// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";

// Libraries
import {AddressStorageArray} from "src/libraries/AddressStorageArray.sol";

// Bophades
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

abstract contract BasePeriodicTaskManager is IPeriodicTaskManager, PolicyEnabler {
    using AddressStorageArray for address[];

    // ========== STATE VARIABLES ========== //

    /// @notice The periodic tasks
    address[] internal _periodicTaskAddresses;

    /// @notice An optional custom selector for each periodic task
    /// @dev    If the selector is set (non-zero), the task will be executed using the custom selector
    ///         instead of the `IPeriodicTask.execute` function
    mapping(address => bytes4) internal _periodicTaskCustomSelectors;

    // ========== TASK CONFIGURATION ========== //

    function _addPeriodicTask(address task_, bytes4 customSelector_, uint256 index_) internal {
        // Validate that the task is not already added
        if (hasPeriodicTask(task_)) revert PeriodicTaskManager_TaskAlreadyExists(task_);

        // Validate that the task is not a zero address
        if (task_ == address(0)) revert PeriodicTaskManager_ZeroAddress();

        // Validate that the task is a contract
        if (task_.code.length == 0) revert PeriodicTaskManager_NotPeriodicTask(task_);

        // If there is no custom selector, validate that the task implements the IPeriodicTask interface
        if (customSelector_ == bytes4(0)) {
            // Validate that the task implements the IPeriodicTask interface
            (bool success, bytes memory data) = task_.staticcall(
                abi.encodeWithSelector(
                    IERC165.supportsInterface.selector,
                    type(IPeriodicTask).interfaceId
                )
            );
            if (!success || abi.decode(data, (bool)) == false)
                revert PeriodicTaskManager_NotPeriodicTask(task_);
        } else {
            // Validation of the selector happens at the time of execution, as there is no way to validate it here
            _periodicTaskCustomSelectors[task_] = customSelector_;
        }

        // Insert the task at the index
        // This will also validate that the index is within bounds
        _periodicTaskAddresses.insert(task_, index_);

        // Emit the event
        emit PeriodicTaskAdded(task_, customSelector_, index_);
    }

    /// @inheritdoc IPeriodicTaskManager
    /// @dev        This function reverts if:
    ///             - The caller is not the admin
    ///             - The task is already added
    ///             - The task is not a valid periodic task
    ///
    function addPeriodicTask(address task_) external override onlyAdminRole {
        _addPeriodicTask(task_, bytes4(0), _periodicTaskAddresses.length);
    }

    /// @inheritdoc IPeriodicTaskManager
    /// @dev        This function reverts if:
    ///             - The caller is not the admin
    ///             - The task is already added
    ///             - The task is not a valid periodic task
    ///             - The index is out of bounds
    ///
    ///             If a custom selector is provided, care must be taken to ensure that the selector exists on {task_}.
    ///             If the selector does not exist, all of the periodic tasks will revert.
    function addPeriodicTaskAtIndex(
        address task_,
        bytes4 customSelector_,
        uint256 index_
    ) external override onlyAdminRole {
        _addPeriodicTask(task_, customSelector_, index_);
    }

    function _removePeriodicTask(uint256 index_) internal {
        // Remove the task at the index
        address removedTask = _periodicTaskAddresses.remove(index_);

        // Clear the custom selector for the task
        delete _periodicTaskCustomSelectors[removedTask];

        // Emit the event
        emit PeriodicTaskRemoved(removedTask, index_);
    }

    /// @inheritdoc IPeriodicTaskManager
    /// @dev        This function reverts if:
    ///             - The caller is not the admin
    ///             - The task is not added
    function removePeriodicTask(address task_) external override onlyAdminRole {
        // Get the index of the task
        uint256 index = getPeriodicTaskIndex(task_);

        // Validate that the task exists
        if (index == type(uint256).max) revert PeriodicTaskManager_TaskNotFound(task_);

        // Remove the task at the index
        _removePeriodicTask(index);
    }

    /// @inheritdoc IPeriodicTaskManager
    /// @dev        This function reverts if:
    ///             - The caller is not the admin
    ///             - The index is out of bounds
    function removePeriodicTaskAtIndex(uint256 index_) external override onlyAdminRole {
        // Remove the task at the index
        _removePeriodicTask(index_);
    }

    // ========== TASK EXECUTION ========== //

    /// @dev This function does not implement any logic to catch errors from the periodic tasks.
    /// @dev The logic is that if a periodic task fails, it should fail loudly and revert.
    /// @dev Any tasks that are non-essential can include a try-catch block to handle the error internally.
    function _executePeriodicTasks() internal {
        for (uint256 i = 0; i < _periodicTaskAddresses.length; i++) {
            // Get the custom selector for the task
            bytes4 customSelector = _periodicTaskCustomSelectors[_periodicTaskAddresses[i]];

            // If there is no custom selector, execute the task using the `IPeriodicTask.execute` function
            if (customSelector == bytes4(0)) {
                IPeriodicTask(_periodicTaskAddresses[i]).execute();
            }
            // Otherwise, execute the task using the custom selector
            else {
                // Call the custom selector
                (bool success, bytes memory data) = _periodicTaskAddresses[i].call(
                    abi.encodeWithSelector(customSelector)
                );

                // If the call fails, revert
                if (!success)
                    revert PeriodicTaskManager_CustomSelectorFailed(
                        _periodicTaskAddresses[i],
                        customSelector,
                        data
                    );
            }
        }
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IPeriodicTaskManager
    function getPeriodicTaskCount() external view override returns (uint256) {
        return _periodicTaskAddresses.length;
    }

    /// @inheritdoc IPeriodicTaskManager
    function getPeriodicTaskAtIndex(
        uint256 index_
    ) external view override returns (address, bytes4) {
        address task = _periodicTaskAddresses[index_];

        return (task, _periodicTaskCustomSelectors[task]);
    }

    /// @inheritdoc IPeriodicTaskManager
    function getPeriodicTasks() external view override returns (address[] memory, bytes4[] memory) {
        address[] memory tasks = new address[](_periodicTaskAddresses.length);
        bytes4[] memory customSelectors = new bytes4[](_periodicTaskAddresses.length);

        for (uint256 i = 0; i < _periodicTaskAddresses.length; i++) {
            tasks[i] = _periodicTaskAddresses[i];
            customSelectors[i] = _periodicTaskCustomSelectors[_periodicTaskAddresses[i]];
        }

        return (tasks, customSelectors);
    }

    /// @inheritdoc IPeriodicTaskManager
    ///
    /// @return _index  The index of the task, or type(uint256).max if not found
    function getPeriodicTaskIndex(address task_) public view override returns (uint256 _index) {
        uint256 length = _periodicTaskAddresses.length;
        _index = type(uint256).max;
        for (uint256 i = 0; i < length; i++) {
            if (_periodicTaskAddresses[i] == task_) {
                _index = i;
                break;
            }
        }

        return _index;
    }

    /// @inheritdoc IPeriodicTaskManager
    function hasPeriodicTask(address task_) public view override returns (bool) {
        return getPeriodicTaskIndex(task_) != type(uint256).max;
    }
}
