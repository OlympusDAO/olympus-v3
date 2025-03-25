// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

contract MintDepositCDFTest is ConvertibleDepositFacilityTest {
    // given the contract is inactive
    //  [ ] it reverts
    // when the recipient has not approved CDEPO to spend the reserve tokens
    //  [ ] it reverts
    // given the deposit asset has 6 decimals
    //  [ ] the amount of CD tokens minted is correct
    //  [ ] the mint approval is increased by the correct amount of OHM
    // when multiple positions are created
    //  [ ] it succeeds
    // [ ] it mints the CD tokens to account_
    // [ ] it creates a new position in the CDPOS module
    // [ ] mint approval is not changed
    // [ ] the position does not have a conversion price
    // [ ] it returns the position ID
    // [ ] it emits a CreatedDeposit event
}
