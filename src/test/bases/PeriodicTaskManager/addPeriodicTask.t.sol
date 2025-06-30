// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {PeriodicTaskManagerTest} from "src/test/bases/PeriodicTaskManager/PeriodicTaskManagerTest.sol";

contract PeriodicTaskManagerAddPeriodicTaskTest is PeriodicTaskManagerTest {
    // ========== TESTS ========== //
    // given the caller is not the admin
    //  [ ] it reverts
    // when the task address is zero
    //  [ ] it reverts
    // given the task is already added
    //  [ ] it reverts
    // given the task does not implement the IPeriodicTask interface
    //  [ ] it reverts
    // given there are no tasks in the manager
    //  [ ] it inserts the task at index 0
    //  [ ] the array length is 1
    //  [ ] the custom selector for the task is 0
    // [ ] it inserts the task at the next index
    // [ ] the array length is incremented
    // [ ] the custom selector for the task is 0
}
