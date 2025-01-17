// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";

contract PreviewReclaimCDFTest is ConvertibleDepositFacilityTest {
    // given the contract is inactive
    //  [ ] it reverts
    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [ ] it reverts
    // when the account_ is not the owner of all of the positions
    //  [ ] it reverts
    // when any position is not valid
    //  [ ] it reverts
    // when any position has expired
    //  [ ] it reverts
    // when any position has an amount greater than the remaining deposit
    //  [ ] it reverts
    // when the reclaim amount is 0
    //  [ ] it reverts
    // [ ] it returns the total amount of deposit token that would be reclaimed
    // [ ] it returns the address that will spend the convertible deposit tokens
}
