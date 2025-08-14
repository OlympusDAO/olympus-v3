// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";

contract DepositRedemptionVaultClaimDefaultedLoanTest is DepositRedemptionVaultTest {
    event RedemptionCancelled(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount,
        uint256 remainingAmount
    );

    event LoanDefaulted(
        address indexed user,
        uint16 indexed redemptionId,
        uint256 principal,
        uint256 interest,
        uint256 collateral
    );

    // ===== TESTS ===== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);
    }

    // given the redemption id is invalid
    //  [X] it reverts

    function test_givenRedemptionIdIsInvalid_reverts(
        uint16 redemptionId_
    ) public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidRedemptionId(recipient, redemptionId_);

        // Call function
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, redemptionId_);
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
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);
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
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);
    }

    // given the loan has not expired
    //  [X] it reverts

    function test_givenLoanHasNotExpired_reverts(
        uint48 elapsed_
    ) public givenLocallyActive givenCommittedDefault(COMMITMENT_AMOUNT) givenLoanDefault {
        elapsed_ = uint48(bound(elapsed_, 0, PERIOD_MONTHS * 30 days - 1));
        vm.warp(block.timestamp + elapsed_);

        // Expect revert
        _expectRevertLoanIncorrectState(recipient, 0);

        // Call function
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);
    }

    // given the loan has already defaulted
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
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);
    }

    // given the loan is fully repaid
    //  [X] it reverts

    function test_givenLoanIsFullyRepaid_reverts()
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
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);
    }

    // given the loan principal has been partially repaid
    //  [X] it marks the loan as defaulted
    //  [X] it sets the loan principal to 0
    //  [X] it sets the loan interest to 0
    //  [X] it reduces the amount borrowed from the facility by the remaining principal
    //  [X] it reduces the committed amount from the facility by the remaining principal
    //  [X] it reduces the redemption amount by the remaining principal
    //  [X] it does not transfer any deposit tokens to the caller
    //  [X] it transfers the unpaid principal of the deposit tokens to the TRSRY
    //  [X] it emits a LoanDefaulted event
    //  [X] it emits a RedemptionCancelled event

    function test_givenLoanPrincipalHasBeenPartiallyRepaid(
        uint256 principalAmount_
    )
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenRecipientHasReserveToken
        givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient
    {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);
        principalAmount_ = uint256(bound(principalAmount_, 1, loan.principal - 1));
        _repayLoan(recipient, 0, loan.interest + principalAmount_);

        // Expire the loan
        vm.warp(loan.dueDate);

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit LoanDefaulted(
            recipient,
            0,
            loan.principal - principalAmount_,
            0,
            COMMITMENT_AMOUNT - principalAmount_
        );
        vm.expectEmit(true, true, true, true);
        emit RedemptionCancelled(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT - principalAmount_,
            principalAmount_
        );

        // Call function
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, 0, 0, true, loan.dueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            loan.principal + RESERVE_TOKEN_AMOUNT - loan.interest - principalAmount_, // No change since repayment
            loan.interest + COMMITMENT_AMOUNT - loan.principal, // Receives remaining collateral that was not lent out
            0
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(
            recipient,
            0,
            principalAmount_ // redemption vault still custodies the repaid amount
        );

        // Assert the redemption amount
        assertEq(
            redemptionVault.getUserRedemption(recipient, 0).amount,
            principalAmount_,
            "redemption amount mismatch"
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
            principalAmount_,
            "committed deposits"
        );
    }

    // given there is no retained collateral
    //  [X] it marks the loan as defaulted
    //  [X] it sets the loan principal to 0
    //  [X] it sets the loan interest to 0
    //  [X] it reduces the amount borrowed from the facility by the principal
    //  [X] it reduces the committed amount from the facility by the principal
    //  [X] it reduces the redemption amount by the principal
    //  [X] it does not transfer any deposit tokens to the caller
    //  [X] it does not transfer any deposit tokens to the TRSRY
    //  [X] it emits a LoanDefaulted event
    //  [X] it emits a RedemptionCancelled event

    function test_givenClaimDefaultRewardPercentageIsNonZero_givenNoRetainedCollateral()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenMaxBorrowPercentage(iReserveToken, 100e2) // 100%
        givenLoanDefault
        givenLoanExpired(recipient, 0)
        givenClaimDefaultRewardPercentage(100) // 1%
    {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit LoanDefaulted(recipient, 0, loan.principal, loan.interest, COMMITMENT_AMOUNT);
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
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, COMMITMENT_AMOUNT, 0, 0, true, loan.dueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            loan.principal, // No change
            0, // Nothing retained as it was all lent out
            0 // No keeper reward as it was all lent out
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, 0);

        // Assert the redemption amount
        assertEq(
            redemptionVault.getUserRedemption(recipient, 0).amount,
            0,
            "redemption amount mismatch"
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
            0,
            "committed deposits"
        );
    }

    // given the keeper reward percentage is 0
    //  [X] it marks the loan as defaulted
    //  [X] it sets the loan principal to 0
    //  [X] it sets the loan interest to 0
    //  [X] it reduces the amount borrowed from the facility by the principal
    //  [X] it reduces the committed amount from the facility by the principal
    //  [X] it reduces the redemption amount by the principal
    //  [X] it does not transfer any deposit tokens to the caller
    //  [X] it transfers all of the deposit tokens to the TRSRY
    //  [X] it emits a LoanDefaulted event
    //  [X] it emits a RedemptionCancelled event

    function test_givenClaimDefaultRewardPercentageIsZero()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenLoanExpired(recipient, 0)
    {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit LoanDefaulted(recipient, 0, loan.principal, loan.interest, COMMITMENT_AMOUNT);
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
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, 0, 0, true, loan.dueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            loan.principal, // No change
            COMMITMENT_AMOUNT - loan.principal, // Receives collateral that was not lent out
            0
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, 0);

        // Assert the redemption amount
        assertEq(
            redemptionVault.getUserRedemption(recipient, 0).amount,
            0,
            "redemption amount mismatch"
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
            0,
            "committed deposits"
        );
    }

    // [X] it marks the loan as defaulted
    // [X] it sets the loan principal to 0
    // [X] it sets the loan interest to 0
    // [X] it reduces the amount borrowed from the facility by the principal
    // [X] it reduces the committed amount from the facility by the principal
    // [X] it reduces the redemption amount by the principal
    // [X] it transfers the percentage of the principal as keeper reward to the caller
    // [X] it transfers the remainder of the principal to the TRSRY
    // [X] it emits a LoanDefaulted event
    // [X] it emits a RedemptionCancelled event

    function test_givenClaimDefaultRewardPercentageIsNonZero()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenLoanExpired(recipient, 0)
        givenClaimDefaultRewardPercentage(100) // 1%
    {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(recipient, 0);

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit LoanDefaulted(recipient, 0, loan.principal, loan.interest, COMMITMENT_AMOUNT);
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
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, 0, 0, true, loan.dueDate);

        // Assert deposit token balances
        uint256 remainingCollateral = COMMITMENT_AMOUNT - loan.principal;
        uint256 keeperReward = (remainingCollateral * 100) / 100e2;
        _assertDepositTokenBalances(
            recipient,
            loan.principal, // No change
            remainingCollateral - keeperReward, // Remaining collateral that was not lent out, minus keeper reward
            keeperReward // Keeper reward
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, 0);

        // Assert the redemption amount
        assertEq(
            redemptionVault.getUserRedemption(recipient, 0).amount,
            0,
            "redemption amount mismatch"
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
            0,
            "committed deposits"
        );
    }

    function test_givenCommitmentAmountFuzz(
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
        givenClaimDefaultRewardPercentage(100) // 1%
    {
        commitmentAmount_ = bound(commitmentAmount_, 1e17, 5e18);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        // Borrow
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);

        // Determine the amount to pay back
        IDepositRedemptionVault.Loan memory loanBefore = redemptionVault.getRedemptionLoan(
            recipient,
            0
        );
        uint256 expectedCollateral = commitmentAmount_ - loanBefore.principal;
        uint256 expectedKeeperReward = (expectedCollateral * 100) / 100e2;

        // Expire the loan
        vm.warp(block.timestamp + PERIOD_MONTHS * 30 days);

        // Call function
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);

        // Assert that the loan is cleared
        _assertLoan(recipient, 0, loanBefore.principal, 0, 0, true, loanBefore.dueDate);

        // Assert deposit token balances
        assertEq(
            reserveToken.balanceOf(recipient),
            loanBefore.principal, // No change
            "deposit token: user balance mismatch"
        );
        assertApproxEqAbs(
            reserveToken.balanceOf(address(treasury)),
            expectedCollateral - expectedKeeperReward,
            5, // Actual amount can be unpredictable
            "deposit token: treasury balance mismatch"
        ); // Remaining collateral that was not lent out, minus keeper reward
        assertApproxEqAbs(
            reserveToken.balanceOf(address(defaultRewardClaimer)),
            expectedKeeperReward, // Keeper reward
            1, // Affected by the collateral returned
            "deposit token: claimer balance mismatch"
        );
        assertEq(
            reserveToken.balanceOf(address(redemptionVault)),
            0,
            "deposit token: redemption vault balance mismatch"
        );
        assertEq(
            reserveToken.balanceOf(address(cdFacility)),
            0,
            "deposit token: cd facility balance mismatch"
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, _previousDepositActualAmount - commitmentAmount_, 0);

        // Assert the redemption amount
        assertEq(
            redemptionVault.getUserRedemption(recipient, 0).amount,
            0,
            "redemption amount mismatch"
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
            0,
            "committed deposits"
        );
    }

    function test_givenCommitmentAmountFuzz(
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
        givenClaimDefaultRewardPercentage(100) // 1%
    {
        commitmentAmount_ = bound(commitmentAmount_, 1e17, 5e18);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        // Borrow
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);

        // Determine the amount to pay back
        IDepositRedemptionVault.Loan memory loanBefore = redemptionVault.getRedemptionLoan(
            recipient,
            0
        );
        uint256 expectedCollateral = commitmentAmount_ - loanBefore.principal;
        uint256 expectedKeeperReward = (expectedCollateral * 100) / 100e2;

        // Expire the loan
        vm.warp(block.timestamp + PERIOD_MONTHS * 30 days);

        // Call function
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(recipient, 0);

        // Assert that the loan is cleared
        _assertLoan(recipient, 0, 0, 0, true, loanBefore.dueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            loanBefore.principal, // No change
            expectedCollateral - expectedKeeperReward, // Remaining collateral that was not lent out, minus keeper reward
            expectedKeeperReward // Keeper reward
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, _previousDepositActualAmount, 0);

        // Assert the redemption amount
        assertEq(
            redemptionVault.getUserRedemption(recipient, 0).amount,
            0,
            "redemption amount mismatch"
        );

        // Assert borrowed amount on DepositManager
        assertEq(
            depositManager.getBorrowedAmount(iReserveToken, address(cdFacility)),
            0,
            "getBorrowedAmount"
        );
    }
}
