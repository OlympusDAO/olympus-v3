// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract DepositRedemptionVaultFinishRedemptionTest is DepositRedemptionVaultTest {
    event RedemptionFinished(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    function _assertRedeemed(
        address user_,
        uint16 redemptionId_,
        IERC20 depositToken_,
        uint8 depositPeriod_,
        address facility_,
        uint256 amount_,
        uint256 otherUserCommitmentAmount_,
        uint256 alreadyRedeemedAmount_,
        uint256 cancelledAmount_
    ) internal view {
        // Get redemption
        IDepositRedemptionVault.UserRedemption memory redemption = redemptionVault
            .getUserRedemption(user_, redemptionId_);

        // Assert redemption values
        assertEq(redemption.depositToken, address(depositToken_), "depositToken mismatch");
        assertEq(redemption.depositPeriod, depositPeriod_, "depositPeriod mismatch");
        assertEq(redemption.amount, 0, "amount should be 0 after redemption");

        // Assert receipt token balances
        uint256 receiptTokenId = depositManager.getReceiptTokenId(
            depositToken_,
            depositPeriod_,
            facility_
        );
        assertEq(
            receiptTokenManager.balanceOf(user_, receiptTokenId),
            cancelledAmount_,
            "user: receipt token balance mismatch"
        );
        assertEq(
            receiptTokenManager.balanceOf(address(redemptionVault), receiptTokenId),
            otherUserCommitmentAmount_,
            "redemptionVault: receipt token balance mismatch"
        );

        // Assert deposit token balances
        assertApproxEqAbs(
            depositToken_.balanceOf(user_),
            alreadyRedeemedAmount_ + amount_,
            3,
            "user: deposit token balance mismatch"
        );
        assertEq(
            depositToken_.balanceOf(address(redemptionVault)),
            0,
            "redemptionVault: deposit token balance should be 0"
        );
    }

    modifier givenCommitmentPeriodElapsed(uint16 redemptionId_) {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = redemptionVault
            .getUserRedemption(recipient, redemptionId_)
            .redeemableAt;
        vm.warp(redeemableAt);
        _;
    }

    // given the contract is disabled
    //  [X] it reverts

    function test_contractDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);
    }

    // given the redemption ID does not exist
    //  [X] it reverts

    function test_redemptionIdDoesNotExist_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidRedemptionId(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);
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
        redemptionVault.finishRedemption(0);
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
        redemptionVault.finishRedemption(0);
    }

    // given it is before the redeemable timestamp
    //  [X] it reverts

    function test_beforeRedeemableTimestamp_reverts(
        uint48 timestamp_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Get the redeemable timestamp
        IDepositRedemptionVault.UserRedemption memory redemption = redemptionVault
            .getUserRedemption(recipient, 0);
        uint48 redeemableAt = redemption.redeemableAt;

        // Bound the timestamp to be before the redeemable timestamp
        timestamp_ = uint48(bound(timestamp_, 0, redeemableAt - 1));
        vm.warp(timestamp_);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_TooEarly.selector,
                recipient,
                0,
                redeemableAt
            )
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);
    }

    // given the redemption has already been redeemed
    //  [X] it reverts

    function test_alreadyRedeemed_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenCommitmentPeriodElapsed(0)
        givenRedeemed(recipient, 0)
    {
        // Expect revert
        _expectRevertAlreadyRedeemed(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);
    }

    // given there is an existing redemption for the caller
    //  [X] it does not affect the other redemption

    function test_existingCommitment_sameUser(
        uint8 index_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenCommitmentPeriodElapsed(0)
    {
        // Redeem the chosen redemption
        index_ = uint8(bound(index_, 0, 1));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionFinished(
            recipient,
            index_,
            address(iReserveToken),
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(index_);

        // Assertions
        _assertRedeemed(
            recipient,
            index_,
            iReserveToken,
            PERIOD_MONTHS,
            cdFacilityAddress,
            _previousDepositActualAmount,
            _previousDepositActualAmount,
            0,
            0
        );

        // The other redemption should not be affected
        uint16 otherCommitmentId = index_ == 0 ? 1 : 0;
        IDepositRedemptionVault.UserRedemption memory otherCommitment = redemptionVault
            .getUserRedemption(recipient, otherCommitmentId);
        assertEq(
            otherCommitment.amount,
            _previousDepositActualAmount,
            "Other redemption amount mismatch"
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    // given there is an existing redemption for a different user
    //  [X] it does not affect the other redemption

    function test_existingCommitment_differentUser()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenCommitted(recipientTwo, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenCommitmentPeriodElapsed(0)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionFinished(
            recipientTwo,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Call function
        vm.prank(recipientTwo);
        redemptionVault.finishRedemption(0);

        // Assertions
        _assertRedeemed(
            recipientTwo,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            cdFacilityAddress,
            _previousDepositActualAmount,
            _previousDepositActualAmount,
            0,
            0
        );

        // The other redemption should not be affected
        IDepositRedemptionVault.UserRedemption memory otherCommitment = redemptionVault
            .getUserRedemption(recipient, 0);
        assertEq(
            otherCommitment.amount,
            _previousDepositActualAmount,
            "Other redemption amount mismatch"
        );
        assertEq(reserveToken.balanceOf(recipient), 0, "User: reserve token balance mismatch");

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    // given there is an open loan position
    //  [X] it reverts

    function test_givenLoanPosition_unpaid_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenCommitmentPeriodElapsed(0)
    {
        // Expect revert
        _expectRevertRedemptionVaultUnpaidLoan(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);
    }

    // given there is a partially-paid loan position
    //  [X] it reverts

    function test_givenLoanPosition_partiallyPaid_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient
    {
        // Repay the loan
        vm.prank(recipient);
        redemptionVault.repayLoan(0, LOAN_AMOUNT / 2);

        // Warp to after redeemable timestamp
        uint48 redeemableAt = redemptionVault.getUserRedemption(recipient, 0).redeemableAt;
        vm.warp(redeemableAt);

        // Expect revert
        _expectRevertRedemptionVaultUnpaidLoan(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);
    }

    // given there is a fully-paid loan position
    //  [X] it transfers the deposit tokens from the facility to the caller
    //  [X] it burns the receipt tokens
    //  [X] it removes the redemption from the user's redemptions
    //  [X] it emits a RedemptionFinished event
    //  [X] it returns the amount of deposit tokens transferred

    function test_givenLoanPosition_paid()
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

        // Warp to after redeemable timestamp
        uint48 redeemableAt = redemptionVault.getUserRedemption(recipient, 0).redeemableAt;
        vm.warp(redeemableAt);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionFinished(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);

        // Assertions
        _assertRedeemed(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            cdFacilityAddress,
            COMMITMENT_AMOUNT,
            0,
            0,
            0
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    // given there is a loan position that has been defaulted
    //  given there is no retained redemption amount
    //   [X] it reverts

    function test_givenLoanPosition_givenDefaultedWithoutRetainedRedemption_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenLoanExpired(recipient, 0)
        givenLoanClaimedDefault(recipient, 0)
        givenCommitmentPeriodElapsed(0)
    {
        // Expect revert
        _expectRevertAlreadyRedeemed(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);
    }

    //  [X] it uses the reduced redemption amount
    //  [X] it transfers the deposit tokens from the facility to the caller
    //  [X] it burns the receipt tokens
    //  [X] it removes the redemption from the user's redemptions
    //  [X] it emits a RedemptionFinished event
    //  [X] it returns the amount of deposit tokens transferred

    function test_givenLoanPosition_givenDefaultedWithRetainedRedemption()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoanDefault
        givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient
        givenLoanRepaid(recipient, 0, LOAN_AMOUNT / 2)
        givenLoanExpired(recipient, 0)
        givenLoanClaimedDefault(recipient, 0)
        givenCommitmentPeriodElapsed(0)
    {
        // Get the remaining redemption amount
        uint256 remainingRedemptionAmount = redemptionVault.getUserRedemption(recipient, 0).amount;

        uint256 depositTokenBalanceBefore = iReserveToken.balanceOf(recipient);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionFinished(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            remainingRedemptionAmount
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);

        // Assertions
        _assertRedeemed(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            cdFacilityAddress,
            remainingRedemptionAmount,
            0,
            depositTokenBalanceBefore,
            0
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    // given there has been an amount of receipt tokens cancelled
    //  [X] the updated redemption amount is used

    function test_cancelled(
        uint256 cancelledAmount_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        cancelledAmount_ = bound(cancelledAmount_, 1, COMMITMENT_AMOUNT - 1);

        // Cancel some of the redemption
        vm.prank(recipient);
        redemptionVault.cancelRedemption(0, cancelledAmount_);

        // Warp to after redeemable timestamp
        uint48 redeemableAt = redemptionVault.getUserRedemption(recipient, 0).redeemableAt;
        vm.warp(redeemableAt);

        uint256 remainingAmount = COMMITMENT_AMOUNT - cancelledAmount_;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionFinished(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            remainingAmount
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);

        // Assertions
        _assertRedeemed(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            cdFacilityAddress,
            remainingAmount,
            0,
            0,
            cancelledAmount_
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(cancelledAmount_);
    }

    // given yield has been claimed
    //  [X] it burns the receipt tokens
    //  [X] it transfers the underlying asset to the caller
    //  [X] it sets the redemption amount to 0
    //  [X] it emits a RedemptionFinished event

    function test_givenYieldClaimed()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasYieldDepositPosition(recipient, COMMITMENT_AMOUNT)
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, _previousDepositActualAmount)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
        givenDepositPeriodEnded(0)
        givenRateSnapshotTaken
    {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = redemptionVault.getUserRedemption(recipient, 0).redeemableAt;
        vm.warp(redeemableAt);

        // Claim yield from yield deposit position
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = 0;
        vm.prank(recipient);
        ydFacility.claimYield(positionIds);

        // Claim yield from convertible deposits
        cdFacility.claimYield(iReserveToken);

        uint256 balanceBefore = iReserveToken.balanceOf(recipient);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionFinished(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);

        // Assertions
        _assertRedeemed(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            address(ydFacility),
            _previousDepositActualAmount, // Includes the redemption
            0,
            balanceBefore,
            COMMITMENT_AMOUNT // Yield deposit position
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    // [X] it transfers the deposit tokens from the facility to the caller
    // [X] it burns the receipt tokens
    // [X] it removes the redemption from the user's redemptions
    // [X] it emits a RedemptionFinished event
    // [X] it returns the amount of deposit tokens transferred

    /// forge-config: default.isolate = true
    function test_success()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = redemptionVault.getUserRedemption(recipient, 0).redeemableAt;
        vm.warp(redeemableAt);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionFinished(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Start gas snapshot
        vm.startSnapshotGas("redeem");

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);

        // Stop gas snapshot
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("Gas used", gasUsed);

        // Assertions
        _assertRedeemed(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            cdFacilityAddress,
            COMMITMENT_AMOUNT,
            0,
            0,
            0
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);

        // Assert that there are no remaining committed deposits
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            0,
            "committed deposits should be 0"
        );
    }

    function test_success_fuzz(
        uint48 timestamp_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = redemptionVault.getUserRedemption(recipient, 0).redeemableAt;
        timestamp_ = uint48(bound(timestamp_, redeemableAt, type(uint48).max));
        vm.warp(timestamp_);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionFinished(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);

        // Assertions
        _assertRedeemed(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            cdFacilityAddress,
            COMMITMENT_AMOUNT,
            0,
            0,
            0
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);

        // Assert that there are no remaining committed deposits
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            0,
            "committed deposits should be 0"
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
    {
        commitmentAmount_ = bound(commitmentAmount_, 1e17, 5e18);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        // Warp to after redeemable timestamp
        uint48 redeemableAt = redemptionVault.getUserRedemption(recipient, 0).redeemableAt;
        vm.warp(redeemableAt);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionFinished(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            commitmentAmount_
        );

        // Start gas snapshot
        vm.startSnapshotGas("redeem");

        // Call function
        vm.prank(recipient);
        redemptionVault.finishRedemption(0);

        // Stop gas snapshot
        console2.log("Gas used", vm.stopSnapshotGas());

        // Assertions
        uint256 expectedRemainingReceiptTokens = _previousDepositActualAmount - commitmentAmount_;
        _assertRedeemed(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            cdFacilityAddress,
            commitmentAmount_,
            0,
            0,
            expectedRemainingReceiptTokens
        );

        // Assert that there are no remaining committed deposits
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            0,
            "committed deposits should be 0"
        );
    }
}
