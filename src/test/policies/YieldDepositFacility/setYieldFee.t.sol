// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";

contract SetYieldFeeYDFTest is YieldDepositFacilityTest {
    // given the contract is disabled
    //  [ ] it reverts
    // given the caller is not an admin
    //  [ ] it reverts
    // given the yield fee is greater than 100e2
    //  [ ] it reverts
    // [ ] it sets the yield fee
    // [ ] it emits a YieldFeeSet event
}
