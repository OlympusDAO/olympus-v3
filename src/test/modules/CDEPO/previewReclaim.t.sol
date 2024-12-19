// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {CDEPOTest} from "./CDEPOTest.sol";

contract PreviewReclaimCDEPOTest is CDEPOTest {
    // when the amount is zero
    //  [ ] it reverts
    // when the amount is greater than zero
    //  [ ] it returns the amount after applying the burn rate
}
