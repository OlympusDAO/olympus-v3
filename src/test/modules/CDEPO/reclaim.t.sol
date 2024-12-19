// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {CDEPOTest} from "./CDEPOTest.sol";

contract ReclaimCDEPOTest is CDEPOTest {
    // when the amount is zero
    //  [ ] it reverts
    // when the amount is greater than the caller's balance
    //  [ ] it reverts
    // when the amount is greater than zero
    //  [ ] it burns the corresponding amount of convertible deposit tokens
    //  [ ] it withdraws the underlying asset from the vault
    //  [ ] it transfers the underlying asset to the caller after applying the burn rate
    //  [ ] it updates the total deposits
    //  [ ] it marks the forfeited amount of the underlying asset as yield
}
