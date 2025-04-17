// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";

contract PreviewHarvestYDFTest is YieldDepositFacilityTest {
    // given the contract is disabled
    //  [ ] it reverts
    // given the position does not exist
    //  [ ] it reverts
    // given the position is not a supported CD token
    //  [ ] it reverts
    // given the position is convertible
    //  [ ] it reverts
    // given the position is not the owner of the position
    //  [ ] it reverts
    // given any position has a different CD token
    //  [ ] it reverts
    // given the owner has never claimed yield
    //  [ ] it returns the yield since minting
    // given the position has expired
    //  [ ] it returns the yield up to the conversion rate before expiry
    // given the yield fee is set
    //  [ ] it returns the yield minus the yield fee
    // [ ] it returns the yield since the last claim
}
