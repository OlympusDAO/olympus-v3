// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract ConvertibleDepositFacilityCancelRedemptionTest is ConvertibleDepositFacilityTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    event RedemptionCancelled(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
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
        IDepositRedemptionVault.UserRedemption memory redemption = facility.getUserRedemption(
            user_,
            redemptionId_
        );

        // Assert redemption values
        assertEq(redemption.depositToken, address(depositToken_), "deposit token mismatch");
        assertEq(redemption.depositPeriod, depositPeriod_, "deposit period mismatch");
        assertEq(redemption.amount, previousUserCommitmentAmount_ - amount_, "Amount mismatch");

        // Assert receipt token token balances
        uint256 receiptTokenId_ = depositManager.getReceiptTokenId(depositToken_, depositPeriod_);
        assertEq(
            depositManager.balanceOf(user_, receiptTokenId_),
            depositTokenBalanceBefore_ + amount_,
            "user: receipt token balance mismatch"
        );
        assertEq(
            depositManager.balanceOf(address(facility), receiptTokenId_),
            previousUserCommitmentAmount_ - amount_,
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
        facility.cancelRedemption(0, COMMITMENT_AMOUNT);
    }

    // given the redemption ID does not exist
    //  [X] it reverts

    function test_invalidCommitmentId_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, COMMITMENT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidRedemptionId.selector,
                recipient,
                1
            )
        );

        // Call function
        vm.prank(recipient);
        facility.cancelRedemption(1, COMMITMENT_AMOUNT);
    }

    // given the redemption ID exists for a different user
    //  [X] it reverts

    function test_redemptionIdExistsForDifferentUser_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, COMMITMENT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidRedemptionId.selector,
                recipientTwo,
                0
            )
        );

        // Call function
        vm.prank(recipientTwo);
        facility.cancelRedemption(0, COMMITMENT_AMOUNT);
    }

    // given the amount to cancel is 0
    //  [X] it reverts

    function test_amountIsZero_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, COMMITMENT_AMOUNT)
    {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        facility.cancelRedemption(0, 0);
    }

    // given the amount to cancel is more than the redemption amount
    //  [X] it reverts

    function test_amountGreaterThanCommitment_reverts(
        uint256 amount_
    ) public givenLocallyActive givenCommitted(recipient, COMMITMENT_AMOUNT) {
        // Bound the amount to be greater than the redemption
        amount_ = bound(amount_, COMMITMENT_AMOUNT + 1, type(uint256).max);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidAmount.selector,
                recipient,
                0,
                amount_
            )
        );

        // Call function
        vm.prank(recipient);
        facility.cancelRedemption(0, amount_);
    }

    // given there has been a partial cancellation
    //  [X] it reduces the redemption amount

    function test_success_partialCancellation(
        uint256 firstAmount_,
        uint256 secondAmount_
    ) public givenLocallyActive givenCommitted(recipient, COMMITMENT_AMOUNT) {
        // Bound the first amount to be between 1 and half the redemption amount
        firstAmount_ = bound(firstAmount_, 1, COMMITMENT_AMOUNT / 2);

        // Bound the second amount to be between 1 and the remaining redemption amount
        secondAmount_ = bound(secondAmount_, 1, COMMITMENT_AMOUNT - firstAmount_);

        // First cancellation
        vm.prank(recipient);
        facility.cancelRedemption(0, firstAmount_);

        // Get receipt token balance before second cancellation
        uint256 receiptTokenBalanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionCancelled(recipient, 0, address(reserveToken), PERIOD_MONTHS, secondAmount_);

        // Call function again
        vm.prank(recipient);
        facility.cancelRedemption(0, secondAmount_);

        // Assertions
        _assertRedemptionCancelled(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            receiptTokenBalanceBefore,
            secondAmount_,
            COMMITMENT_AMOUNT - firstAmount_
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(firstAmount_ + secondAmount_);
    }

    // [X] it transfers the receipt tokens from the contract to the caller
    // [X] it reduces the redemption amount
    // [X] it emits an RedemptionCancelled event

    function test_success(
        uint256 amount_
    ) public givenLocallyActive givenCommitted(recipient, COMMITMENT_AMOUNT) {
        // Bound the amount to be between 1 and the redemption amount
        amount_ = bound(amount_, 1, COMMITMENT_AMOUNT);

        // Get receipt token balance before
        uint256 receiptTokenBalanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionCancelled(recipient, 0, address(reserveToken), PERIOD_MONTHS, amount_);

        // Call function
        vm.prank(recipient);
        facility.cancelRedemption(0, amount_);

        // Assertions
        _assertRedemptionCancelled(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            receiptTokenBalanceBefore,
            amount_,
            COMMITMENT_AMOUNT
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(amount_);
    }
}
