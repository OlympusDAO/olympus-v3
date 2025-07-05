// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityHandleCommitCancelTest is ConvertibleDepositFacilityTest {

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [ ] it reverts

    // given the caller is not an authorized operator
    //  [ ] it reverts

    // when the amount is greater than the committed amount
    //  [ ] it reverts

    // [ ] it does not transfer any tokens
    // [ ] it emits an event
    // [ ] it decreases the committed deposits by the amount
    // [ ] it increases the available deposits by the amount
}
