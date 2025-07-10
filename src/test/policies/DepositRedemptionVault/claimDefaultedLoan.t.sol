// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";

contract DepositRedemptionVaultClaimDefaultedLoanTest is DepositRedemptionVaultTest {
    // ===== TESTS ===== //

    // given the contract is disabled
    //  [ ] it reverts

    // given the redemption id is invalid
    //  [ ] it reverts

    // given the loan id is invalid
    //  [ ] it reverts

    // given the facility is not authorized
    //  [ ] it reverts

    // given the loan has not expired
    //  [ ] it reverts

    // given the loan has defaulted
    //  [ ] it reverts

    // given the loan is fully repaid
    //  [ ] it reverts

    // given the keeper reward percentage is 0
    //  [ ] it marks the loan as defaulted
    //  [ ] it sets the loan principal to 0
    //  [ ] it sets the loan interest to 0
    //  [ ] it reduces the amount borrowed from the facility by the principal
    //  [ ] it reduces the committed amount from the facility by the principal
    //  [ ] it reduces the redemption amount by the principal
    //  [ ] it does not transfer any deposit tokens to the caller
    //  [ ] it transfers all of the deposit tokens to the TRSRY
    //  [ ] it emits a LoanDefaulted event
    //  [ ] it emits a RedemptionCancelled event

    // [ ] it marks the loan as defaulted
    // [ ] it sets the loan principal to 0
    // [ ] it sets the loan interest to 0
    // [ ] it reduces the amount borrowed from the facility by the principal
    // [ ] it reduces the committed amount from the facility by the principal
    // [ ] it reduces the redemption amount by the principal
    // [ ] it transfers the percentage of the principal as keeper reward to the caller
    // [ ] it transfers the remainder of the principal to the TRSRY
    // [ ] it emits a LoanDefaulted event
    // [ ] it emits a RedemptionCancelled event
}
