// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityHandleWithdrawTest is ConvertibleDepositFacilityTest {
    // ========== TESTS ========== //
    // given the contract is disabled
    //  [ ] it reverts
    // given the caller is not authorized
    //  [ ] it reverts
    // when the amount is greater than the available capacity
    //  [ ] it reverts
    // [ ] it burns the amount of receipt tokens from the caller
    // [ ] it transfers the tokens to the recipient
}
