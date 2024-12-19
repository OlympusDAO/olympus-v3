// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {CDEPOTest} from "./CDEPOTest.sol";

contract SetReclaimRateCDEPOTest is CDEPOTest {
    // when the caller is not permissioned
    //  [ ] it reverts
    // when the new reclaim rate is greater than the maximum reclaim rate
    //  [ ] it reverts
    // when the new reclaim rate is within bounds
    //  [ ] it sets the new reclaim rate
    //  [ ] it emits an event
}
