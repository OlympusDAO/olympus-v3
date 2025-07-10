// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";

contract DepositRedemptionVaultBorrowAgainstRedemptionTest is DepositRedemptionVaultTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    event LoanCreated(
        address indexed user,
        uint16 indexed redemptionId,
        uint16 indexed loanId,
        uint256 amount,
        address facility
    );

    // ===== TESTS ===== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0, 1);
    }

    // given the redemption id is invalid
    //  [X] it reverts

    function test_givenRedemptionIdIsInvalid_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidRedemptionId(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0, 1);
    }

    // given the facility is not authorized
    //  [X] it reverts

    function test_givenFacilityIsNotAuthorized_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenFacilityIsDeauthorized(address(cdFacility))
    {
        // Expect revert
        _expectRevertFacilityNotRegistered(address(cdFacility));

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0, 1);
    }

    // when the amount is 0
    //  [X] it reverts

    function test_givenAmountIsZero_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0, 0);
    }

    // given the borrow percentage is 0
    //  [X] it reverts

    function test_givenBorrowPercentageIsZero_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Expect revert
        _expectRevertBorrowLimitExceeded(1, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0, 1);
    }

    // given the interest rate is 0
    //  [X] it reverts

    function test_givenInterestRateIsZero_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenMaxBorrowPercentage(iReserveToken, 90e2)
    {
        // Expect revert
        _expectRevertInterestRateNotSet(iReserveToken);

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0, 1);
    }

    // given the number of loans exceeds uint16 max
    //  [X] it reverts

    function test_givenNumberOfLoansExceedsUint16Max_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenMaxBorrowPercentage(iReserveToken, 90e2)
        givenAnnualInterestRate(iReserveToken, 10e2)
    {
        // Create uint16 max number of loans
        for (uint16 i = 0; i < type(uint16).max; i++) {
            vm.prank(recipient);
            redemptionVault.borrowAgainstRedemption(0, 1);
        }

        // Expect revert
        _expectRevertMaxLoans(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0, 1);
    }

    // when the amount is greater than the allowed percentage of the redemption amount
    //  [X] it reverts

    function test_whenAmountIsGreaterThanMaxBorrow_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenMaxBorrowPercentage(iReserveToken, 90e2)
        givenAnnualInterestRate(iReserveToken, 10e2)
    {
        amount_ = bound(amount_, (COMMITMENT_AMOUNT * 90e2) / 100e2 + 1, type(uint256).max);

        // Expect revert
        _expectRevertBorrowLimitExceeded(amount_, (COMMITMENT_AMOUNT * 90e2) / 100e2);

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0, amount_);
    }

    // given there is an existing loan
    //  when the previous amount plus new amount is greater than the allowed percentage of the redemption amount
    //   [X] it reverts

    function test_givenLoan_whenAmountIsGreaterThanMaxBorrow_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenMaxBorrowPercentage(iReserveToken, 90e2)
        givenAnnualInterestRate(iReserveToken, 10e2)
        givenLoan(recipient, 0, 8e17)
    {
        amount_ = bound(amount_, 1e17 + 1, type(uint256).max);

        // Expect revert
        _expectRevertBorrowLimitExceeded(amount_, 1e17);

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0, amount_);
    }

    //  [X] it creates a new loan record
    //  [X] the due date is the deposit period term in the future from now
    //  [X] the principal is the amount specified
    //  [X] the interest is the principal * interest rate * deposit period / 12
    //  [X] isDefaulted is false
    //  [X] the loan id is one greater than the previous loan id
    //  [X] the total borrowed is the sum of the previous amount and the new amount
    //  [X] it emits a LoanCreated event
    //  [X] it transfers the deposit tokens to the caller
    //  [X] the redemption vault retains custody of the receipt tokens

    function test_givenLoan_whenAmountIsLessThanMaxBorrow(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenMaxBorrowPercentage(iReserveToken, 90e2)
        givenAnnualInterestRate(iReserveToken, 10e2)
        givenLoan(recipient, 0, 8e17)
    {
        amount_ = bound(amount_, 1, 1e17);

        // Calculations
        uint256 expectedInterest = (amount_ * 10e2 * PERIOD_MONTHS) / (100e2 * 12);
        uint48 expectedDueDate = uint48(block.timestamp + PERIOD_MONTHS * 30 days);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit LoanCreated(recipient, 0, 1, amount_, address(cdFacility));

        // Call function
        vm.prank(recipient);
        uint16 loanId = redemptionVault.borrowAgainstRedemption(0, amount_);

        // Assert loan
        assertEq(loanId, 1, "loan id mismatch");
        _assertLoan(recipient, 0, 1, amount_, expectedInterest, false, expectedDueDate);

        // Assert total borrowed
        _assertTotalBorrowed(recipient, 0, 8e17 + amount_);

        // Assert available borrow
        _assertAvailableBorrow(recipient, 0, (COMMITMENT_AMOUNT * 90e2) / 100e2 - 8e17 - amount_);

        // Assert deposit token balances
        _assertDepositTokenBalances(recipient, 8e17 + amount_, 0, 0);

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, COMMITMENT_AMOUNT);
    }

    // [X] it creates a new loan record
    // [X] the due date is the deposit period term in the future fro now
    // [X] the principal is the amount specified
    // [X] the interest is the principal * interest rate * deposit period / 12
    // [X] the loan id is 0
    // [X] the total borrowed is the new amount
    // [X] it emits a LoanCreated event
    // [X] it transfers the deposit tokens to the caller
    // [X] the redemption vault retains custody of the receipt tokens

    function test_success(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenMaxBorrowPercentage(iReserveToken, 90e2)
        givenAnnualInterestRate(iReserveToken, 10e2)
    {
        amount_ = bound(amount_, 1, (COMMITMENT_AMOUNT * 90e2) / 100e2);

        // Calculations
        uint256 expectedInterest = (amount_ * 10e2 * PERIOD_MONTHS) / (100e2 * 12);
        uint48 expectedDueDate = uint48(block.timestamp + PERIOD_MONTHS * 30 days);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit LoanCreated(recipient, 0, 0, amount_, address(cdFacility));

        vm.startSnapshotGas("borrowAgainstRedemption");

        // Call function
        vm.prank(recipient);
        uint16 loanId = redemptionVault.borrowAgainstRedemption(0, amount_);

        vm.stopSnapshotGas();

        // Assert loan
        assertEq(loanId, 0, "loan id mismatch");
        _assertLoan(recipient, 0, 0, amount_, expectedInterest, false, expectedDueDate);

        // Assert total borrowed
        _assertTotalBorrowed(recipient, 0, amount_);

        // Assert available borrow
        _assertAvailableBorrow(recipient, 0, (COMMITMENT_AMOUNT * 90e2) / 100e2 - amount_);

        // Assert deposit token balances
        _assertDepositTokenBalances(recipient, amount_, 0, 0);

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, COMMITMENT_AMOUNT);
    }
}
