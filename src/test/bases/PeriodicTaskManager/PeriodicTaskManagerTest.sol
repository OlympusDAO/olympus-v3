// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockCustomPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockCustomPeriodicTask.sol";
import {AddressStorageArray} from "src/libraries/AddressStorageArray.sol";

abstract contract PeriodicTaskManagerTest is Test {
    MockPeriodicTaskManager public periodicTaskManager;
    Kernel public kernel;
    OlympusRoles public ROLES;
    RolesAdmin public rolesAdmin;

    address public OWNER;
    address public ADMIN;

    MockPeriodicTask public periodicTaskA;
    MockPeriodicTask public periodicTaskB;
    MockPeriodicTask public periodicTaskC;
    MockCustomPeriodicTask public customPeriodicTask;

    function setUp() public {
        OWNER = makeAddr("OWNER");
        ADMIN = makeAddr("ADMIN");

        vm.startPrank(OWNER);
        kernel = new Kernel();

        ROLES = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        periodicTaskManager = new MockPeriodicTaskManager(kernel);
        vm.stopPrank();

        // Install contracts
        vm.startPrank(OWNER);
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(periodicTaskManager));
        vm.stopPrank();

        // Grant permissions
        vm.startPrank(OWNER);
        rolesAdmin.grantRole(bytes32("admin"), ADMIN);
        vm.stopPrank();

        periodicTaskA = new MockPeriodicTask();
        periodicTaskB = new MockPeriodicTask();
        periodicTaskC = new MockPeriodicTask();
        customPeriodicTask = new MockCustomPeriodicTask();
    }

    modifier givenPeriodicTaskIsAdded(address task_) {
        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTask(task_);
        _;
    }

    modifier givenCustomPeriodicTaskIsAdded(address task_) {
        uint256 taskCount = periodicTaskManager.getPeriodicTaskCount();

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(
            task_,
            MockCustomPeriodicTask.customExecute.selector,
            taskCount
        );
        _;
    }

    function _expectRevertNotAdmin() internal {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("admin"))
        );
    }

    function _expectRevertZeroAddress() internal {
        vm.expectRevert(
            abi.encodeWithSelector(IPeriodicTaskManager.PeriodicTaskManager_ZeroAddress.selector)
        );
    }

    function _expectRevertIndexOutOfBounds(uint256 index_, uint256 length_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                AddressStorageArray.AddressStorageArray_IndexOutOfBounds.selector,
                index_,
                length_
            )
        );
    }

    function _expectRevertTaskAlreadyExists(address task_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPeriodicTaskManager.PeriodicTaskManager_TaskAlreadyExists.selector,
                task_
            )
        );
    }

    function _expectRevertTaskNotFound(address task_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPeriodicTaskManager.PeriodicTaskManager_TaskNotFound.selector,
                task_
            )
        );
    }

    function _expectRevertNotPeriodicTask(address task_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPeriodicTaskManager.PeriodicTaskManager_NotPeriodicTask.selector,
                task_
            )
        );
    }

    function _assertPeriodicTasks(
        address[] memory tasks_,
        bytes4[] memory customSelectors_
    ) internal view {
        assertEq(periodicTaskManager.getPeriodicTaskCount(), tasks_.length, "periodicTaskCount");

        // Compare index by index
        for (uint256 i = 0; i < tasks_.length; i++) {
            (address task, bytes4 customSelector) = periodicTaskManager.getPeriodicTaskAtIndex(i);
            assertEq(task, tasks_[i], string.concat("atIndex tasks[", vm.toString(i), "]"));
            assertEq(
                customSelector,
                customSelectors_[i],
                string.concat("atIndex customSelectors[", vm.toString(i), "]")
            );
        }

        // Compare the full array
        (address[] memory tasks, bytes4[] memory customSelectors) = periodicTaskManager
            .getPeriodicTasks();
        for (uint256 i = 0; i < tasks_.length; i++) {
            assertEq(tasks[i], tasks_[i], string.concat("tasks[", vm.toString(i), "]"));
            assertEq(
                customSelectors[i],
                customSelectors_[i],
                string.concat("customSelectors[", vm.toString(i), "]")
            );
        }

        assertEq(tasks.length, tasks_.length, "tasks.length");
        assertEq(customSelectors.length, customSelectors_.length, "customSelectors.length");
    }
}
