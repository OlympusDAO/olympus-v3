// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityHandleLoanRepayTest is ConvertibleDepositFacilityTest {
    // ========== TESTS ========== //
    // given the contract is disabled
    //  [ ] it reverts
    // given the caller is not authorized
    //  [ ] it reverts
    // when the amount is greater than the borrowed amount
    //  [ ] it reverts
    // [ ] it transfers the tokens from the payer to the deposit manager
}
