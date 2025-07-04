// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract DepositRedemptionVaultStartRedemptionTest is DepositRedemptionVaultTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    event RedemptionStarted(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed asset,
        uint8 periodMonths,
        uint256 amount,
        address facility
    );

    function _assertCommitment(
        address user_,
        uint16 redemptionId_,
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 receiptTokenBalanceBefore_,
        uint256 amount_,
        uint256 previousUserCommitmentAmount_,
        uint256 previousOtherUserCommitmentAmount_,
        address facility_
    ) internal view {
        // Get redemption
        IDepositRedemptionVault.UserRedemption memory redemption = redemptionVault
            .getUserRedemption(user_, redemptionId_);

        // Assert redemption values
        assertEq(redemption.depositToken, address(depositToken_), "deposit token mismatch");
        assertEq(redemption.depositPeriod, depositPeriod_, "deposit period mismatch");
        assertEq(redemption.amount, amount_, "amount mismatch");
        assertEq(
            redemption.redeemableAt,
            block.timestamp + depositPeriod_ * 30 days,
            "redeemableAt mismatch"
        );
        assertEq(redemption.facility, facility_, "facility mismatch");

        // Assert redemption count
        assertEq(
            redemptionVault.getUserRedemptionCount(user_),
            redemptionId_ + 1,
            "redemption count mismatch"
        );

        // Assert receipt token balances
        uint256 receiptTokenId = depositManager.getReceiptTokenId(depositToken_, depositPeriod_);
        assertEq(
            depositManager.balanceOf(user_, receiptTokenId),
            receiptTokenBalanceBefore_ - amount_ - previousUserCommitmentAmount_,
            "user: receipt token balance mismatch"
        );
        assertEq(
            depositManager.balanceOf(address(redemptionVault), receiptTokenId),
            amount_ + previousUserCommitmentAmount_ + previousOtherUserCommitmentAmount_,
            "redemptionVault: receipt token balance mismatch"
        );

        // Assert committed deposits
        assertEq(
            redemptionVault.getFacilityCommittedDeposits(depositToken_, facility_),
            amount_ + previousUserCommitmentAmount_ + previousOtherUserCommitmentAmount_,
            "committed deposits mismatch"
        );
    }

    // given the contract is disabled
    //  [X] it reverts

    function test_contractDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        redemptionVault.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(cdFacility)
        );
    }

    // given the deposit token is not supported by the deposit manager
    //  [X] it reverts

    function test_depositTokenNotConfigured_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertDepositNotConfigured(iReserveToken, PERIOD_MONTHS + 1);

        // Call function
        vm.prank(recipient);
        redemptionVault.startRedemption(
            iReserveToken,
            PERIOD_MONTHS + 1,
            COMMITMENT_AMOUNT,
            address(cdFacility)
        );
    }

    // given the facility is not registered
    //  [X] it reverts

    function test_facilityNotRegistered_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertFacilityNotRegistered(address(0x123));

        // Call function
        vm.prank(recipient);
        redemptionVault.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(0x123)
        );
    }

    // given the facility is deauthorized
    //  [X] it reverts

    function test_deauthorizedFacility_reverts()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(recipient, address(redemptionVault), COMMITMENT_AMOUNT)
        givenFacilityIsDeauthorized(address(cdFacility))
    {
        // Expect revert
        _expectRevertFacilityNotRegistered(address(cdFacility));

        // Call function
        vm.prank(recipient);
        redemptionVault.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(cdFacility)
        );
    }

    // given the amount is 0
    //  [X] it reverts

    function test_amountIsZero_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        redemptionVault.startRedemption(iReserveToken, PERIOD_MONTHS, 0, address(cdFacility));
    }

    // given the caller has not approved the redemption vault to spend the receipt tokens
    //  [X] it reverts

    function test_spendingIsNotApproved_reverts()
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
        _expectRevertReceiptTokenInsufficientAllowance(
            address(redemptionVault),
            0,
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipient);
        redemptionVault.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(cdFacility)
        );
    }

    // given the caller does not have enough receipt tokens
    //  [X] it reverts

    function test_insufficientReceiptTokenBalance_reverts()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(recipient, address(redemptionVault), COMMITMENT_AMOUNT)
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
        redemptionVault.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(cdFacility)
        );
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
        givenReceiptTokenSpendingIsApproved(recipient, address(redemptionVault), COMMITMENT_AMOUNT)
    {
        amount_ = bound(amount_, 1, COMMITMENT_AMOUNT);

        // Reclaim the yield deposit via the redemption vault
        vm.prank(recipient);
        redemptionVault.reclaim(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(cdFacility)
        );

        // At this stage:
        // - The recipient has reclaimed 1e18 via the ConvertibleDepositFacility
        // - DepositManager has 0 in deposits from the ConvertibleDepositFacility
        // - DepositManager has 1e18 in deposits from the YieldDepositFacility

        // Expect revert
        _expectRevertInsufficientAvailableDeposits(amount_, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.startRedemption(iReserveToken, PERIOD_MONTHS, amount_, address(cdFacility));
    }

    // given there is an existing redemption for the caller
    //  given the existing redemption is for the same receipt token
    //   [X] it creates a new redemption for the caller
    //   [X] it returns a redemption ID of 1

    function test_existingCommitment_sameReceiptToken()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(recipient, address(redemptionVault), COMMITMENT_AMOUNT)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(
            recipient,
            1,
            address(iReserveToken),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(cdFacility)
        );

        // Call function
        vm.prank(recipient);
        uint16 redemptionId = redemptionVault.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(cdFacility)
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
            0,
            address(cdFacility)
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    //  [X] it creates a new redemption for the caller
    //  [X] it returns a redemption ID of 1

    function test_existingCommitment_differentReceiptToken()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveTokenTwo,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
    {
        // Approve spending of the second receipt token
        vm.prank(recipient);
        depositManager.approve(address(redemptionVault), receiptTokenIdTwo, COMMITMENT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(
            recipient,
            1,
            address(iReserveTokenTwo),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(cdFacility)
        );

        // Call function
        vm.prank(recipient);
        uint16 redemptionId = redemptionVault.startRedemption(
            iReserveTokenTwo,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(cdFacility)
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
            0,
            address(cdFacility)
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    // given there is an existing redemption for a different user
    //  [X] it returns a redemption ID of 0

    function test_existingCommitment_differentUser()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenAddressHasConvertibleDepositToken(
            recipientTwo,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(
            recipientTwo,
            address(redemptionVault),
            COMMITMENT_AMOUNT
        )
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(
            recipientTwo,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(cdFacility)
        );

        // Call function
        vm.prank(recipientTwo);
        uint16 redemptionId = redemptionVault.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            address(cdFacility)
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
            COMMITMENT_AMOUNT,
            address(cdFacility)
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
        givenReceiptTokenSpendingIsApproved(recipient, address(redemptionVault), COMMITMENT_AMOUNT)
    {
        amount_ = bound(amount_, 1, COMMITMENT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            amount_,
            address(cdFacility)
        );

        // Call function
        vm.prank(recipient);
        uint16 redemptionId = redemptionVault.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            amount_,
            address(cdFacility)
        );

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
            0,
            address(cdFacility)
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(COMMITMENT_AMOUNT - amount_);
    }
}
