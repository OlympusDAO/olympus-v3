// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {PeriodicTaskManagerTest} from "src/test/bases/PeriodicTaskManager/PeriodicTaskManagerTest.sol";

contract PeriodicTaskManagerRemovePeriodicTaskAtIndexTest is PeriodicTaskManagerTest {
    // ========== TESTS ========== //
    // given the caller is not the admin
    //  [ ] it reverts
    // given the index is out of bounds
    //  [ ] it reverts
    // given the task has a custom selector
    //  [ ] it removes the task
    //  [ ] the array length is decremented
    //  [ ] the elements after the index are shifted to the left
    //  [ ] the custom selector for the task is cleared
    // [ ] it removes the task
    // [ ] the array length is decremented
    // [ ] the elements after the index are shifted to the left
    // [ ] the custom selector for the task is cleared
}
