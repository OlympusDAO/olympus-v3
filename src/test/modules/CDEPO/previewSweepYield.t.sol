// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {CDEPOTest} from "./CDEPOTest.sol";

contract PreviewSweepYieldCDEPOTest is CDEPOTest {
    // when there are no deposits
    //  [ ] it returns zero
    // when there are deposits
    //  [ ] it returns the difference between the total deposits and the total assets in the vault
}
