// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

contract DepositRedemptionVaultCancelRedemptionTest is DepositRedemptionVaultTest {
    event RedemptionCancelled(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount,
        uint256 remainingAmount
    );

    function _assertRedemptionCancelled(
        address user_,
        uint16 redemptionId_,
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 depositTokenBalanceBefore_,
        uint256 amount_,
        uint256 previousUserCommitmentAmount_
    ) internal view {
        // Get redemption
        IDepositRedemptionVault.UserRedemption memory redemption = redemptionVault
            .getUserRedemption(user_, redemptionId_);

        // Assert redemption values
        assertEq(redemption.depositToken, address(depositToken_), "depositToken mismatch");
        assertEq(redemption.depositPeriod, depositPeriod_, "depositPeriod mismatch");
        assertEq(redemption.amount, previousUserCommitmentAmount_ - amount_, "Amount mismatch");

        // Assert receipt token balances
        uint256 receiptTokenId = depositManager.getReceiptTokenId(depositToken_, depositPeriod_);
        assertEq(
            depositManager.balanceOf(user_, receiptTokenId),
            depositTokenBalanceBefore_ + amount_,
            "user: receipt token balance mismatch"
        );
        assertEq(
            depositManager.balanceOf(address(redemptionVault), receiptTokenId),
            previousUserCommitmentAmount_ - amount_,
            "redemptionVault: receipt token balance mismatch"
        );
    }

    // given the contract is disabled
    //  [X] it reverts

    function test_contractDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, COMMITMENT_AMOUNT);
    }

    // given the redemption ID does not exist
    //  [X] it reverts

    function test_invalidCommitmentId_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Expect revert
        _expectRevertInvalidRedemptionId(recipient, 1);

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(1, COMMITMENT_AMOUNT);
    }

    // given the redemption ID exists for a different user
    //  [X] it reverts

    function test_redemptionIdExistsForDifferentUser_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Expect revert
        _expectRevertInvalidRedemptionId(recipientTwo, 0);

        // Call function
        vm.prank(recipientTwo);
        redemptionVault.cancelRedemption(0, COMMITMENT_AMOUNT);
    }

    // given the facility is deauthorized
    //  [X] it reverts

    function test_deauthorizedFacility_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenFacilityIsDeauthorized(address(cdFacility))
    {
        // Expect revert
        _expectRevertFacilityNotRegistered(cdFacilityAddress);

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, COMMITMENT_AMOUNT);
    }

    // given the amount to cancel is 0
    //  [X] it reverts

    function test_amountIsZero_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, 0);
    }

    // given the amount to cancel is more than the redemption
    //  [X] it reverts

    function test_amountGreaterThanCommitment_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Bound the amount to be greater than the redemption
        amount_ = bound(amount_, COMMITMENT_AMOUNT + 1, type(uint256).max);

        // Expect revert
        _expectRevertInvalidAmount(recipient, 0, amount_);

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, amount_);
    }

    // given there has been a partial cancellation
    //  [X] it reduces the redemption amount

    function test_success_partialCancellation(
        uint256 firstAmount_,
        uint256 secondAmount_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        firstAmount_ = bound(firstAmount_, 1, COMMITMENT_AMOUNT - 1);
        secondAmount_ = bound(secondAmount_, 1, COMMITMENT_AMOUNT - firstAmount_);

        // Cancel first amount
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, firstAmount_);

        // Cancel second amount
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, secondAmount_);

        // Get redemption
        IDepositRedemptionVault.UserRedemption memory redemption = redemptionVault
            .getUserRedemption(recipient, 0);

        // Assert redemption amount
        assertEq(
            redemption.amount,
            COMMITMENT_AMOUNT - firstAmount_ - secondAmount_,
            "redemption amount mismatch"
        );

        // Assert receipt token balances
        uint256 receiptTokenId = depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS);
        assertEq(
            depositManager.balanceOf(recipient, receiptTokenId),
            firstAmount_ + secondAmount_,
            "user: receipt token balance mismatch"
        );
        assertEq(
            depositManager.balanceOf(address(redemptionVault), receiptTokenId),
            COMMITMENT_AMOUNT - firstAmount_ - secondAmount_,
            "redemptionVault: receipt token balance mismatch"
        );
    }

    // given there has been a full cancellation
    //  [X] it removes the redemption

    function test_success_fullCancellation()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionCancelled(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            0
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, COMMITMENT_AMOUNT);

        // Get redemption
        IDepositRedemptionVault.UserRedemption memory redemption = redemptionVault
            .getUserRedemption(recipient, 0);

        // Assert redemption amount is 0
        assertEq(redemption.amount, 0, "redemption amount should be 0");

        // Assert receipt token balances
        uint256 receiptTokenId = depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS);
        assertEq(
            depositManager.balanceOf(recipient, receiptTokenId),
            COMMITMENT_AMOUNT,
            "user: receipt token balance mismatch"
        );
        assertEq(
            depositManager.balanceOf(address(redemptionVault), receiptTokenId),
            0,
            "redemptionVault: receipt token balance should be 0"
        );

        // Assert committed deposits are 0
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            0,
            "committed deposits should be 0"
        );
    }

    // given there is an open loan position
    //  [X] it reverts

    function test_givenLoanPosition_unpaid_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
    {
        // Expect revert
        _expectRevertRedemptionVaultUnpaidLoan(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, COMMITMENT_AMOUNT);
    }

    // given there is a partially-paid loan position
    //  [X] it reverts

    function test_givenLoanPosition_partiallyPaid_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient
    {
        amount_ = bound(amount_, 1, LOAN_AMOUNT - 1);

        // Repay the loan
        vm.prank(recipient);
        redemptionVault.repayLoan(0, amount_);

        // Expect revert
        _expectRevertRedemptionVaultUnpaidLoan(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, amount_);
    }

    // given there is a fully-paid loan position
    //  [X] it transfers the receipt tokens from the contract to the caller
    //  [X] it reduces the redemption amount
    //  [X] it emits a RedemptionCancelled event

    function test_givenLoanPosition_paid(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient
    {
        // Repay the full amount of the loan
        {
            IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(
                recipient,
                0
            );
            uint256 loanPayable = loan.principal + loan.interest;

            // Mint the required amount of the reserve token
            MockERC20(address(iReserveToken)).mint(recipient, loan.interest);

            // Approve the redemption vault to spend the reserve token
            iReserveToken.approve(address(redemptionVault), loanPayable);

            vm.prank(recipient);
            redemptionVault.repayLoan(0, loanPayable);
        }

        // Bound the amount to cancel
        amount_ = bound(amount_, 1, COMMITMENT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionCancelled(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            amount_,
            COMMITMENT_AMOUNT - amount_
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, amount_);

        // Assertions
        _assertRedemptionCancelled(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            0,
            amount_,
            COMMITMENT_AMOUNT
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(amount_);
    }

    // given there is a loan position that has been defaulted
    //  given there is no retained redemption amount
    //   [X] it reverts

    function test_givenLoanPosition_givenDefaultedWithoutRetainedRedemption_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenLoanExpired(recipient, 0)
        givenLoanClaimedDefault(recipient, 0)
    {
        amount_ = bound(amount_, 1, LOAN_AMOUNT);

        // Expect revert
        _expectRevertInvalidAmount(recipient, 0, amount_);

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, amount_);
    }

    //  [X] it transfers the receipt tokens from the contract to the caller
    //  [X] it reduces the redemption amount
    //  [X] it emits a RedemptionCancelled event

    function test_givenLoanPosition_givenDefaultedWithRetainedRedemption(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient
        givenLoanRepaid(recipient, 0, LOAN_AMOUNT / 2)
        givenLoanExpired(recipient, 0)
        givenLoanClaimedDefault(recipient, 0)
    {
        // Get the remaining redemption amount
        uint256 remainingRedemptionAmount = redemptionVault.getUserRedemption(recipient, 0).amount;
        amount_ = bound(amount_, 1, remainingRedemptionAmount);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionCancelled(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            amount_,
            remainingRedemptionAmount - amount_
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, amount_);

        // Assertions
        _assertRedemptionCancelled(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            0,
            amount_,
            remainingRedemptionAmount
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(amount_);
    }

    // [X] it transfers the receipt tokens from the contract to the caller
    // [X] it reduces the redemption amount
    // [X] it emits a RedemptionCancelled event

    function test_success(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        amount_ = bound(amount_, 1, COMMITMENT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionCancelled(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            amount_,
            COMMITMENT_AMOUNT - amount_
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, amount_);

        // Assertions
        _assertRedemptionCancelled(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            0,
            amount_,
            COMMITMENT_AMOUNT
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(amount_);

        // Assert committed deposits
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            COMMITMENT_AMOUNT - amount_,
            "committed deposits"
        );
    }

    function test_givenOtherDeposits(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositTokenDefault(COMMITMENT_AMOUNT)
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        amount_ = bound(amount_, 1, COMMITMENT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionCancelled(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            amount_,
            COMMITMENT_AMOUNT - amount_
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, amount_);

        // Assertions
        _assertRedemptionCancelled(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            _previousDepositActualAmount,
            amount_,
            COMMITMENT_AMOUNT
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(_previousDepositActualAmount + amount_);
    }
}
