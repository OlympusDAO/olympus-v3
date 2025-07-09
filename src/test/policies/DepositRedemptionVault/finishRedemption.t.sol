// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract DepositRedemptionVaultFinishRedemptionTest is DepositRedemptionVaultTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

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
        uint256 receiptTokenId = depositManager.getReceiptTokenId(depositToken_, depositPeriod_);
        assertEq(
            depositManager.balanceOf(user_, receiptTokenId),
            cancelledAmount_,
            "user: receipt token balance mismatch"
        );
        assertEq(
            depositManager.balanceOf(address(redemptionVault), receiptTokenId),
            otherUserCommitmentAmount_,
            "redemptionVault: receipt token balance mismatch"
        );

        // Assert deposit token balances
        assertEq(
            depositToken_.balanceOf(user_),
            alreadyRedeemedAmount_ + amount_,
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
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_AlreadyRedeemed.selector,
                recipient,
                0
            )
        );

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
    }

    // given there is an open loan position
    //  [ ] it reverts

    // given there is a fully-paid loan position
    //  [ ] it transfers the deposit tokens from the facility to the caller
    //  [ ] it burns the receipt tokens
    //  [ ] it removes the redemption from the user's redemptions
    //  [ ] it emits a RedemptionFinished event
    //  [ ] it returns the amount of deposit tokens transferred

    // given there is a loan position that has been defaulted
    //  [ ] it uses the reduced redemption amount
    //  [ ] it transfers the deposit tokens from the facility to the caller
    //  [ ] it burns the receipt tokens
    //  [ ] it removes the redemption from the user's redemptions
    //  [ ] it emits a RedemptionFinished event
    //  [ ] it returns the amount of deposit tokens transferred

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
            remainingAmount,
            0,
            0,
            cancelledAmount_
        );
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

        // Claim yield
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = 0;
        vm.prank(recipient);
        uint256 yieldClaimed = ydFacility.claimYield(positionIds);

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
            RESERVE_TOKEN_AMOUNT, // Includes the redemption
            0,
            yieldClaimed,
            COMMITMENT_AMOUNT // Yield deposit position
        );
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
        _assertRedeemed(recipient, 0, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT, 0, 0, 0);

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
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
        _assertRedeemed(recipient, 0, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT, 0, 0, 0);

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }
}
