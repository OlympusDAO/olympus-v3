// SPDX-License-Identifier: UNLICENSED
// solhint-disable one-contract-per-file
pragma solidity 0.8.15;

import {CoolerCompositesV2Test} from "./CoolerCompositesV2Test.sol";

contract CoolerCompositesV2RepayAndRemoveCollateralTest is CoolerCompositesV2Test {
    // ========= TESTS ========= //
    // given the contract is disabled
    //  [ ] it reverts
    // given authorization has not been provided previously
    //  when an authorization signature has not been provided
    //   [ ] it reverts
    //  [ ] it repays and removes collateral
    // given authorization has been provided previously
    //  when an authorization signature has not been provided
    //   [ ] it repays and removes collateral
    //  [ ] it repays and removes collateral
    // given the caller has not approved spending of the debt token
    //  [ ] it reverts
    // given the caller has insufficient debt token balance
    //  [ ] it reverts
    // when autoDelegate is true
    //  when delegationRequests are provided
    //   [ ] it reverts
    //  when useGohm is false
    //   [ ] it removes delegation for the gOHM amount from the caller
    //   [ ] it repays and removes collateral
    //   [ ] it transfers OHM to the caller
    //  when useGohm is true
    //   [ ] it removes delegation for the gOHM amount from the caller
    //   [ ] it repays and removes collateral
    // when autoDelegate is false
    //  when delegationRequests are provided
    //   [ ] it uses the provided delegation requests to delegate governance power for the gOHM amount
    //   [ ] it repays and removes collateral
    //  [ ] it does not delegate any governance power
    //  [ ] it repays and removes collateral
    // given the repayAmount is greater than the outstanding debt
    //  [ ] it refunds the excess debt token to the caller
}
