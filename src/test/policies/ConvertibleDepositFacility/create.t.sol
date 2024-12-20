// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";

contract CreateCDFTest is ConvertibleDepositFacilityTest {
    // when the caller does not have the CD_Auctioneer role
    //  [ ] it reverts
    // when the caller has not approved CDEPO to spend the reserve tokens
    //  [ ] it reverts
    // [ ] it mints the CD tokens to account_
    // [ ] it creates a new position in the CDPOS module
    // [ ] it pre-emptively increases the mint approval equivalent to the converted amount of OHM
    // [ ] it returns the position ID
    // [ ] it emits a CreatedDeposit event
}
