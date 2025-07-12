// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";

contract DepositRedemptionVaultClaimDefaultedLoanTest is DepositRedemptionVaultTest {
    event RedemptionCancelled(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    event LoanDefaulted(
        address indexed user,
        uint16 indexed redemptionId,
        uint16 indexed loanId,
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
        vm.prank(recipientTwo);
        redemptionVault.claimDefaultedLoan(recipient, 0, 0);
    }

    // given the redemption id is invalid
    //  [X] it reverts

    function test_givenRedemptionIdIsInvalid_reverts(
        uint256 redemptionId_
    ) public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidRedemptionId(redemptionId_);

        // Call function
        vm.prank(recipientTwo);
        redemptionVault.claimDefaultedLoan(recipient, redemptionId_, 0);
    }

    // given the loan id is invalid
    //  [X] it reverts

    function test_givenLoanIdIsInvalid_reverts(
        uint256 loanId_
    ) public givenLocallyActive givenCommittedDefault(COMMITMENT_AMOUNT) {
        // Expect revert
        _expectRevertInvalidLoanId(loanId_);

        // Call function
        vm.prank(recipientTwo);
        redemptionVault.claimDefaultedLoan(recipient, 0, loanId_);
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
        vm.prank(recipientTwo);
        redemptionVault.claimDefaultedLoan(recipient, 0, 0);
    }

    // given the loan has not expired
    //  [X] it reverts

    function test_givenLoanHasNotExpired_reverts(
        uint48 elapsed_
    ) public givenLocallyActive givenCommittedDefault(COMMITMENT_AMOUNT) givenLoanDefault {
        elapsed_ = uint48(bound(elapsed_, 0, PERIOD_MONTHS * 30 days - 1));
        vm.warp(block.timestamp + elapsed_);

        // Expect revert
        _expectRevertLoanIncorrectState(recipient, 0, 0);

        // Call function
        vm.prank(recipientTwo);
        redemptionVault.claimDefaultedLoan(recipient, 0, 0);
    }

    // given the loan has defaulted
    //  [X] it reverts

    function test_givenLoanIsDefaulted_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenLoanExpired(recipient, 0, 0)
        givenLoanClaimedDefault(recipient, 0, 0)
    {
        // Expect revert
        _expectRevertLoanIncorrectState(recipient, 0, 0);

        // Call function
        vm.prank(recipientTwo);
        redemptionVault.claimDefaultedLoan(recipient, 0, 0);
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
        IDepositRedemptionVault.Loan[] memory loans = redemptionVault.getRedemptionLoans(
            recipient,
            0
        );
        uint256 amountToRepay = loans[0].principal + loans[0].interest;
        _repayLoan(recipient, 0, 0, amountToRepay);

        // Expect revert
        _expectRevertLoanIncorrectState(recipient, 0, 0);

        // Call function
        vm.prank(recipientTwo);
        redemptionVault.claimDefaultedLoan(recipient, 0, 0);
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
        givenLoanExpired(recipient, 0, 0)
        givenRecipientHasReserveToken
        givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient
    {
        IDepositRedemptionVault.Loan[] memory loans = redemptionVault.getRedemptionLoans(
            recipient,
            0
        );
        principalAmount_ = uint256(bound(principalAmount_, 1, loans[0].principal - 1));
        _repayLoan(recipient, 0, 0, loans[0].interest + principalAmount_);

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit LoanDefaulted(
            recipient,
            0,
            0,
            loans[0].principal - principalAmount_,
            0,
            COMMITMENT_AMOUNT
        );
        vm.expectEmit(true, true, true, true);
        emit RedemptionCancelled(
            recipient,
            0,
            address(RESERVE_TOKEN),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipientTwo);
        redemptionVault.claimDefaultedLoan(recipient, 0, 0);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, 0, 0, 0, true, loans[0].dueDate);

        // Assert total borrowed
        _assertTotalBorrowed(recipient, 0, 0);

        // Assert available to borrow
        _assertAvailableBorrow(recipient, 0, LOAN_AMOUNT);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            loans[0].principal + RESERVE_TOKEN_AMOUNT - loans[0].interest - principalAmount_, // No change since repayment
            loans[0].interest + COMMITMENT_AMOUNT - loans[0].principal, // Receives remaining collateral that was not lent out
            0
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, 0);
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
        givenLoanExpired(recipient, 0, 0)
    {
        IDepositRedemptionVault.Loan[] memory loans = redemptionVault.getRedemptionLoans(
            recipient,
            0
        );

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit LoanDefaulted(
            recipient,
            0,
            0,
            loans[0].principal,
            loans[0].interest,
            COMMITMENT_AMOUNT
        );
        vm.expectEmit(true, true, true, true);
        emit RedemptionCancelled(
            recipient,
            0,
            address(RESERVE_TOKEN),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipientTwo);
        redemptionVault.claimDefaultedLoan(recipient, 0, 0);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, 0, 0, 0, true, loans[0].dueDate);

        // Assert total borrowed
        _assertTotalBorrowed(recipient, 0, 0);

        // Assert available to borrow
        _assertAvailableBorrow(recipient, 0, LOAN_AMOUNT);

        // Assert deposit token balances
        _assertDepositTokenBalances(
            recipient,
            loans[0].principal, // No change
            COMMITMENT_AMOUNT - loans[0].principal, // Receives collateral that was not lent out
            0
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, 0);
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
        givenLoanExpired(recipient, 0, 0)
        givenClaimDefaultRewardPercentageIsNonZero(100) // 1%
    {
        IDepositRedemptionVault.Loan[] memory loans = redemptionVault.getRedemptionLoans(
            recipient,
            0
        );

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit LoanDefaulted(
            recipient,
            0,
            0,
            loans[0].principal,
            loans[0].interest,
            COMMITMENT_AMOUNT
        );
        vm.expectEmit(true, true, true, true);
        emit RedemptionCancelled(
            recipient,
            0,
            address(RESERVE_TOKEN),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipientTwo);
        redemptionVault.claimDefaultedLoan(recipient, 0, 0);

        // Assertions
        // Assert loan
        _assertLoan(recipient, 0, 0, 0, 0, true, loans[0].dueDate);

        // Assert total borrowed
        _assertTotalBorrowed(recipient, 0, 0);

        // Assert available to borrow
        _assertAvailableBorrow(recipient, 0, LOAN_AMOUNT);

        // Assert deposit token balances
        uint256 remainingCollateral = COMMITMENT_AMOUNT - loans[0].principal;
        uint256 keeperReward = (remainingCollateral * 100) / 100e2;
        _assertDepositTokenBalances(
            recipient,
            loans[0].principal, // No change
            remainingCollateral - keeperReward, // Remaining collateral that was not lent out, minus keeper reward
            keeperReward // Keeper reward
        );

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, 0);
    }
}
