// SPDX-License-Identifier: UNLICENSED
// solhint-disable one-contract-per-file
pragma solidity 0.8.15;

import {CoolerCompositesV2Test} from "./CoolerCompositesV2Test.sol";

contract CoolerCompositesV2PreviewAddCollateralAndBorrowTest is CoolerCompositesV2Test {
    // ========= TESTS ========= //
    // given the contract is disabled
    //  [ ] it reverts
    // when useGohm is false
    //  [ ] it converts the OHM amount into gOHM
    // [ ] it returns success = true
    // [ ] it returns the post-deposit collateral amount in gOHM
    // [ ] it returns the maximum borrowable after the borrow
    // when the collateral amount is 0
    //  [ ] it returns the current collateral amount
    //  [ ] it returns the remaining borrowable amount
    // when the borrow amount results in the LLTV being exceeded
    //  [ ] it returns success = false
    //  [ ] it returns the post-deposit collateral amount
    //  [ ] it returns the maximum borrowable
    // [ ] it returns success = true
    // [ ] it returns the post-deposit collateral amount
    // [ ] it returns the maximum borrowable after the borrow
}
