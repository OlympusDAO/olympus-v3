// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";

contract DepositRedemptionVaultRepayLoanTest is DepositRedemptionVaultTest {
    // ===== TESTS ===== //

    // given the contract is disabled
    //  [ ] it reverts

    // given the redemption id is invalid
    //  [ ] it reverts

    // given the loan id is invalid
    //  [ ] it reverts

    // given the facility is not authorized
    //  [ ] it reverts

    // when the amount is 0
    //  [ ] it reverts

    // given the loan is already repaid in full
    //  [ ] it reverts

    // when the amount is greater than the principal and interest owed
    //  [ ] it reverts

    // when the amount is less than or equal to the interest owed
    //  [ ] it reduces the interest owed
    //  [ ] it does not reduce the principal owed
    //  [ ] it reduces the total principal borrowed
    //  [ ] it transfers deposit tokens from the caller
    //  [ ] it does not transfer any receipt tokens
    //  [ ] it emits a LoanRepaid event

    // when the amount is greater than the interest owed
    //  [ ] it reduces the interest owed
    //  [ ] it reduces the principal owed
    //  [ ] it reduces the total principal borrowed
    //  [ ] it transfers deposit tokens from the caller
    //  [ ] it does not transfer any receipt tokens
    //  [ ] it emits a LoanRepaid event
}
