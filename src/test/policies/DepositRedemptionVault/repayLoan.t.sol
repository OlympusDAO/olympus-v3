// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";

contract DepositRedemptionVaultRepayLoanTest is DepositRedemptionVaultTest {
    struct FacilityAssetSnapshot {
        uint256 shares;
        uint256 assets;
    }

    uint256 public constant LOAN_PRINCIPAL_MAX_SLIPPAGE = 5;
    uint256 internal constant VAULT_DEPOSIT_AMOUNT = 1000e18;
    uint256 internal constant ONE_RESERVE_TOKEN = 1e18;
    uint256 internal constant SMALL_TEST_AMOUNT = 1e16;
    uint256 internal constant MAX_FUZZ_AMOUNT = 50e18;
    uint256 internal constant MAX_COMMITMENT_AMOUNT = 5e18;
    uint256 internal constant MIN_COMMITMENT_AMOUNT = 100;
    uint256 internal constant SMALL_PAYMENT_COUNT = 20;
    uint256 internal constant SMALL_PAYMENT_MAX_SLIPPAGE = SMALL_PAYMENT_COUNT;

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
        _repayLoan(recipient, 0, 1);
    }

    // given the redemption id is invalid
    //  [X] it reverts

    function test_givenRedemptionIdIsInvalid_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidRedemptionId(recipient, 0);

        // Call function
        _repayLoan(recipient, 0, 1);
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
        _repayLoan(recipient, 0, 1);
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
        _repayLoan(recipient, 0, 1);
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
        _repayLoan(recipient, 0, 0);
    }

    // given the loan has expired
    //  [X] it reverts

    function test_givenLoanHasExpired_reverts(
        uint256 elapsed_
    ) public givenLocallyActive givenCommittedDefault(COMMITMENT_AMOUNT) givenLoanDefault {
        elapsed_ = bound(elapsed_, block.timestamp + PERIOD_MONTHS * 30 days, type(uint48).max);
        vm.warp(elapsed_);

        // Expect revert
        _expectRevertLoanIncorrectState(recipient, 0);

        // Call function
        _repayLoan(recipient, 0, 1);
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
        _repayLoan(recipient, 0, 1);
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
        _repayLoan(recipient, 0, 1);
    }

    // when the amount is greater than the principal and interest owed (including slippage)
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
        amount_ = bound(
            amount_,
            loan.principal + loan.interest + LOAN_PRINCIPAL_MAX_SLIPPAGE,
            RESERVE_TOKEN_AMOUNT
        );

        // Expect revert
        _expectRevertMaxSlippageExceededPartial();

        // Call function
        _repayLoan(recipient, 0, amount_);
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
        _repayLoan(recipient, 0, 1);
    }

    // when the amount is less than or equal to the interest owed
    //  when the maximum slippage is not 0
    //   [X] it has no effect

    function test_whenAmountIsLessThanOrEqualToInterestOwed_givenMaxSlippage(
        uint256 amount_,
        uint256 maxSlippage_
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
        _repayLoan(recipient, 0, amount_, maxSlippage_);

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
        _repayLoan(recipient, 0, amount_);

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
    //  given there is a minimum deposit configured for the asset
    //   when the principal amount is less than the minimum deposit
    //    [X] it reduces the interest owed
    //    [X] it reduces the principal owed
    //    [X] it reduces the total principal borrowed
    //    [X] it transfers deposit tokens from the caller
    //    [X] it does not transfer any receipt tokens
    //    [X] it emits a LoanRepaid event

    function test_whenAmountIsGreaterThanInterestOwed_givenMinimumDeposit()
        public
        givenLocallyActive
        givenMinimumDeposit(SMALL_TEST_AMOUNT)
        givenVaultHasDeposit(VAULT_DEPOSIT_AMOUNT)
    {
        // Accrue yield
        _accrueYield(iVault, SMALL_TEST_AMOUNT);

        // Deposit
        _createDeposit(recipient, iReserveToken, PERIOD_MONTHS, ONE_RESERVE_TOKEN);

        // The loan principal repayment will be less than the minimum deposit.
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, SMALL_TEST_AMOUNT);

        // Borrow
        vm.prank(recipient);
        assertGt(redemptionVault.borrowAgainstRedemption(0), 0, "borrowed amount");

        // Accrue more yield
        _accrueYield(iVault, SMALL_TEST_AMOUNT);

        uint256 recipientReserveTokenBalanceBefore = reserveToken.balanceOf(recipient);

        // Determine the amount to pay back
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 repaymentAmount = loan.principal + loan.interest + LOAN_PRINCIPAL_MAX_SLIPPAGE;

        // Mint and approve
        reserveToken.mint(recipient, repaymentAmount);
        vm.prank(recipient);
        assertTrue(
            reserveToken.approve(address(redemptionVault), repaymentAmount),
            "repayment approval"
        );

        // Call function
        // Emit event (but ignore the principal and interest amounts)
        vm.expectEmit(true, true, true, false);
        emit LoanRepaid(recipient, 0, loan.principal, loan.interest);

        // Call function
        _repayLoan(recipient, 0, repaymentAmount, LOAN_PRINCIPAL_MAX_SLIPPAGE);

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
            _previousDepositActualAmount - SMALL_TEST_AMOUNT,
            SMALL_TEST_AMOUNT
        );

        // Assert borrowed amount on DepositManager
        assertEq(
            depositManager.getBorrowedAmount(iReserveToken, address(cdFacility)),
            0,
            "getBorrowedAmount"
        );

        // Assert committed funds
        assertApproxEqAbs(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            SMALL_TEST_AMOUNT,
            LOAN_PRINCIPAL_MAX_SLIPPAGE,
            "committed deposits"
        );
    }

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
        _repayLoan(recipient, 0, principalAmount_ + loan.interest);

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

    //  given there is a deposit cap
    //   when the deposit cap is reached
    //    [X] it reduces the interest owed
    //    [X] it reduces the principal owed
    //    [X] it reduces the total principal borrowed
    //    [X] it transfers deposit tokens from the caller
    //    [X] it does not transfer any receipt tokens
    //    [X] it emits a LoanRepaid event

    function test_whenAmountIsGreaterThanInterestOwed_givenDepositCap()
        public
        givenLocallyActive
        givenVaultHasDeposit(VAULT_DEPOSIT_AMOUNT)
    {
        // Accrue yield
        _accrueYield(iVault, SMALL_TEST_AMOUNT);

        // Deposit
        _createDeposit(recipient, iReserveToken, PERIOD_MONTHS, ONE_RESERVE_TOKEN);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, SMALL_TEST_AMOUNT);

        // Borrow
        vm.prank(recipient);
        assertGt(redemptionVault.borrowAgainstRedemption(0), 0, "borrowed amount");

        // Accrue more yield
        _accrueYield(iVault, SMALL_TEST_AMOUNT);

        // Set the deposit cap
        vm.prank(admin);
        depositManager.setAssetDepositCap(iReserveToken, ONE_RESERVE_TOKEN);

        // Determine the amount to pay back
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 repaymentAmount = loan.principal + loan.interest + LOAN_PRINCIPAL_MAX_SLIPPAGE;
        uint256 recipientReserveTokenBalanceBefore = reserveToken.balanceOf(recipient);

        // Fund the cap-check deposit and the later repayment with the same tokens
        reserveToken.mint(recipient, repaymentAmount);

        // Confirm that the deposit cap is active
        {
            (uint256 sharesBefore, uint256 assetAmountBefore) = depositManager.getOperatorAssets(
                iReserveToken,
                address(cdFacility)
            );
            assertGt(sharesBefore, 0, "facility should have custody shares");
            uint256 capUtilizationBefore = depositManager
                .getAssetDepositCapStatus(iReserveToken)
                .utilization;
            assertGt(
                capUtilizationBefore,
                assetAmountBefore,
                "borrowed principal should remain in cap utilization"
            );

            // Approve deposit manager to spend the reserve tokens
            vm.startPrank(recipient);
            assertTrue(
                iReserveToken.approve(address(depositManager), repaymentAmount),
                "deposit approval"
            );
            vm.stopPrank();

            vm.expectRevert(
                abi.encodeWithSelector(
                    IAssetManager.AssetManager_DepositCapExceeded.selector,
                    address(iReserveToken),
                    capUtilizationBefore,
                    ONE_RESERVE_TOKEN
                )
            );

            // Mint the receipt token to the account
            vm.prank(recipient);
            // The expected revert has no receipt-token return value to inspect.
            /// forge-lint: disable-next-line(unused-return)
            cdFacility.deposit(iReserveToken, PERIOD_MONTHS, repaymentAmount, false);
        }
        assertEq(
            reserveToken.balanceOf(recipient),
            recipientReserveTokenBalanceBefore + repaymentAmount,
            "failed deposit should not consume repayment funds"
        );

        // Approve the redemption vault to spend the same repayment funds
        vm.prank(recipient);
        assertTrue(
            reserveToken.approve(address(redemptionVault), repaymentAmount),
            "repayment approval"
        );

        // Call function
        // Emit event (but ignore the principal and interest amounts)
        vm.expectEmit(true, true, true, false);
        emit LoanRepaid(recipient, 0, loan.principal, loan.interest);

        // Call function
        _repayLoan(recipient, 0, repaymentAmount, LOAN_PRINCIPAL_MAX_SLIPPAGE);

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
            _previousDepositActualAmount - SMALL_TEST_AMOUNT,
            SMALL_TEST_AMOUNT
        );

        // Assert borrowed amount on DepositManager
        assertEq(
            depositManager.getBorrowedAmount(iReserveToken, address(cdFacility)),
            0,
            "getBorrowedAmount"
        );

        // Assert committed funds
        assertApproxEqAbs(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            SMALL_TEST_AMOUNT,
            LOAN_PRINCIPAL_MAX_SLIPPAGE,
            "committed deposits"
        );
    }

    function test_givenCommitmentAmountFuzz_repayInFull(
        uint256 commitmentAmount_
    )
        public
        givenLocallyActive
        givenVaultHasDeposit(VAULT_DEPOSIT_AMOUNT)
        givenAddressHasConvertibleDepositToken(
            recipientTwo,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasConvertibleDepositTokenDefault(RESERVE_TOKEN_AMOUNT)
        givenVaultAccruesYield(iVault, 3e18) // Ensures that there are rounding inconsistencies when depositing/withdrawing from the vault
    {
        commitmentAmount_ = bound(commitmentAmount_, MIN_COMMITMENT_AMOUNT, MAX_COMMITMENT_AMOUNT);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        // Borrow
        vm.prank(recipient);
        assertGt(redemptionVault.borrowAgainstRedemption(0), 0, "borrowed amount");

        uint256 recipientReserveTokenBalanceBefore = reserveToken.balanceOf(recipient);

        // Determine the amount to pay back
        // This includes a buffer to ensure full repayment
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 repaymentAmount = loan.principal + loan.interest + LOAN_PRINCIPAL_MAX_SLIPPAGE;

        // Mint and approve
        reserveToken.mint(recipient, repaymentAmount);
        vm.prank(recipient);
        assertTrue(
            reserveToken.approve(address(redemptionVault), repaymentAmount),
            "repayment approval"
        );

        // Call function
        // Emit event (but ignore the principal and interest amounts)
        vm.expectEmit(true, true, true, false);
        emit LoanRepaid(recipient, 0, loan.principal, loan.interest);

        // Call function
        _repayLoan(recipient, 0, repaymentAmount, LOAN_PRINCIPAL_MAX_SLIPPAGE);

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
        assertApproxEqAbs(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            commitmentAmount_,
            LOAN_PRINCIPAL_MAX_SLIPPAGE,
            "committed deposits"
        );
    }

    function test_givenCommitmentAmountFuzz_givenYieldFuzz_repayInFull(
        uint256 depositAmount_,
        uint256 commitmentAmount_,
        uint256 yieldAmount_,
        uint256 yieldAmountTwo_
    ) public givenLocallyActive givenVaultHasDeposit(VAULT_DEPOSIT_AMOUNT) {
        depositAmount_ = bound(depositAmount_, ONE_RESERVE_TOKEN, MAX_FUZZ_AMOUNT);
        commitmentAmount_ = bound(commitmentAmount_, MIN_COMMITMENT_AMOUNT, depositAmount_ / 2);
        yieldAmount_ = bound(yieldAmount_, SMALL_TEST_AMOUNT, MAX_FUZZ_AMOUNT);
        yieldAmountTwo_ = bound(yieldAmountTwo_, SMALL_TEST_AMOUNT, MAX_FUZZ_AMOUNT);

        // Accrue yield
        _accrueYield(iVault, yieldAmount_);

        // Deposit
        _createDeposit(recipient, iReserveToken, PERIOD_MONTHS, depositAmount_);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        // Borrow
        vm.prank(recipient);
        assertGt(redemptionVault.borrowAgainstRedemption(0), 0, "borrowed amount");

        // Accrue more yield
        _accrueYield(iVault, yieldAmountTwo_);

        uint256 recipientReserveTokenBalanceBefore = reserveToken.balanceOf(recipient);

        // Determine the amount to pay back
        // This includes a buffer to ensure full repayment
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 repaymentAmount = loan.principal + loan.interest + LOAN_PRINCIPAL_MAX_SLIPPAGE;

        // Mint and approve
        reserveToken.mint(recipient, repaymentAmount);
        vm.prank(recipient);
        assertTrue(
            reserveToken.approve(address(redemptionVault), repaymentAmount),
            "repayment approval"
        );

        // Call function
        // Emit event (but ignore the principal and interest amounts)
        vm.expectEmit(true, true, true, false);
        emit LoanRepaid(recipient, 0, loan.principal, loan.interest);

        // Call function
        _repayLoan(recipient, 0, repaymentAmount, LOAN_PRINCIPAL_MAX_SLIPPAGE);

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
        assertApproxEqAbs(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            commitmentAmount_,
            LOAN_PRINCIPAL_MAX_SLIPPAGE,
            "committed deposits"
        );
    }

    function test_smallPayments()
        public
        givenLocallyActive
        givenVaultHasDeposit(VAULT_DEPOSIT_AMOUNT)
    {
        // Accrue yield
        _accrueYield(iVault, SMALL_TEST_AMOUNT);

        // Deposit
        _createDeposit(recipient, iReserveToken, PERIOD_MONTHS, ONE_RESERVE_TOKEN);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, SMALL_TEST_AMOUNT);

        // Borrow
        vm.prank(recipient);
        assertGt(redemptionVault.borrowAgainstRedemption(0), 0, "borrowed amount");

        // Determine the amount to pay back
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);

        // Mint and approve
        // Include a buffer to ensure full repayment
        uint256 repaymentAmount = loan.principal + loan.interest + ONE_RESERVE_TOKEN;
        reserveToken.mint(recipient, repaymentAmount);
        vm.prank(recipient);
        assertTrue(
            reserveToken.approve(address(redemptionVault), repaymentAmount),
            "repayment approval"
        );

        // Repay interest
        _repayLoan(recipient, 0, loan.interest);

        // Repay principal in small payments
        // Repeated small payments would exacerbate rounding errors and cause insolvency
        for (uint256 i = 0; i < SMALL_PAYMENT_COUNT; i++) {
            _repayLoan(
                recipient,
                0,
                loan.principal / SMALL_PAYMENT_COUNT + 1,
                SMALL_PAYMENT_MAX_SLIPPAGE
            );
        }

        // Assert that the loan is fully repaid
        assertEq(redemptionVault.getRedemptionLoan(recipient, 0).principal, 0);
        assertEq(redemptionVault.getRedemptionLoan(recipient, 0).interest, 0);
    }

    // given the vault has a different withdrawable amount than the provided amount
    //  when the maximum slippage is 0
    //   [X] it reverts
    //  when the maximum slippage is less than the difference
    //   [X] it reverts
    //  [X] it reduces the interest owed
    //  [X] it reduces the principal owed
    //  [X] it reduces the total principal borrowed
    //  [X] it transfers deposit tokens from the caller
    //  [X] it does not transfer any receipt tokens
    //  [X] it emits a LoanRepaid event

    function test_givenVaultHasDifferentWithdrawableAmount_whenRepayingInFull_whenMaxSlippageIsZero_reverts(
        uint256 depositAmount_,
        uint256 commitmentAmount_,
        uint256 yieldAmount_,
        uint256 yieldAmountTwo_
    ) public givenLocallyActive givenVaultHasDeposit(VAULT_DEPOSIT_AMOUNT) {
        depositAmount_ = bound(depositAmount_, ONE_RESERVE_TOKEN, MAX_FUZZ_AMOUNT);
        commitmentAmount_ = bound(commitmentAmount_, MIN_COMMITMENT_AMOUNT, depositAmount_ / 2);
        yieldAmount_ = bound(yieldAmount_, SMALL_TEST_AMOUNT, MAX_FUZZ_AMOUNT);
        yieldAmountTwo_ = bound(yieldAmountTwo_, SMALL_TEST_AMOUNT, MAX_FUZZ_AMOUNT);

        // Accrue yield
        _accrueYield(iVault, yieldAmount_);

        // Deposit
        _createDeposit(recipient, iReserveToken, PERIOD_MONTHS, depositAmount_);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        // Borrow
        vm.prank(recipient);
        assertGt(redemptionVault.borrowAgainstRedemption(0), 0, "borrowed amount");

        // Accrue more yield
        _accrueYield(iVault, yieldAmountTwo_);

        // Determine the amount to pay back
        // This includes a buffer to ensure full repayment
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 repaymentAmount = loan.principal + loan.interest + LOAN_PRINCIPAL_MAX_SLIPPAGE;

        // Mint and approve
        reserveToken.mint(recipient, repaymentAmount);
        vm.prank(recipient);
        assertTrue(
            reserveToken.approve(address(redemptionVault), repaymentAmount),
            "repayment approval"
        );

        // Expect revert
        _expectRevertMaxSlippageExceededPartial();

        // Call function
        _repayLoan(recipient, 0, repaymentAmount, 0);
    }

    function test_givenVaultHasDifferentWithdrawableAmount_whenRepayingInFull_whenSlippageIsGreaterThanMax_reverts(
        uint256 depositAmount_,
        uint256 commitmentAmount_,
        uint256 yieldAmount_,
        uint256 yieldAmountTwo_
    ) public givenLocallyActive givenVaultHasDeposit(VAULT_DEPOSIT_AMOUNT) {
        depositAmount_ = bound(depositAmount_, ONE_RESERVE_TOKEN, MAX_FUZZ_AMOUNT);
        commitmentAmount_ = bound(commitmentAmount_, MIN_COMMITMENT_AMOUNT, depositAmount_ / 2);
        yieldAmount_ = bound(yieldAmount_, SMALL_TEST_AMOUNT, MAX_FUZZ_AMOUNT);
        yieldAmountTwo_ = bound(yieldAmountTwo_, SMALL_TEST_AMOUNT, MAX_FUZZ_AMOUNT);

        // Accrue yield
        _accrueYield(iVault, yieldAmount_);

        // Deposit
        _createDeposit(recipient, iReserveToken, PERIOD_MONTHS, depositAmount_);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        // Borrow
        vm.prank(recipient);
        assertGt(redemptionVault.borrowAgainstRedemption(0), 0, "borrowed amount");

        // Accrue more yield
        _accrueYield(iVault, yieldAmountTwo_);

        // Determine the amount to pay back
        // This includes a buffer to ensure full repayment
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 repaymentAmount = loan.principal + loan.interest + LOAN_PRINCIPAL_MAX_SLIPPAGE;

        // Mint and approve
        reserveToken.mint(recipient, repaymentAmount);
        vm.prank(recipient);
        assertTrue(
            reserveToken.approve(address(redemptionVault), repaymentAmount),
            "repayment approval"
        );

        // Expect revert
        _expectRevertMaxSlippageExceededPartial();

        // Call function
        _repayLoan(recipient, 0, repaymentAmount, 1);
    }

    function test_givenVaultHasDifferentWithdrawableAmount_whenRepayingInFull_whenSlippageIsLessThanMax(
        uint256 depositAmount_,
        uint256 commitmentAmount_,
        uint256 yieldAmount_,
        uint256 yieldAmountTwo_,
        uint256 maxSlippage_
    ) public givenLocallyActive givenVaultHasDeposit(VAULT_DEPOSIT_AMOUNT) {
        depositAmount_ = bound(depositAmount_, ONE_RESERVE_TOKEN, MAX_FUZZ_AMOUNT);
        commitmentAmount_ = bound(commitmentAmount_, MIN_COMMITMENT_AMOUNT, depositAmount_ / 2);
        yieldAmount_ = bound(yieldAmount_, SMALL_TEST_AMOUNT, MAX_FUZZ_AMOUNT);
        yieldAmountTwo_ = bound(yieldAmountTwo_, SMALL_TEST_AMOUNT, MAX_FUZZ_AMOUNT);
        maxSlippage_ = bound(
            maxSlippage_,
            LOAN_PRINCIPAL_MAX_SLIPPAGE, // Ensures that if repaid amount != withdrawable amount, payment is completed
            ONE_RESERVE_TOKEN
        );

        // Accrue yield
        _accrueYield(iVault, yieldAmount_);

        // Deposit
        _createDeposit(recipient, iReserveToken, PERIOD_MONTHS, depositAmount_);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        // Borrow
        vm.prank(recipient);
        assertGt(redemptionVault.borrowAgainstRedemption(0), 0, "borrowed amount");

        // Accrue more yield
        _accrueYield(iVault, yieldAmountTwo_);

        uint256 recipientReserveTokenBalanceBefore = reserveToken.balanceOf(recipient);
        uint256 committedDepositsBefore = cdFacility.getCommittedDeposits(
            iReserveToken,
            address(redemptionVault)
        );
        // Determine the amount to pay back
        // This includes a buffer to ensure full repayment
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 repaymentAmount = loan.principal + loan.interest + maxSlippage_;

        // Mint and approve
        reserveToken.mint(recipient, repaymentAmount);
        vm.prank(recipient);
        assertTrue(
            reserveToken.approve(address(redemptionVault), repaymentAmount),
            "repayment approval"
        );

        // Call function
        // Emit event (but ignore the principal and interest amounts)
        vm.expectEmit(true, true, true, false);
        emit LoanRepaid(recipient, 0, loan.principal, loan.interest);

        // Call function
        _repayLoan(recipient, 0, repaymentAmount, maxSlippage_);

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
            committedDepositsBefore + loan.principal,
            "committed deposits"
        );
    }

    function test_givenVaultHasDifferentWithdrawableAmount_whenRepayingInFull_whenSlippageIsLessThanMax_givenSecondLoan(
        uint256 depositAmount_,
        uint256 commitmentAmount_,
        uint256 yieldAmount_,
        uint256 yieldAmountTwo_,
        uint256 maxSlippage_
    ) public givenLocallyActive givenVaultHasDeposit(VAULT_DEPOSIT_AMOUNT) {
        depositAmount_ = bound(depositAmount_, ONE_RESERVE_TOKEN, MAX_FUZZ_AMOUNT);
        commitmentAmount_ = bound(commitmentAmount_, MIN_COMMITMENT_AMOUNT, depositAmount_ / 2);
        yieldAmount_ = bound(yieldAmount_, SMALL_TEST_AMOUNT, MAX_FUZZ_AMOUNT);
        yieldAmountTwo_ = bound(yieldAmountTwo_, SMALL_TEST_AMOUNT, MAX_FUZZ_AMOUNT);
        maxSlippage_ = bound(
            maxSlippage_,
            LOAN_PRINCIPAL_MAX_SLIPPAGE, // Ensures that if repaid amount != withdrawable amount, payment is completed
            ONE_RESERVE_TOKEN
        );

        // Accrue yield
        _accrueYield(iVault, yieldAmount_);

        // Loan one
        {
            _createDeposit(recipient, iReserveToken, PERIOD_MONTHS, depositAmount_);

            _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

            vm.prank(recipient);
            assertGt(redemptionVault.borrowAgainstRedemption(0), 0, "borrowed amount");
        }

        // Loan two
        {
            _createDeposit(recipient, iReserveToken, PERIOD_MONTHS, depositAmount_);

            _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

            vm.prank(recipient);
            assertGt(redemptionVault.borrowAgainstRedemption(1), 0, "second borrowed amount");
        }

        // Accrue more yield
        _accrueYield(iVault, yieldAmountTwo_);

        uint256 recipientReserveTokenBalanceBefore = reserveToken.balanceOf(recipient);
        uint256 recipientReceiptTokenBalanceBefore = receiptTokenManager.balanceOf(
            recipient,
            receiptTokenId
        );
        uint256 committedDepositsBefore = cdFacility.getCommittedDeposits(
            iReserveToken,
            address(redemptionVault)
        );
        FacilityAssetSnapshot memory facilityBefore;
        (facilityBefore.shares, facilityBefore.assets) = depositManager.getOperatorAssets(
            iReserveToken,
            address(cdFacility)
        );

        // Get the details of the second loan for use later
        IDepositRedemptionVault.Loan memory loanTwo = redemptionVault.getRedemptionLoan(
            recipient,
            1
        );

        // Determine the amount to pay back for loan one
        // This includes a buffer to ensure full repayment
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        uint256 repaymentAmount = loan.principal + loan.interest + maxSlippage_;

        // Mint and approve
        reserveToken.mint(recipient, repaymentAmount);
        vm.prank(recipient);
        assertTrue(
            reserveToken.approve(address(redemptionVault), repaymentAmount),
            "repayment approval"
        );

        // Call function
        // Emit event (but ignore the principal and interest amounts)
        vm.expectEmit(true, true, true, false);
        emit LoanRepaid(recipient, 0, loan.principal, loan.interest);

        // Call function
        _repayLoan(recipient, 0, repaymentAmount, maxSlippage_);

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
            recipientReceiptTokenBalanceBefore, // No change
            commitmentAmount_ + commitmentAmount_ // Deposited for redemption
        );

        // Assert borrowed amount on DepositManager
        assertEq(
            depositManager.getBorrowedAmount(iReserveToken, address(cdFacility)),
            loanTwo.principal, // Repayment does not affect the second loan outstanding
            "getBorrowedAmount"
        );
        FacilityAssetSnapshot memory facilityAfter;
        (facilityAfter.shares, facilityAfter.assets) = depositManager.getOperatorAssets(
            iReserveToken,
            address(cdFacility)
        );
        assertGt(
            facilityAfter.shares,
            facilityBefore.shares,
            "facility custody shares should increase with repayment"
        );
        assertGt(
            facilityAfter.assets - facilityBefore.assets,
            loan.principal,
            "facility assets should include the accepted repayment buffer"
        );

        // Assert committed funds
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            committedDepositsBefore + loan.principal,
            "committed deposits"
        );
    }
}
