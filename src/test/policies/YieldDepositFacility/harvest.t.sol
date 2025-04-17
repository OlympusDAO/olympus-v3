// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";

contract HarvestYDFTest is YieldDepositFacilityTest {
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
    //  [ ] it transfers the yield to the caller
    //  [ ] it transfers the yield fee to the treasury
    //  [ ] it updates the last yield conversion rate
    //  [ ] it emits a Harvest event
    //  [ ] it withdraws the yield from the CDEPO module
    // given the owner has claimed yield
    //  given a rate snapshot is not available for the expiry timestamp
    //   [ ] it uses the rate snapshot from the previous rounded timestamp
    //  [ ] it returns the yield since the last claim
    //  [ ] it transfers the yield to the caller
    //  [ ] it transfers the yield fee to the treasury
    //  [ ] it updates the last yield conversion rate
    //  [ ] it emits a Harvest event
    //  [ ] it withdraws the yield from the CDEPO module
    // given the position has expired
    //  given a rate snapshot is not available for the expiry timestamp
    //   [ ] it uses the rate snapshot from the previous rounded timestamp
    //  [ ] it returns the yield up to the conversion rate before expiry
    //  [ ] it transfers the yield to the caller
    //  [ ] it transfers the yield fee to the treasury
    //  [ ] it updates the last yield conversion rate
    //  [ ] it emits a Harvest event
    //  [ ] it withdraws the yield from the CDEPO module
    // given the yield fee is 0
    //  [ ] it returns the yield
    //  [ ] it updates the last yield conversion rate
    //  [ ] it transfers the yield to the caller
    //  [ ] it does not transfer the yield fee to the treasury
    //  [ ] it emits a Harvest event
    //  [ ] it withdraws the yield from the CDEPO module
}
