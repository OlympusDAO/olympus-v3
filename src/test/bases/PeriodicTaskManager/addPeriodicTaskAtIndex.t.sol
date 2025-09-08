// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {PeriodicTaskManagerTest} from "src/test/bases/PeriodicTaskManager/PeriodicTaskManagerTest.sol";
import {MockCustomPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockCustomPeriodicTask.sol";

contract PeriodicTaskManagerAddPeriodicTaskAtIndexTest is PeriodicTaskManagerTest {
    // ========== TESTS ========== //
    // given the caller is not the admin
    //  [X] it reverts

    function test_givenCallerNotAdmin_reverts() public {
        _expectRevertNotAdmin();

        vm.prank(OWNER);
        periodicTaskManager.addPeriodicTaskAtIndex(address(periodicTaskA), bytes4(0), 0);
    }

    // when the task address is zero
    //  [X] it reverts

    function test_givenTaskAddressIsZero_reverts() public {
        _expectRevertZeroAddress();

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(address(0), bytes4(0), 0);
    }

    // given the index is greater than the array length
    //  [X] it reverts

    function test_givenIndexIsGreaterThanArrayLength_reverts(
        uint256 tasksCount_,
        uint256 index_
    ) public {
        tasksCount_ = bound(tasksCount_, 0, 1);
        index_ = bound(index_, tasksCount_ + 1, type(uint256).max);

        // Insert any required tasks
        if (tasksCount_ > 0) {
            vm.prank(ADMIN);
            periodicTaskManager.addPeriodicTask(address(periodicTaskA));
        }

        _expectRevertIndexOutOfBounds(index_, tasksCount_);

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(address(periodicTaskB), bytes4(0), index_);
    }

    // when the custom selector is not 0
    //  given the task is already added
    //   [X] it reverts

    function test_customSelectorNotZero_givenTaskAlreadyAdded_reverts()
        public
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        _expectRevertTaskAlreadyExists(address(customPeriodicTask));

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(
            address(customPeriodicTask),
            MockCustomPeriodicTask.customExecute.selector,
            1
        );
    }

    //  given there is no contract at the address
    //   [X] it reverts

    function test_customSelectorNotZero_givenNoContractCode_reverts() public {
        _expectRevertNotPeriodicTask(address(0xDDDD));

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(
            address(0xDDDD),
            MockCustomPeriodicTask.customExecute.selector,
            0
        );
    }

    //  given there are no tasks
    //   [X] it inserts the task at the first index
    //   [X] the array length is incremented
    //   [X] the custom selector for the task is the custom selector parameter

    function test_customSelectorNotZero_givenNoTasks() public {
        address[] memory expectedTasks = new address[](1);
        expectedTasks[0] = address(customPeriodicTask);
        bytes4[] memory expectedCustomSelectors = new bytes4[](1);
        expectedCustomSelectors[0] = MockCustomPeriodicTask.customExecute.selector;

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(
            address(customPeriodicTask),
            MockCustomPeriodicTask.customExecute.selector,
            0
        );

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    //  [X] it inserts the task at the index
    //  [X] the array length is incremented
    //  [X] the elements after the index are shifted to the right
    //  [X] the custom selector for the task is the custom selector parameter

    function test_customSelectorNotZero_indexZero()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
    {
        address[] memory expectedTasks = new address[](4);
        expectedTasks[0] = address(customPeriodicTask);
        expectedTasks[1] = address(periodicTaskA);
        expectedTasks[2] = address(periodicTaskB);
        expectedTasks[3] = address(periodicTaskC);
        bytes4[] memory expectedCustomSelectors = new bytes4[](4);
        expectedCustomSelectors[0] = MockCustomPeriodicTask.customExecute.selector;
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = bytes4(0);
        expectedCustomSelectors[3] = bytes4(0);

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(
            address(customPeriodicTask),
            MockCustomPeriodicTask.customExecute.selector,
            0
        );

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    function test_customSelectorNotZero_indexOne()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
    {
        address[] memory expectedTasks = new address[](4);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(customPeriodicTask);
        expectedTasks[2] = address(periodicTaskB);
        expectedTasks[3] = address(periodicTaskC);
        bytes4[] memory expectedCustomSelectors = new bytes4[](4);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = MockCustomPeriodicTask.customExecute.selector;
        expectedCustomSelectors[2] = bytes4(0);
        expectedCustomSelectors[3] = bytes4(0);

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(
            address(customPeriodicTask),
            MockCustomPeriodicTask.customExecute.selector,
            1
        );

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    function test_customSelectorNotZero_indexTwo()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
    {
        address[] memory expectedTasks = new address[](4);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskB);
        expectedTasks[2] = address(customPeriodicTask);
        expectedTasks[3] = address(periodicTaskC);
        bytes4[] memory expectedCustomSelectors = new bytes4[](4);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = MockCustomPeriodicTask.customExecute.selector;
        expectedCustomSelectors[3] = bytes4(0);

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(
            address(customPeriodicTask),
            MockCustomPeriodicTask.customExecute.selector,
            2
        );

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    function test_customSelectorNotZero_indexThree()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenPeriodicTaskIsAdded(address(periodicTaskC))
    {
        address[] memory expectedTasks = new address[](4);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskB);
        expectedTasks[2] = address(periodicTaskC);
        expectedTasks[3] = address(customPeriodicTask);
        bytes4[] memory expectedCustomSelectors = new bytes4[](4);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = bytes4(0);
        expectedCustomSelectors[3] = MockCustomPeriodicTask.customExecute.selector;

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(
            address(customPeriodicTask),
            MockCustomPeriodicTask.customExecute.selector,
            3
        );

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    // given the task does not implement the IPeriodicTask interface
    //  [X] it reverts

    function test_givenTaskDoesNotImplementInterface_reverts() public {
        _expectRevertNotPeriodicTask(address(customPeriodicTask));

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(address(customPeriodicTask), bytes4(0), 0);
    }

    // given the task is already added
    //  [X] it reverts

    function test_givenTaskIsAlreadyAdded_reverts()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
    {
        _expectRevertTaskAlreadyExists(address(periodicTaskA));

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(address(periodicTaskA), bytes4(0), 0);
    }

    // given there are no tasks
    //  [X] it inserts the task at the first index
    //  [X] the array length is incremented
    //  [X] the custom selector for the task is 0

    function test_givenNoTasks() public {
        address[] memory expectedTasks = new address[](1);
        expectedTasks[0] = address(periodicTaskA);
        bytes4[] memory expectedCustomSelectors = new bytes4[](1);
        expectedCustomSelectors[0] = bytes4(0);

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(address(periodicTaskA), bytes4(0), 0);

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    // [X] it inserts the task at the index
    // [X] the array length is incremented
    // [X] the elements after the index are shifted to the right
    // [X] the custom selector for the task is 0

    function test_indexZero()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        address[] memory expectedTasks = new address[](4);
        expectedTasks[0] = address(periodicTaskC);
        expectedTasks[1] = address(periodicTaskA);
        expectedTasks[2] = address(periodicTaskB);
        expectedTasks[3] = address(customPeriodicTask);
        bytes4[] memory expectedCustomSelectors = new bytes4[](4);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = bytes4(0);
        expectedCustomSelectors[3] = MockCustomPeriodicTask.customExecute.selector;

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(address(periodicTaskC), bytes4(0), 0);

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    function test_indexOne()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        address[] memory expectedTasks = new address[](4);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskC);
        expectedTasks[2] = address(periodicTaskB);
        expectedTasks[3] = address(customPeriodicTask);
        bytes4[] memory expectedCustomSelectors = new bytes4[](4);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = bytes4(0);
        expectedCustomSelectors[3] = MockCustomPeriodicTask.customExecute.selector;

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(address(periodicTaskC), bytes4(0), 1);

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    function test_indexTwo()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        address[] memory expectedTasks = new address[](4);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskB);
        expectedTasks[2] = address(periodicTaskC);
        expectedTasks[3] = address(customPeriodicTask);
        bytes4[] memory expectedCustomSelectors = new bytes4[](4);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = bytes4(0);
        expectedCustomSelectors[3] = MockCustomPeriodicTask.customExecute.selector;

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(address(periodicTaskC), bytes4(0), 2);

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }

    function test_indexThree()
        public
        givenPeriodicTaskIsAdded(address(periodicTaskA))
        givenPeriodicTaskIsAdded(address(periodicTaskB))
        givenCustomPeriodicTaskIsAdded(address(customPeriodicTask))
    {
        address[] memory expectedTasks = new address[](4);
        expectedTasks[0] = address(periodicTaskA);
        expectedTasks[1] = address(periodicTaskB);
        expectedTasks[2] = address(customPeriodicTask);
        expectedTasks[3] = address(periodicTaskC);
        bytes4[] memory expectedCustomSelectors = new bytes4[](4);
        expectedCustomSelectors[0] = bytes4(0);
        expectedCustomSelectors[1] = bytes4(0);
        expectedCustomSelectors[2] = MockCustomPeriodicTask.customExecute.selector;
        expectedCustomSelectors[3] = bytes4(0);

        vm.prank(ADMIN);
        periodicTaskManager.addPeriodicTaskAtIndex(address(periodicTaskC), bytes4(0), 3);

        _assertPeriodicTasks(expectedTasks, expectedCustomSelectors);
    }
}
