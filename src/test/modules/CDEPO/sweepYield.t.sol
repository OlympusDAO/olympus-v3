// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {CDEPOTest} from "./CDEPOTest.sol";

contract SweepYieldCDEPOTest is CDEPOTest {
    // when the caller is not permissioned
    //  [ ] it reverts
    // when there are no deposits
    //  [ ] it does not transfer any yield
    //  [ ] it returns zero
    //  [ ] it does not emit any events
    // when there are deposits
    //  when it is called again without any additional yield
    //   [ ] it returns zero
    //  when deposit tokens have been reclaimed
    //   [ ] the yield includes the forfeited amount
    //  [ ] it withdraws the underlying asset from the vault
    //  [ ] it transfers the underlying asset to the caller
    //  [ ] it emits a `YieldSwept` event
}
