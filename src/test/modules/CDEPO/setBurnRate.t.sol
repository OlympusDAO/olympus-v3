// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {CDEPOTest} from "./CDEPOTest.sol";

contract SetBurnRateCDEPOTest is CDEPOTest {
    // when the caller is not permissioned
    //  [ ] it reverts
    // when the new burn rate is greater than the maximum burn rate
    //  [ ] it reverts
    // when the new burn rate is within bounds
    //  [ ] it sets the new burn rate
    //  [ ] it emits an event
}
