// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract ConvertibleDepositFacilityStartRedemptionTest is ConvertibleDepositFacilityTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    event RedemptionStarted(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    function _assertCommitment(
        address user_,
        uint16 redemptionId_,
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 receiptTokenBalanceBefore_,
        uint256 amount_,
        uint256 previousUserCommitmentAmount_,
        uint256 previousOtherUserCommitmentAmount_
    ) internal view {
        // Get redemption
        IDepositRedemptionVault.UserRedemption memory redemption = facility.getUserRedemption(
            user_,
            redemptionId_
        );

        // Assert redemption values
        assertEq(redemption.depositToken, address(depositToken_), "deposit token mismatch");
        assertEq(redemption.depositPeriod, depositPeriod_, "deposit period mismatch");
        assertEq(redemption.amount, amount_, "Amount mismatch");
        assertEq(
            redemption.redeemableAt,
            block.timestamp + depositPeriod_ * 30 days,
            "RedeemableAt mismatch"
        );

        // Assert redemption count
        assertEq(
            facility.getUserRedemptionCount(user_),
            redemptionId_ + 1,
            "Commitment count mismatch"
        );

        // Assert receipt token balances
        uint256 receiptTokenId_ = depositManager.getReceiptTokenId(depositToken_, depositPeriod_);
        assertEq(
            depositManager.balanceOf(user_, receiptTokenId_),
            receiptTokenBalanceBefore_ - amount_ - previousUserCommitmentAmount_,
            "user: receipt token balance mismatch"
        );
        assertEq(
            depositManager.balanceOf(address(facility), receiptTokenId_),
            amount_ + previousUserCommitmentAmount_ + previousOtherUserCommitmentAmount_,
            "ConvertibleDepositFacility: receipt token balance mismatch"
        );
    }

    // given the contract is disabled
    //  [X] it reverts

    function test_contractDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        facility.startRedemption(iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT);
    }

    // when the deposit token is not supported by the deposit manager
    //  [X] it reverts

    function test_receiptTokenNotSupported_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertDepositNotConfigured(iReserveToken, PERIOD_MONTHS + 1);

        // Call function
        vm.prank(recipient);
        facility.startRedemption(iReserveToken, PERIOD_MONTHS + 1, COMMITMENT_AMOUNT);
    }

    // when the amount is 0
    //  [X] it reverts

    function test_amountIsZero_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        facility.startRedemption(iReserveToken, PERIOD_MONTHS, 0);
    }

    // when the caller has not approved spending of the receipt token by the contract
    //  [X] it reverts

    function test_receiptTokenNotApproved_reverts()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
    {
        // Expect revert
        _expectRevertReceiptTokenInsufficientAllowance(address(facility), 0, COMMITMENT_AMOUNT);

        // Call function
        vm.prank(recipient);
        facility.startRedemption(iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT);
    }

    // when the caller does not have enough receipt tokens
    //  [X] it reverts

    function test_receiptTokenInsufficientBalance_reverts()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(recipient, address(facility), COMMITMENT_AMOUNT)
    {
        // Transfer the receipt tokens to reduce the balance
        vm.startPrank(recipient);
        depositManager.transfer(
            address(this),
            depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS),
            1e17
        );
        vm.stopPrank();

        // Expect revert
        _expectRevertReceiptTokenInsufficientBalance(COMMITMENT_AMOUNT - 1e17, COMMITMENT_AMOUNT);

        // Call function
        vm.prank(recipient);
        facility.startRedemption(iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT);
    }

    // given the facility does not have enough available deposits to fulfill the redemption
    //  [X] it reverts

    function test_insufficientAvailableDeposits_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPositionNoWrap(recipient, COMMITMENT_AMOUNT)
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasYieldDepositPosition(recipient, COMMITMENT_AMOUNT)
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), COMMITMENT_AMOUNT)
        givenReceiptTokenSpendingIsApproved(recipient, address(facility), COMMITMENT_AMOUNT)
    {
        amount_ = bound(amount_, 1, COMMITMENT_AMOUNT);

        // Reclaim the yield deposit via the ConvertibleDepositFacility
        vm.prank(recipient);
        facility.reclaim(iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT);

        // At this stage:
        // - The recipient has reclaimed 1e18 via the ConvertibleDepositFacility
        // - DepositManager has 0 in deposits from the ConvertibleDepositFacility
        // - DepositManager has 1e18 in deposits from the YieldDepositFacility

        // Expect revert
        _expectRevertInsufficientAvailableDeposits(amount_, 0);

        // Call function
        vm.prank(recipient);
        facility.startRedemption(iReserveToken, PERIOD_MONTHS, amount_);
    }

    // given there is an existing redemption for the caller
    //  given the existing redemption is for the same receipt token
    //   [X] it creates a new redemption for the caller
    //   [X] it returns a redemption ID of 1

    function test_existingCommitment_sameReceiptToken()
        public
        givenLocallyActive
        givenCommitted(recipient, COMMITMENT_AMOUNT)
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(recipient, address(facility), COMMITMENT_AMOUNT)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(
            recipient,
            1,
            address(iReserveToken),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipient);
        uint16 redemptionId = facility.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Assertions
        assertEq(redemptionId, 1, "Commitment ID mismatch");
        _assertCommitment(
            recipient,
            redemptionId,
            iReserveToken,
            PERIOD_MONTHS,
            2e18,
            COMMITMENT_AMOUNT,
            COMMITMENT_AMOUNT,
            0
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    //  [X] it creates a new redemption for the caller
    //  [X] it returns a redemption ID of 1

    function test_existingCommitment_differentReceiptToken()
        public
        givenLocallyActive
        givenCommitted(recipient, COMMITMENT_AMOUNT)
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveTokenTwo,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
    {
        // Approve spending of the second receipt token
        vm.prank(recipient);
        depositManager.approve(address(facility), receiptTokenIdTwo, COMMITMENT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(
            recipient,
            1,
            address(iReserveTokenTwo),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipient);
        uint16 redemptionId = facility.startRedemption(
            iReserveTokenTwo,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Assertions
        assertEq(redemptionId, 1, "Commitment ID mismatch");
        _assertCommitment(
            recipient,
            redemptionId,
            iReserveTokenTwo,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            COMMITMENT_AMOUNT,
            0,
            0
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    // given there is an existing redemption for a different user
    //  [X] it returns a redemption ID of 0

    function test_existingCommitment_differentUser()
        public
        givenLocallyActive
        givenCommitted(recipient, COMMITMENT_AMOUNT)
        givenAddressHasConvertibleDepositToken(
            recipientTwo,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(recipientTwo, address(facility), COMMITMENT_AMOUNT)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(
            recipientTwo,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipientTwo);
        uint16 redemptionId = facility.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Assertions
        assertEq(redemptionId, 0, "Commitment ID mismatch");
        _assertCommitment(
            recipientTwo,
            redemptionId,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            COMMITMENT_AMOUNT,
            0,
            COMMITMENT_AMOUNT
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    // [X] it transfers the receipt tokens from the caller to the contract
    // [X] it creates a new redemption for the caller
    // [X] the new redemption has the same receipt token
    // [X] the new redemption has an amount equal to the amount of receipt tokens for redemption
    // [X] the new redemption has a redeemable timestamp of the current timestamp + the number of months in the receipt token's period * 30 days
    // [X] it emits a RedemptionStarted event
    // [X] it returns a redemption ID of 0

    function test_success(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(recipient, address(facility), COMMITMENT_AMOUNT)
    {
        amount_ = bound(amount_, 1, COMMITMENT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(recipient, 0, address(iReserveToken), PERIOD_MONTHS, amount_);

        // Call function
        vm.prank(recipient);
        uint16 redemptionId = facility.startRedemption(iReserveToken, PERIOD_MONTHS, amount_);

        // Assertions
        assertEq(redemptionId, 0, "Commitment ID mismatch");
        _assertCommitment(
            recipient,
            redemptionId,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            amount_,
            0,
            0
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(COMMITMENT_AMOUNT - amount_);
    }
}
