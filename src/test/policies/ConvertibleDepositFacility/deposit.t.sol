// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityDepositTest is ConvertibleDepositFacilityTest {
    // given the contract is disabled
    //  [ ] it reverts
    // given the deposit is not configured
    //  [ ] it reverts
    // given the caller has not approved the deposit manager to spend the asset
    //  [ ] it reverts
    // given the caller does not have the required asset balance
    //  [ ] it reverts
    // when wrap receipt is true
    //  [ ] it transfers the asset from the caller
    //  [ ] it transfers the wrapped receipt token to the caller
    //  [ ] it returns the receipt token id
    //  [ ] it returns the actual deposit amount
    //  [ ] it does not create a position
    // [ ] it transfers the asset from the caller
    // [ ] it transfers the receipt token to the caller
    // [ ] it returns the receipt token id
    // [ ] it returns the actual deposit amount
    // [ ] it does not create a position
}
