// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

contract UncommitCDFTest is ConvertibleDepositFacilityTest {
    // given the contract is disabled
    //  [ ] it reverts
    // when the commitment ID does not exist
    //  [ ] it reverts
    // when the commitment ID exists for a different user
    //  [ ] it reverts
    // given the amount to uncommit is more than the commitment
    //  [ ] it reverts
    // [ ] it transfers the CD tokens from the contract to the caller
    // [ ] it reduces the commitment amount
    // [ ] it emits an Uncommitted event
}
