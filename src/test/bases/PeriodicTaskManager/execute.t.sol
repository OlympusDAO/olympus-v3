// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {PeriodicTaskManagerTest} from "src/test/bases/PeriodicTaskManager/PeriodicTaskManagerTest.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockCustomPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockCustomPeriodicTask.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";

contract PeriodicTaskManagerExecuteTest is PeriodicTaskManagerTest {
    // ========== TESTS ========== //
    // given there are no tasks
    //  [X] it does nothing

    function test_givenNoTasks() public {
        // Execute the periodic tasks
        periodicTaskManager.executeAllTasks();

        // Assert that the periodic tasks were not executed
        assertEq(periodicTaskA.count(), 0, "periodicTaskA.count");
        assertEq(periodicTaskB.count(), 0, "periodicTaskB.count");
        assertEq(periodicTaskC.count(), 0, "periodicTaskC.count");
        assertEq(customPeriodicTask.count(), 0, "customPeriodicTask.count");
    }

    // given a standard periodic task reverts
    //  [X] it reverts

    function test_givenPeriodicTaskReverts_reverts()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        // Set the revert flag for the periodic task
        periodicTaskA.setRevert(true);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(MockPeriodicTask.MockPeriodicTask_Revert.selector));

        // Execute the periodic tasks
        periodicTaskManager.executeAllTasks();
    }

    // given a custom periodic tasks reverts
    //  [X] it reverts

    function test_givenCustomPeriodicTaskReverts_reverts()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        // Set the revert flag for the periodic task
        customPeriodicTask.setRevert(true);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IPeriodicTaskManager.PeriodicTaskManager_CustomSelectorFailed.selector,
                address(customPeriodicTask),
                MockCustomPeriodicTask.customExecute.selector,
                abi.encodeWithSelector(
                    MockCustomPeriodicTask.MockCustomPeriodicTask_Revert.selector
                )
            )
        );

        // Execute the periodic tasks
        periodicTaskManager.executeAllTasks();
    }

    // given the custom selector is not implemented
    //  [X] it reverts

    function test_givenCustomSelectorIsNotImplemented_reverts()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
    {
        // Add a custom periodic task with a non-existent selector
        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(
            address(customPeriodicTask),
            IPeriodicTask.execute.selector,
            3
        );

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IPeriodicTaskManager.PeriodicTaskManager_CustomSelectorFailed.selector,
                address(customPeriodicTask),
                IPeriodicTask.execute.selector,
                ""
            )
        );

        // Execute the periodic tasks
        periodicTaskManager.executeAllTasks();
    }

    // [X] it runs the periodic tasks

    function test_success()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        // Execute the periodic tasks
        periodicTaskManager.executeAllTasks();

        // Assert that the periodic tasks were not executed
        assertEq(periodicTaskA.count(), 1, "periodicTaskA.count");
        assertEq(periodicTaskB.count(), 1, "periodicTaskB.count");
        assertEq(periodicTaskC.count(), 1, "periodicTaskC.count");
        assertEq(customPeriodicTask.count(), 1, "customPeriodicTask.count");
    }
}
