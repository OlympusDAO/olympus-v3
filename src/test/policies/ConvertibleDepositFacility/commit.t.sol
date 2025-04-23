// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

contract CommitCDFTest is ConvertibleDepositFacilityTest {
    // given the contract is disabled
    //  [ ] it reverts
    // when the CD token is not supported by CDEPO
    //  [ ] it reverts
    // when the caller has not approved spending of the CD token by the contract
    //  [ ] it reverts
    // when the caller does not have enough CD tokens
    //  [ ] it reverts
    // given there is an existing commitment for the caller
    //  given the existing commitment is for the same CD token
    //   [ ] it creates a new commitment for the caller
    //   [ ] it returns a commitment ID of 1
    //  [ ] it creates a new commitment for the caller
    //  [ ] it returns a commitment ID of 1
    // given there is an existing commitment for a different user
    //  [ ] it returns a commitment ID of 0
    // [ ] it transfers the CD tokens from the caller to the contract
    // [ ] it creates a new commitment for the caller
    // [ ] the new commitment has the same CD token
    // [ ] the new commitment has an amount equal to the amount of CD tokens committed
    // [ ] the new commitment has a redeemable timestamp of the current timestamp + the number of months in the CD token's period * 30 days
    // [ ] it emits a Committed event
    // [ ] it returns a commitment ID of 0
}
