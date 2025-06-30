// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {PeriodicTaskManagerTest} from "src/test/bases/PeriodicTaskManager/PeriodicTaskManagerTest.sol";

contract PeriodicTaskManagerAddPeriodicTaskAtIndexTest is PeriodicTaskManagerTest {
    // ========== TESTS ========== //
    // given the caller is not the admin
    //  [ ] it reverts
    // when the task address is zero
    //  [ ] it reverts
    // given the index is greater than the array length
    //  [ ] it reverts
    // when the custom selector is not 0
    //  given the task is already added
    //   [ ] it reverts
    //  [ ] it inserts the task at the index
    //  [ ] the array length is incremented
    //  [ ] the elements after the index are shifted to the right
    //  [ ] the custom selector for the task is the custom selector parameter
    // given the task does not implement the IPeriodicTask interface
    //  [ ] it reverts
    // given the task is already added
    //  [ ] it reverts
    // [ ] it inserts the task at the index
    // [ ] the array length is incremented
    // [ ] the elements after the index are shifted to the right
    // [ ] the custom selector for the task is 0
}
