// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {CoolerComposites} from "src/policies/cooler/CoolerComposites.sol";

contract CoolerCompositesTest is Test {
    // TODO
}

contract CoolerCompositesAddAndBorrowTest is CoolerCompositesTest {
    // given authorization has not been provided
    //  given an authorization signature has not been provided
    //   [ ] it reverts
    //  given an authorization signature has been provided
    //   [ ] it sets authorization
    //   [ ] it adds collateral and borrows
    // given an authorization signature has been provided
    //  [ ] it sets authorization
    //  [ ] it adds collateral and borrows
    // given the caller has not approved the composites contract to spend the collateral
    //  [ ] it reverts
    // given the caller does not have enough collateral
    //  [ ] it reverts
    // [ ] it adds collateral and borrows
}

contract CoolerCompositesRepayAndRemoveTest is CoolerCompositesTest {
    // given authorization has not been provided
    //  given an authorization signature has not been provided
    //   [ ] it reverts
    //  given an authorization signature has been provided
    //   [ ] it sets authorization
    //   [ ] it repays and removes collateral
    // given an authorization signature has been provided
    //  [ ] it sets authorization
    //  [ ] it repays and removes collateral
    // given the caller has not approved the composites contract to spend the debt token
    //  [ ] it reverts
    // given the caller does not have enough debt token
    //  [ ] it reverts
    // [ ] it repays and removes collateral
}
