// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";

contract ReclaimCDFTest is ConvertibleDepositFacilityTest {
    event ReclaimedDeposit(address indexed user, uint256 reclaimedAmount, uint256 forfeitedAmount);

    // given the contract is inactive
    //  [ ] it reverts
    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [ ] it reverts
    // when any position is not valid
    //  [ ] it reverts
    // when any position has an owner that is not the caller
    //  [ ] it reverts
    // when any position has expired
    //  [ ] it reverts
    // when any position has an amount greater than the remaining deposit
    //  [ ] it reverts
    // when the caller has not approved CDEPO to spend the total amount of CD tokens
    //  [ ] it reverts
    // when the reclaim amount is 0
    //  [ ] it reverts
    // [ ] it updates the remaining deposit of each position
    // [ ] it transfers the reclaimed reserve tokens to the caller
    // [ ] it decreases the OHM mint approval by the amount of OHM that would have been converted
    // [ ] it returns the reclaimed amount
    // [ ] it emits a ReclaimedDeposit event
}
