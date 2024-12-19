// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {CDEPOTest} from "./CDEPOTest.sol";

contract RedeemCDEPOTest is CDEPOTest {
    // when the amount is zero
    //  [ ] it reverts
    // when the caller is not permissioned
    //  [ ] it reverts
    // when the caller is permissioned
    //  [ ] it burns the corresponding amount of convertible deposit tokens
    //  [ ] it withdraws the underlying asset from the vault
    //  [ ] it transfers the underlying asset to the caller
    //  [ ] it emits a `Transfer` event
}
