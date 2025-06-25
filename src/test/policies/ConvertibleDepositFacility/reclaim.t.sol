// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract ConvertibleDepositFacilityReclaimTest is ConvertibleDepositFacilityTest {
    event Reclaimed(
        address indexed user,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 reclaimedAmount,
        uint256 forfeitedAmount
    );

    // given the contract is inactive
    //  [X] it reverts

    function test_contractInactive_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        facility.reclaim(iReserveToken, PERIOD_MONTHS, 1e18);
    }

    // when the amount of receipt tokens to reclaim is 0
    //  [X] it reverts

    function test_amountToReclaimIsZero_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        mintConvertibleDepositToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        facility.reclaim(iReserveToken, PERIOD_MONTHS, 0);
    }

    // when the reclaimed amount is 0
    //  [X] it reverts

    function test_reclaimedAmountIsZero_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        mintConvertibleDepositToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Will round down to 0 after the reclaim rate is applied
        uint256 amount = 1;

        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        facility.reclaim(iReserveToken, PERIOD_MONTHS, amount);
    }

    // given the caller has not approved DepositManager to spend the total amount of receipt tokens
    //  [X] it reverts

    function test_spendingIsNotApproved_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        mintConvertibleDepositToken(recipient, RESERVE_TOKEN_AMOUNT)
    {
        // Expect revert
        _expectRevertReceiptTokenInsufficientAllowance(
            address(depositManager),
            0,
            RESERVE_TOKEN_AMOUNT
        );

        // Call function
        vm.prank(recipient);
        facility.reclaim(iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT);
    }

    // [X] it transfers the reclaimed reserve tokens to the caller
    // [X] it returns the reclaimed amount
    // [X] it emits a Reclaimed event
    // [X] the OHM mint approval is not changed

    /// forge-config: default.isolate = true
    function test_success()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        mintConvertibleDepositToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        uint256 expectedReclaimedAmount = (RESERVE_TOKEN_AMOUNT *
            depositManager.getAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS)) / 100e2;
        uint256 expectedForfeitedAmount = RESERVE_TOKEN_AMOUNT - expectedReclaimedAmount;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Reclaimed(
            recipient,
            address(reserveToken),
            PERIOD_MONTHS,
            expectedReclaimedAmount,
            expectedForfeitedAmount
        );

        // Start gas snapshot
        vm.startSnapshotGas("reclaim");

        // Call function
        vm.prank(recipient);
        uint256 reclaimed = facility.reclaim(iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT);

        // Stop gas snapshot
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("Gas used", gasUsed);

        // Assertion that the reclaimed amount is the sum of the amounts adjusted by the reclaim rate
        assertEq(reclaimed, expectedReclaimedAmount, "reclaimed");

        // Assert convertible deposit tokens are transferred from the recipient
        assertEq(
            depositManager.balanceOf(recipient, receiptTokenId),
            0,
            "receiptToken.balanceOf(recipient)"
        );

        // Assert OHM not minted to the recipient
        assertEq(ohm.balanceOf(recipient), 0, "ohm.balanceOf(recipient)");

        // No dangling mint approval
        _assertMintApproval(0);

        // Deposit token is transferred to the recipient
        _assertAssetBalance(expectedForfeitedAmount, expectedReclaimedAmount);

        // Vault shares are not transferred to the TRSRY
        _assertVaultBalance();
    }

    function test_success_fuzz(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        mintConvertibleDepositToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        uint256 amountOne = bound(amount_, 3, RESERVE_TOKEN_AMOUNT);

        // Calculate the amount that will be reclaimed
        uint256 expectedReclaimedAmount = (amountOne *
            depositManager.getAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS)) / 100e2;
        uint256 expectedForfeitedAmount = amountOne - expectedReclaimedAmount;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Reclaimed(
            recipient,
            address(reserveToken),
            PERIOD_MONTHS,
            expectedReclaimedAmount,
            expectedForfeitedAmount
        );

        // Call function
        vm.prank(recipient);
        uint256 reclaimed = facility.reclaim(iReserveToken, PERIOD_MONTHS, amountOne);

        // Assert reclaimed amount
        assertEq(reclaimed, expectedReclaimedAmount, "reclaimed");

        // Assert convertible deposit tokens are transferred from the recipient
        assertEq(
            depositManager.balanceOf(recipient, receiptTokenId),
            RESERVE_TOKEN_AMOUNT - amountOne,
            "receiptToken.balanceOf(recipient)"
        );

        // Assert OHM not minted to the recipient
        assertEq(ohm.balanceOf(recipient), 0, "ohm.balanceOf(recipient)");

        // No dangling mint approval
        _assertMintApproval(0);

        // Deposit token is transferred to the recipient
        _assertAssetBalance(expectedForfeitedAmount, expectedReclaimedAmount);

        // Vault shares are not transferred to the TRSRY
        _assertVaultBalance();
    }
}
