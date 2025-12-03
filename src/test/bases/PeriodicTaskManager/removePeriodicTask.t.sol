// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {PeriodicTaskManagerTest} from "src/test/bases/PeriodicTaskManager/PeriodicTaskManagerTest.sol";
import {MockCustomPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockCustomPeriodicTask.sol";

contract PeriodicTaskManagerRemovePeriodicTaskTest is PeriodicTaskManagerTest {
    // ========== TESTS ========== //
    // given the caller is not the admin
    //  [X] it reverts

    function test_givenCallerIsNotAdmin_reverts() public {
        _expectRevertNotAdmin();

        vm.prank(OWNER);
        periodicTaskManager.removePeriodicTask(address(periodicTaskA));
    }

    // given the task is not added
    //  [X] it reverts

    function test_givenTaskIsNotAdded_reverts() public {
        _expectRevertTaskNotFound(address(periodicTaskA));

        vm.prank(ADMIN);
        periodicTaskManager.removePeriodicTask(address(periodicTaskA));
    }

    // given the task has a custom selector
    //  [X] it removes the task
    //  [X] the array length is decremented
    //  [X] the elements after the index are shifted to the left
    //  [X] the custom selector for the task is removed

    function test_givenCustomSelectorTask_indexZero()
        public
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
    {
        address[] memory expectedTasks = new address[](3);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskB);
        expectedTasks[2] = address(periodicTaskC);

        bytes4[] memory expectedCustomSelectors = new bytes4[](3);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = bytes4(0);

        vm.prank(ADMIN);
        periodicTaskManager.removePeriodicTask(address(customPeriodicTask));

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    function test_givenCustomSelectorTask_indexOne()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
    {
        address[] memory expectedTasks = new address[](3);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskB);
        expectedTasks[2] = address(periodicTaskC);

        bytes4[] memory expectedCustomSelectors = new bytes4[](3);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = bytes4(0);

        vm.prank(ADMIN);
        periodicTaskManager.removePeriodicTask(address(customPeriodicTask));

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    function test_givenCustomSelectorTask_indexTwo()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
    {
        address[] memory expectedTasks = new address[](3);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskB);
        expectedTasks[2] = address(periodicTaskC);

        bytes4[] memory expectedCustomSelectors = new bytes4[](3);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = bytes4(0);

        vm.prank(ADMIN);
        periodicTaskManager.removePeriodicTask(address(customPeriodicTask));

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    function test_givenCustomSelectorTask_indexThree()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        address[] memory expectedTasks = new address[](3);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskB);
        expectedTasks[2] = address(periodicTaskC);

        bytes4[] memory expectedCustomSelectors = new bytes4[](3);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = bytes4(0);

        vm.prank(ADMIN);
        periodicTaskManager.removePeriodicTask(address(customPeriodicTask));

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    // [X] it removes the task
    // [X] the array length is decremented
    // [X] the elements after the index are shifted to the left
    // [X] the custom selector for the task is cleared

    function test_givenDifferentCustomSelectorTask_indexZero()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        address[] memory expectedTasks = new address[](3);
        expectedTasks[0] = address(periodicTaskB);
        expectedTasks[1] = address(periodicTaskC);
        expectedTasks[2] = address(customPeriodicTask);

        bytes4[] memory expectedCustomSelectors = new bytes4[](3);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = MockCustomPeriodicTask.customExecute.selector;

        vm.prank(ADMIN);
        periodicTaskManager.removePeriodicTask(address(periodicTaskA));

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    function test_givenDifferentCustomSelectorTask_indexOne()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        address[] memory expectedTasks = new address[](3);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskC);
        expectedTasks[2] = address(customPeriodicTask);

        bytes4[] memory expectedCustomSelectors = new bytes4[](3);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = MockCustomPeriodicTask.customExecute.selector;

        vm.prank(ADMIN);
        periodicTaskManager.removePeriodicTask(address(periodicTaskB));

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    function test_givenDifferentCustomSelectorTask_indexTwo()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        address[] memory expectedTasks = new address[](3);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskB);
        expectedTasks[2] = address(customPeriodicTask);

        bytes4[] memory expectedCustomSelectors = new bytes4[](3);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = MockCustomPeriodicTask.customExecute.selector;

        vm.prank(ADMIN);
        periodicTaskManager.removePeriodicTask(address(periodicTaskC));

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }
}
