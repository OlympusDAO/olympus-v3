// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {CDEPOTest} from "./CDEPOTest.sol";

contract ReclaimToCDEPOTest is CDEPOTest {
    // when the amount is zero
    //  [ ] it reverts
    // when the caller has not approved CDEPO to spend convertible deposit tokens
    //  [ ] it reverts
    // when the caller has approved CDEPO to spend convertible deposit tokens
    //  when the caller has an insufficient balance of convertible deposit tokens
    //   [ ] it reverts
    //  when the caller has a sufficient balance of convertible deposit tokens
    //   [ ] it burns the corresponding amount of convertible deposit tokens
    //   [ ] it withdraws the underlying asset from the vault
    //   [ ] it transfers the underlying asset to the `to_` address after applying the burn rate
    //   [ ] it marks the forfeited amount of the underlying asset as yield
    //   [ ] it updates the total deposits
    //   [ ] it emits a `Transfer` event
}
