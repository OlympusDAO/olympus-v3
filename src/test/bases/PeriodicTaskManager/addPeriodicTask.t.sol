// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {PeriodicTaskManagerTest} from "src/test/bases/PeriodicTaskManager/PeriodicTaskManagerTest.sol";

contract PeriodicTaskManagerAddPeriodicTaskTest is PeriodicTaskManagerTest {
    // ========== TESTS ========== //
    // given the caller is not the admin
    //  [X] it reverts

    function test_givenCallerNotAdmin_reverts() public {
        _expectRevertNotAdmin();

        vm.prank(OWNER);
        periodicTaskManager.addPeriodicTask(address(periodicTaskA));
    }

    // when the task address is zero
    //  [X] it reverts

    function test_givenTaskAddressIsZero_reverts() public {
        _expectRevertZeroAddress();

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTask(address(0));
    }

    // given the task is already added
    //  [X] it reverts

    function test_givenTaskIsAlreadyAdded_reverts()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
    {
        _expectRevertTaskAlreadyExists(address(periodicTaskA));

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTask(address(periodicTaskA));
    }

    // given the task does not implement the IPeriodicTask interface
    //  [X] it reverts

    function test_givenNotPeriodicTask_reverts() public {
        _expectRevertNotPeriodicTask(address(customPeriodicTask));

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTask(address(customPeriodicTask));
    }

    // given there are no tasks in the manager
    //  [X] it inserts the task at index 0
    //  [X] the array length is 1
    //  [X] the custom selector for the task is 0

    function test_givenNoTasks() public {
        address[] memory expectedTasks = new address[](1);
        expectedTasks[0] = address(periodicTaskA);
        bytes4[] memory expectedCustomSelectors = new bytes4[](1);
        expectedCustomSelectors[0] = bytes4(0);

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTask(address(periodicTaskA));

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    // [X] it inserts the task at the next index
    // [X] the array length is incremented
    // [X] the custom selector for the task is 0

    function test_givenTasks() public givenPeriodicTaskIsAdded(address(periodicTaskA)) {
        address[] memory expectedTasks = new address[](2);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskB);
        bytes4[] memory expectedCustomSelectors = new bytes4[](2);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTask(address(periodicTaskB));

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }
}
