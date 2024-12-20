// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";

contract ReclaimCDFTest is ConvertibleDepositFacilityTest {
    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [ ] it reverts
    // when any position is not valid
    //  [ ] it reverts
    // when any position has an owner that is not the caller
    //  [ ] it reverts
    // when any position has a convertible deposit token that is not CDEPO
    //  [ ] it reverts
    // when any position has not expired
    //  [ ] it reverts
    // when any position has an amount greater than the remaining deposit
    //  [ ] it reverts
    // when the caller has not approved CDEPO to spend the total amount of CD tokens
    //  [ ] it reverts
    // [ ] it updates the remaining deposit of each position
    // [ ] it transfers the redeemed reserve tokens to the owner
    // [ ] it decreases the OHM mint approval by the amount of OHM that would have been converted
    // [ ] it returns the reclaimed amount
    // [ ] it emits a ReclaimedDeposit event
}
