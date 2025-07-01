// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityClaimYieldTest is ConvertibleDepositFacilityTest {
    // ========== TESTS ========== //
    // given the facility is disabled
    //  [ ] it returns 0
    // given the asset is not supported
    //  [ ] it returns 0
    // given the yield is 0
    //  [ ] it returns 0
    // [ ] it transfers the yield to the treasury
    // [ ] it emits the ClaimedYield event
    // [ ] it returns the yield
}
