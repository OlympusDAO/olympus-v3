// SPDX-License-Identifier: UNLICENSED
// solhint-disable one-contract-per-file
pragma solidity 0.8.15;

import {CoolerCompositesV2Test} from "./CoolerCompositesV2Test.sol";

contract CoolerCompositesV2AddCollateralAndBorrowTest is CoolerCompositesV2Test {
    // ========= TESTS ========= //
    // given the contract is disabled
    //  [ ] it reverts
    // given authorization has not been provided previously
    //  when an authorization signature has not been provided
    //   [ ] it reverts
    //  [ ] it adds collateral and borrows
    // given authorization has been provided previously
    //  when an authorization signature has not been provided
    //   [ ] it adds collateral and borrows
    //  [ ] it adds collateral and borrows
    // when autoDelegate is true
    //  when delegationRequests are provided
    //   [ ] it reverts
    //  when useGohm is false
    //   given the caller has not approved spending of the OHM token
    //    [ ] it reverts
    //   given the caller has insufficient OHM balance
    //    [ ] it reverts
    //   given the staking contract has the warmup period enabled
    //    [ ] it reverts
    //   [ ] it stakes OHM to gOHM
    //   [ ] it delegates governance power for the gOHM amount to the caller
    //   [ ] it adds collateral and borrows
    //   [ ] the loan position matches the preview
    //  when useGohm is true
    //   given the caller has not approved spending of the gOHM token
    //    [ ] it reverts
    //   given the caller has insufficient gOHM balance
    //    [ ] it reverts
    //   [ ] it delegates governance power for the gOHM amount to the caller
    //   [ ] it adds collateral and borrows
    //   [ ] the loan position matches the preview
    // when autoDelegate is false
    //  when delegationRequests are provided
    //   [ ] it uses the provided delegation requests to delegate governance power for the gOHM amount
    //   [ ] it adds collateral and borrows
    //  when delegationRequests are provided
    //   [ ] it does not delegate any governance power
    //   [ ] it adds collateral and borrows
}
