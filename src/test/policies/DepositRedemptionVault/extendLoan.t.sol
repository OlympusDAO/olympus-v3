// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";

import {FullMath} from "src/libraries/FullMath.sol";

contract DepositRedemptionVaultExtendLoanTest is DepositRedemptionVaultTest {
    event LoanExtended(address indexed user, uint16 indexed redemptionId, uint256 newDueDate);

    // ===== TESTS ===== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, 1);
    }

    // given the redemption id is invalid
    //  [X] it reverts

    function test_givenRedemptionIdIsInvalid_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidRedemptionId(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, 1);
    }

    // given a loan has not been created
    //  [X] it reverts

    function test_givenLoanHasNotBeenCreated_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
    {
        // Expect revert
        _expectRevertInvalidLoan(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, 1);
    }

    // given the facility is not authorized
    //  [X] it reverts

    function test_givenFacilityIsNotAuthorized_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenFacilityIsDeauthorized(address(cdFacility))
    {
        // Expect revert
        _expectRevertFacilityNotRegistered(address(cdFacility));

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, 1);
    }

    // when the months is 0
    //  [X] it reverts

    function test_whenMonthsIsZero_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
    {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, 0);
    }

    // given the loan has expired
    //  [X] it reverts

    function test_givenLoanHasExpired_reverts(
        uint48 elapsed_
    ) public givenLocallyActive givenCommittedDefault(COMMITMENT_AMOUNT) givenLoanDefault {
        elapsed_ = uint48(
            bound(elapsed_, block.timestamp + PERIOD_MONTHS * 30 days, type(uint48).max)
        );
        vm.warp(elapsed_);

        // Expect revert
        _expectRevertLoanIncorrectState(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, 1);
    }

    // given the loan is defaulted
    //  [X] it reverts

    function test_givenLoanIsDefaulted_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenLoanExpired(recipient, 0)
        givenLoanClaimedDefault(recipient, 0)
    {
        // Expect revert
        _expectRevertLoanIncorrectState(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, 1);
    }

    // given the loan is repaid
    //  [X] it reverts

    function test_givenLoanIsRepaid_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenRecipientHasReserveToken
        givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient
    {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 amountToRepay = loan.principal + loan.interest;
        _repayLoan(recipient, 0, amountToRepay);

        // Expect revert
        _expectRevertLoanIncorrectState(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, 1);
    }

    // given the annual interest rate is not set
    //  [X] it reverts

    function test_givenAnnualInterestRateIsNotSet_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenAnnualInterestRate(iReserveToken, 0)
    {
        // Expect revert
        _expectRevertInterestRateNotSet(iReserveToken);

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, 1);
    }

    // given the caller has not approved the redemption vault to spend the deposit tokens
    //  [X] it reverts

    function test_givenCallerHasNotApprovedSpending_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenRecipientHasReserveToken
    {
        // Expect revert
        _expectRevertERC20InsufficientAllowance();

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, 1);
    }

    // given the loan interest has been partially repaid
    //  [X] the due date is extended by the number of months specified
    //  [X] the principal is not increased
    //  [X] the interest is increased by the principal * interest rate * extension months / 12
    //  [X] it emits a LoanExtended event
    //  [X] it transfers deposit tokens from the caller

    function test_givenLoanInterestPartiallyRepaid(
        uint256 amount_,
        uint8 months_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenRecipientHasReserveToken
        givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient
    {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);

        amount_ = bound(amount_, 1, loan.interest);
        months_ = uint8(bound(months_, 1, 12));
        _repayLoan(recipient, 0, amount_);

        // Call function
        (uint48 newDueDate, uint256 interestPayable) = redemptionVault.previewExtendLoan(
            recipient,
            0,
            months_
        );

        // Assert due date
        assertEq(newDueDate, loan.dueDate + uint48(months_) * uint48(30 days), "due date mismatch");

        // Assert interest payable
        assertEq(
            interestPayable,
            FullMath.mulDivUp(loan.principal, uint256(months_) * 10e2, 12 * 100e2),
            "interest payable mismatch"
        );

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit LoanExtended(recipient, 0, newDueDate);

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, months_);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, loan.principal, loan.interest - amount_, false, newDueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            loan.principal + RESERVE_TOKEN_AMOUNT - amount_ - interestPayable,
            amount_ + interestPayable,
            0
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, COMMITMENT_AMOUNT);
    }

    // given the loan principal has been partially repaid
    //  [X] the due date is extended by the number of months specified
    //  [X] the principal is not increased
    //  [X] the interest is increased by the principal * interest rate * extension months / 12
    //  [X] it emits a LoanExtended event
    //  [X] it transfers deposit tokens from the caller

    function test_givenLoanPrincipalPartiallyRepaid(
        uint256 principalAmount_,
        uint8 months_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenRecipientHasReserveToken
        givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient
    {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);

        principalAmount_ = bound(principalAmount_, 1, loan.principal - 1);
        months_ = uint8(bound(months_, 1, 12));
        _repayLoan(recipient, 0, loan.interest + principalAmount_);
        uint256 remainingPrincipal = loan.principal - principalAmount_;

        // Determine interest to be paid
        uint256 expectedInterest = FullMath.mulDivUp(
            remainingPrincipal,
            uint256(months_) * 10e2,
            12 * 100e2
        );

        // Call function
        (uint48 newDueDate, uint256 interestPayable) = redemptionVault.previewExtendLoan(
            recipient,
            0,
            months_
        );

        // Assert due date
        assertEq(newDueDate, loan.dueDate + uint48(months_) * uint48(30 days), "due date mismatch");

        // Assert interest payable
        assertEq(interestPayable, expectedInterest, "interest payable mismatch");

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit LoanExtended(recipient, 0, newDueDate);

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, months_);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, remainingPrincipal, 0, false, newDueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            loan.principal +
                RESERVE_TOKEN_AMOUNT -
                principalAmount_ -
                loan.interest -
                expectedInterest,
            expectedInterest + loan.interest,
            0
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, COMMITMENT_AMOUNT);
    }

    // [X] the due date is extended by the number of months specified
    // [X] the principal is not increased
    // [X] the interest is increased by the principal * interest rate * extension months / 12
    // [X] it emits a LoanExtended event
    // [X] it transfers deposit tokens from the caller

    function test_success(
        uint8 months_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenRecipientHasReserveToken
        givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient
    {
        months_ = uint8(bound(months_, 1, 12));

        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);

        // Determine interest to be paid
        uint256 expectedInterest = FullMath.mulDivUp(
            loan.principal,
            uint256(months_) * 10e2,
            12 * 100e2
        );

        // Call function
        (uint48 newDueDate, uint256 interestPayable) = redemptionVault.previewExtendLoan(
            recipient,
            0,
            months_
        );

        // Assert due date
        assertEq(newDueDate, loan.dueDate + uint48(months_) * uint48(30 days), "due date mismatch");

        // Assert interest payable
        assertEq(interestPayable, expectedInterest, "interest payable mismatch");

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit LoanExtended(recipient, 0, newDueDate);

        // Call function
        vm.prank(recipient);
        redemptionVault.extendLoan(0, months_);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, loan.principal, loan.interest, false, newDueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            loan.principal + RESERVE_TOKEN_AMOUNT - expectedInterest,
            expectedInterest,
            0
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, COMMITMENT_AMOUNT);

        // Assert borrowed amount on DepositManager
        assertEq(
            depositManager.getBorrowedAmount(iReserveToken, address(cdFacility)),
            loan.initialPrincipal,
            "getBorrowedAmount"
        );

        // Assert committed funds have been reduced
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            COMMITMENT_AMOUNT - loan.initialPrincipal,
            "committed deposits"
        );
    }
}
