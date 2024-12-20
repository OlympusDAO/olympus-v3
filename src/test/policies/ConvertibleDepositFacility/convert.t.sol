// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";

contract ConvertCDFTest is ConvertibleDepositFacilityTest {
    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [ ] it reverts
    // when any position is not valid
    //  [ ] it reverts
    // when any position has an owner that is not the caller
    //  [ ] it reverts
    // when any position has a convertible deposit token that is not CDEPO
    //  [ ] it reverts
    // when any position has expired
    //  [ ] it reverts
    // when any position has an amount greater than the remaining deposit
    //  [ ] it reverts
    // when the caller has not approved CDEPO to spend the total amount of CD tokens
    //  [ ] it reverts
    // [ ] it mints the converted amount of OHM to the account_
    // [ ] it updates the remaining deposit of each position
    // [ ] it transfers the redeemed vault shares to the TRSRY
    // [ ] it returns the total deposit amount and the converted amount
    // [ ] it emits a ConvertedDeposit event
}
