// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";

contract DepositRedemptionVaultBorrowAgainstRedemptionTest is DepositRedemptionVaultTest {
    // ===== TESTS ===== //

    // given the contract is disabled
    //  [ ] it reverts

    // given the redemption id is invalid
    //  [ ] it reverts

    // given the facility is not authorized
    //  [ ] it reverts

    // when the amount is 0
    //  [ ] it reverts

    // given the borrow percentage is 0
    //  [ ] it reverts

    // given the interest rate is 0
    //  [ ] it reverts

    // given the number of loans exceeds uint16 max
    //  [ ] it reverts

    // when the amount is greater than the allowed percentage of the redemption amount
    //  [ ] it reverts

    // given there is an existing loan
    //  when the previous amount plus new amount is greater than the allowed percentage of the redemption amount
    //   [ ] it reverts
    //  [ ] it creates a new loan record
    //  [ ] the due date is the deposit period term in the future from now
    //  [ ] the principal is the amount specified
    //  [ ] the interest is the principal * interest rate * deposit period / 12
    //  [ ] isDefaulted is false
    //  [ ] the loan id is one greater than the previous loan id
    //  [ ] the total borrowed is the sum of the previous amount and the new amount
    //  [ ] it emits a LoanCreated event
    //  [ ] it transfers the deposit tokens to the caller
    //  [ ] the redemption vault retains custody of the receipt tokens

    // [ ] it creates a new loan record
    // [ ] the due date is the deposit period term in the future fro now
    // [ ] the principal is the amount specified
    // [ ] the interest is the principal * interest rate * deposit period / 12
    // [ ] the loan id is 0
    // [ ] the total borrowed is the new amount
    // [ ] it emits a LoanCreated event
    // [ ] it transfers the deposit tokens to the caller
    // [ ] the redemption vault retains custody of the receipt tokens
}
