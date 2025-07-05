// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityHandleCommitWithdrawTest is ConvertibleDepositFacilityTest {

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [ ] it reverts

    // given the caller is not an authorized operator
    //  [ ] it reverts

    // when the amount is greater than the committed amount
    //  [ ] it reverts

    // [ ] it burns the receipt tokens from the caller
    // [ ] it transfers the deposit tokens to the recipient
    // [ ] it emits an event
    // [ ] it decreases the committed deposits by the amount
    // [ ] it decreases the available deposits by the amount
}
