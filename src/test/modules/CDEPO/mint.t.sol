// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {CDEPOTest} from "./CDEPOTest.sol";

contract MintCDEPOTest is CDEPOTest {
    // when the recipient is the zero address
    //  [ ] it reverts
    // when the amount is zero
    //  [ ] it reverts
    // when the caller has not approved CDEPO to spend reserve tokens
    //  [ ] it reverts
    // when the caller has approved CDEPO to spend reserve tokens
    //  when the caller has an insufficient balance of reserve tokens
    //   [ ] it reverts
    //  when the caller has a sufficient balance of reserve tokens
    //   [ ] it transfers the reserve tokens to CDEPO
    //   [ ] it mints an equal amount of convertible deposit tokens to the caller
    //   [ ] it deposits the reserve tokens into the vault
    //   [ ] it emits a `Transfer` event
}
