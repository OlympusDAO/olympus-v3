// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {CDEPOTest} from "./CDEPOTest.sol";

contract ConstructorTest is CDEPOTest {
    // when the kernel address is zero
    //  [ ] it reverts
    // when the vault address is zero
    //  [ ] it reverts
    // [ ] the name is set to "cd" + the asset symbol
    // [ ] the symbol is set to "cd" + the asset symbol
    // [ ] the decimals are set to the asset decimals
    // [ ] the asset is recorded
    // [ ] the vault is recorded
}
