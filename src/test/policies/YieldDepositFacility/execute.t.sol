// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";

contract ExecuteYDFTest is YieldDepositFacilityTest {
    // given the contract is disabled
    //  [ ] it does nothing
    // given the caller is not the heart
    //  [ ] it reverts
    // given a snapshot has already been taken for the current rounded timestamp
    //  [ ] it does nothing
    // given the current timestamp is not a multiple of 8 hours
    //  [ ] the snapshot timestamp is rounded down to the nearest 8-hour interval
    // [ ] the snapshot timestamp is rounded down to the nearest 8-hour interval
    // [ ] it stores the rate snapshot for each vault
    // [ ] it emits a SnapshotTaken event
}
