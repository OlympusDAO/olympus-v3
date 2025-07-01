// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityClaimYieldTest is ConvertibleDepositFacilityTest {
    // ========== TESTS ========== //

    // given the facility is disabled
    //  [ ] it does nothing
    // given there are no supported assets
    //  [ ] it does nothing
    // given an asset has no yield
    //  [ ] it does nothing
    // [ ] it transfers the token yields to the treasury
    // [ ] it emits ClaimedYield events
}
