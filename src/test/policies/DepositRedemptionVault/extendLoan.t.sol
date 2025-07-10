// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";

contract DepositRedemptionVaultExtendLoanTest is DepositRedemptionVaultTest {
    // ===== TESTS ===== //

    // given the contract is disabled
    //  [ ] it reverts

    // given the redemption id is invalid
    //  [ ] it reverts

    // given the loan id is invalid
    //  [ ] it reverts

    // given the facility is not authorized
    //  [ ] it reverts

    // when the months is 0
    //  [ ] it reverts

    // given the loan has expired
    //  [ ] it reverts

    // given the loan is defaulted
    //  [ ] it reverts

    // given the loan is repaid
    //  [ ] it reverts

    // given the loan interest has been partially repaid
    //  [ ] the due date is extended by the number of months specified
    //  [ ] the principal is not increased
    //  [ ] the interest is increased by the principal * interest rate * extension months / 12
    //  [ ] it emits a LoanExtended event
    //  [ ] it transfers deposit tokens from the caller

    // given the loan principal has been partially repaid
    //  [ ] the due date is extended by the number of months specified
    //  [ ] the principal is not increased
    //  [ ] the interest is increased by the principal * interest rate * extension months / 12
    //  [ ] it emits a LoanExtended event
    //  [ ] it transfers deposit tokens from the caller

    // [ ] the due date is extended by the number of months specified
    // [ ] the principal is not increased
    // [ ] the interest is increased by the principal * interest rate * extension months / 12
    // [ ] it emits a LoanExtended event
    //  [ ] it transfers deposit tokens from the caller
}
