// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract DisableCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // given the caller is not an admin or emergency
    //  [ ] it reverts
    // [ ] the contract is disabled
    // [ ] the contract is deactivated in CHREG
}
