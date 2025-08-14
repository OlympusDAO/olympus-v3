// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";

contract DepositRedemptionVaultRepayLoanTest is DepositRedemptionVaultTest {
    event LoanRepaid(
        address indexed user,
        uint16 indexed redemptionId,
        uint256 principal,
        uint256 interest
    );

    // ===== TESTS ===== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        redemptionVault.repayLoan(0, 1);
    }

    // given the redemption id is invalid
    //  [X] it reverts

    function test_givenRedemptionIdIsInvalid_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidRedemptionId(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.repayLoan(0, 1);
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
        redemptionVault.repayLoan(0, 1);
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
        redemptionVault.repayLoan(0, 1);
    }

    // when the amount is 0
    //  [X] it reverts

    function test_whenAmountIsZero_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
    {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        redemptionVault.repayLoan(0, 0);
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
        redemptionVault.repayLoan(0, 1);
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
        redemptionVault.repayLoan(0, 1);
    }

    // given the loan is already repaid in full
    //  [X] it reverts

    function test_givenLoanIsRepaid_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(redemptionVault),
            RESERVE_TOKEN_AMOUNT
        )
    {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 amountToRepay = loan.principal + loan.interest;
        _repayLoan(recipient, 0, amountToRepay);

        // Expect revert
        _expectRevertLoanIncorrectState(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.repayLoan(0, 1);
    }

    // when the amount is greater than the principal and interest owed
    //  [X] it reverts

    function test_whenAmountIsGreaterThanPrincipalAndInterest_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(redemptionVault),
            RESERVE_TOKEN_AMOUNT
        )
    {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        amount_ = bound(amount_, loan.principal + loan.interest + 1, RESERVE_TOKEN_AMOUNT);

        // Expect revert
        _expectRevertLoanAmountExceeded(recipient, 0, loan.principal);

        // Call function
        vm.prank(recipient);
        redemptionVault.repayLoan(0, amount_);
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
        redemptionVault.repayLoan(0, 1);
    }

    // when the amount is less than or equal to the interest owed
    //  [X] it reduces the interest owed
    //  [X] it does not reduce the principal owed
    //  [X] it reduces the total principal borrowed
    //  [X] it transfers deposit tokens from the caller
    //  [X] it does not transfer any receipt tokens
    //  [X] it emits a LoanRepaid event

    function test_whenAmountIsLessThanOrEqualToInterestOwed(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(redemptionVault),
            RESERVE_TOKEN_AMOUNT
        )
    {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        amount_ = bound(amount_, 1, loan.interest);

        // Emit event
        vm.expectEmit(true, true, true, true);
        emit LoanRepaid(recipient, 0, 0, amount_);

        // Call function
        vm.prank(recipient);
        redemptionVault.repayLoan(0, amount_);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, loan.principal, loan.interest - amount_, false, loan.dueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            LOAN_AMOUNT + RESERVE_TOKEN_AMOUNT - amount_,
            amount_,
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

        // Assert committed funds have been increased
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            COMMITMENT_AMOUNT - loan.initialPrincipal,
            "committed deposits"
        );
    }

    // when the amount is greater than the interest owed
    //  [X] it reduces the interest owed
    //  [X] it reduces the principal owed
    //  [X] it reduces the total principal borrowed
    //  [X] it transfers deposit tokens from the caller
    //  [X] it does not transfer any receipt tokens
    //  [X] it emits a LoanRepaid event

    function test_whenAmountIsGreaterThanInterestOwed(
        uint256 principalAmount_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(redemptionVault),
            RESERVE_TOKEN_AMOUNT
        )
    {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        principalAmount_ = bound(principalAmount_, 1, loan.principal);

        // Emit event
        vm.expectEmit(true, true, true, true);
        emit LoanRepaid(recipient, 0, principalAmount_, loan.interest);

        // Call function
        vm.prank(recipient);
        redemptionVault.repayLoan(0, principalAmount_ + loan.interest);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, loan.principal - principalAmount_, 0, false, loan.dueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            LOAN_AMOUNT + RESERVE_TOKEN_AMOUNT - principalAmount_ - loan.interest,
            loan.interest,
            0
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, COMMITMENT_AMOUNT);

        // Assert borrowed amount on DepositManager
        assertEq(
            depositManager.getBorrowedAmount(iReserveToken, address(cdFacility)),
            loan.initialPrincipal - principalAmount_,
            "getBorrowedAmount"
        );

        // Assert committed funds have been increased
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            COMMITMENT_AMOUNT - (loan.initialPrincipal - principalAmount_),
            "committed deposits"
        );
    }

    function test_givenCommitmentAmountFuzz_repayInFull(
        uint256 commitmentAmount_
    )
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipientTwo,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasConvertibleDepositTokenDefault(RESERVE_TOKEN_AMOUNT)
        givenVaultAccruesYield(iVault, 3e18) // Ensures that there are rounding inconsistencies when depositing/withdrawing from the vault
    {
        commitmentAmount_ = bound(commitmentAmount_, 1e17, 5e18);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        // Borrow
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);

        uint256 recipientReserveTokenBalanceBefore = reserveToken.balanceOf(recipient);

        // Determine the amount to pay back
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 repaymentAmount = loan.principal + loan.interest;

        // Mint and approve
        reserveToken.mint(recipient, repaymentAmount);
        vm.prank(recipient);
        reserveToken.approve(address(redemptionVault), repaymentAmount);

        // Call function
        // Emit event
        vm.expectEmit(true, true, true, true);
        emit LoanRepaid(recipient, 0, loan.principal, loan.interest);

        // Call function
        vm.prank(recipient);
        redemptionVault.repayLoan(0, repaymentAmount);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, loan.initialPrincipal, 0, 0, false, loan.dueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            recipientReserveTokenBalanceBefore, // repaymentAmount is minted and used
            loan.interest,
            0
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(
            recipient,
            _previousDepositActualAmount - commitmentAmount_,
            commitmentAmount_
        );

        // Assert borrowed amount on DepositManager
        assertEq(
            depositManager.getBorrowedAmount(iReserveToken, address(cdFacility)),
            0,
            "getBorrowedAmount"
        );

        // Assert committed funds
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            commitmentAmount_,
            "committed deposits"
        );
    }

    function test_givenCommitmentAmountFuzz_repayInFull(
        uint256 commitmentAmount_
    )
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipientTwo,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasConvertibleDepositTokenDefault(RESERVE_TOKEN_AMOUNT)
        givenVaultAccruesYield(iVault, 3e18) // Ensures that there are rounding inconsistencies when depositing/withdrawing from the vault
    {
        commitmentAmount_ = bound(commitmentAmount_, 1e17, 5e18);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        // Borrow
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);

        uint256 recipientReserveTokenBalanceBefore = reserveToken.balanceOf(recipient);

        // Determine the amount to pay back
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 repaymentAmount = loan.principal + loan.interest;

        // Mint and approve
        reserveToken.mint(recipient, repaymentAmount);
        vm.prank(recipient);
        reserveToken.approve(address(redemptionVault), repaymentAmount);

        // Call function
        vm.prank(recipient);
        redemptionVault.repayLoan(0, repaymentAmount);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, loan.principal, 0, 0, false, loan.dueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            recipientReserveTokenBalanceBefore, // repaymentAmount is minted and used
            loan.interest,
            0
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, _previousDepositActualAmount - commitmentAmount_, commitmentAmount_);

        // Assert borrowed amount on DepositManager
        assertEq(
            depositManager.getBorrowedAmount(iReserveToken, address(cdFacility)),
            0,
            "getBorrowedAmount"
        );
    }
}
