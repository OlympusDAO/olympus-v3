// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";

contract DepositRedemptionVaultSetAnnualInterestRateTest is DepositRedemptionVaultTest {
    // ===== TESTS ===== //

    // given the caller is not the admin
    //  [ ] it reverts

    // given the caller is not the admin or manager
    //  [ ] it reverts

    // given the rate is greater than 100e2
    //  [ ] it reverts

    // given the rate is 0
    //  [ ] it reverts

    // given the asset is not supported
    //  [ ] it sets the annual interest rate for the asset
    //  [ ] it emits a InterestRateSet event

    // [ ] it sets the annual interest rate for the asset
    // [ ] it emits a InterestRateSet event
}
