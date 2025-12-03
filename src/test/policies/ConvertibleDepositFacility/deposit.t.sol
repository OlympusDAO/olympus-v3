// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract ConvertibleDepositFacilityDepositTest is ConvertibleDepositFacilityTest {
    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        facility.deposit(iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT, true);
    }

    // given the deposit is not configured
    //  [X] it reverts

    function test_givenDepositIsNotConfigured_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidConfiguration(iReserveToken, PERIOD_MONTHS + 1);

        // Call function
        vm.prank(recipient);
        facility.deposit(iReserveToken, PERIOD_MONTHS + 1, RESERVE_TOKEN_AMOUNT, true);
    }

    // given the caller has not approved the deposit manager to spend the asset
    //  [X] it reverts

    function test_givenCallerHasNotApprovedDepositManagerToSpendAsset_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(recipient);
        facility.deposit(iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT, true);
    }

    // given the caller does not have the required asset balance
    //  [X] it reverts

    function test_givenCallerDoesNotHaveRequiredAssetBalance_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT + 1
        )
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(recipient);
        facility.deposit(iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT + 1, true);
    }

    // when wrap receipt is true
    //  [X] it transfers the asset from the caller
    //  [X] it transfers the wrapped receipt token to the caller
    //  [X] it returns the receipt token id
    //  [X] it returns the actual deposit amount
    //  [X] it does not create a position

    function test_whenWrapReceiptIsTrue()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
    {
        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(
            iReserveToken,
            PERIOD_MONTHS,
            address(facility)
        );

        // Call function
        vm.prank(recipient);
        (uint256 receiptTokenId, uint256 actualDepositAmount) = facility.deposit(
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT,
            true
        );

        // Assert that the receipt token id is correct
        assertEq(receiptTokenId, expectedReceiptTokenId, "receiptTokenId");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the wrapped receipt token amount is correct
        assertApproxEqAbs(actualDepositAmount, RESERVE_TOKEN_AMOUNT, 1, "actualDepositAmount");

        // Assert that the wrapped receipt token was minted to the recipient
        _assertReceiptTokenBalance(recipient, actualDepositAmount, true);

        // Assert that the recipient does not have a DEPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 0, "positionIds.length");

        // Assert that the available deposits are correct
        _assertAvailableDeposits(actualDepositAmount);
    }

    // [X] it transfers the asset from the caller
    // [X] it transfers the receipt token to the caller
    // [X] it returns the receipt token id
    // [X] it returns the actual deposit amount
    // [X] it does not create a position

    /// forge-config: default.isolate = true
    function test_success()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
    {
        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(
            iReserveToken,
            PERIOD_MONTHS,
            address(facility)
        );

        // Start gas snapshot
        vm.startSnapshotGas("deposit");

        // Call function
        vm.prank(recipient);
        (uint256 receiptTokenId, uint256 actualDepositAmount) = facility.deposit(
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT,
            false
        );

        // Stop gas snapshot
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("Gas used", gasUsed);

        // Assert that the receipt token id is correct
        assertEq(receiptTokenId, expectedReceiptTokenId, "receiptTokenId");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the receipt token was minted to the recipient
        _assertReceiptTokenBalance(recipient, actualDepositAmount, false);

        // Assert that the recipient does not have a DEPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 0, "positionIds.length");

        // Assert that the available deposits are correct
        _assertAvailableDeposits(actualDepositAmount);
    }
}
