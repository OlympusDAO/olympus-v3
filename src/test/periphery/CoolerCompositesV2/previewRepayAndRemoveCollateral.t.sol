// SPDX-License-Identifier: UNLICENSED
// solhint-disable one-contract-per-file
pragma solidity 0.8.15;

import {CoolerCompositesV2Test} from "./CoolerCompositesV2Test.sol";

contract CoolerCompositesV2RepayAndRemoveCollateralTest is CoolerCompositesV2Test {
    // ========= TESTS ========= //
    // given the contract is disabled
    //  [ ] it reverts
    // when the collateral amount is greater than the existing collateral
    //  [ ] it returns success = false
    //  [ ] it returns the existing collateral amount
    //  [ ] it returns the existing debt amount
    // when useGohm is false
    //  [ ] it converts the OHM amount into gOHM
    //  [ ] it returns success = true
    //  [ ] it returns the post-withdraw collateral amount in gOHM
    //  [ ] it returns the remaining debt amount
    // when the repay amount is greater than the existing debt
    //  [ ] it returns success = true
    //  [ ] it returns the post-withdraw collateral amount
    //  [ ] it returns 0
    // [ ] it returns success = true
    // [ ] it returns the post-withdraw collateral amount
    // [ ] it returns the remaining debt amount
}
