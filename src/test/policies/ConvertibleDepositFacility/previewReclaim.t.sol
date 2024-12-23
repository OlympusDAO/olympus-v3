// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";

contract PreviewReclaimCDFTest is ConvertibleDepositFacilityTest {
    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [ ] it reverts
    // when any position is not valid
    //  [ ] it reverts
    // when any position has a convertible deposit token that is not CDEPO
    //  [ ] it reverts
    // when any position has not expired
    //  [ ] it reverts
    // when any position has an amount greater than the remaining deposit
    //  [ ] it reverts
    // [ ] it returns the total amount of deposit token that would be reclaimed
    // [ ] it returns the address that will spend the convertible deposit tokens
}
