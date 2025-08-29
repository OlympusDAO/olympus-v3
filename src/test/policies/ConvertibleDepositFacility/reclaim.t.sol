// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract ConvertibleDepositFacilityReclaimTest is ConvertibleDepositFacilityTest {
    event Reclaimed(
        address indexed user,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 reclaimedAmount,
        uint256 forfeitedAmount
    );

    // ========== HELPERS ========== //

    // Helper to call reclaim on the vault, or skip if not implemented
    function _callReclaim(address user_, IERC20 asset_, uint8 period_, uint256 amount_) internal {
        vm.prank(user_);
        facility.reclaim(asset_, period_, amount_);
    }

    // ========== TESTS ========== //

    // given the contract is disable
    //  [X] it reverts

    function test_contractDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        _callReclaim(recipient, iReserveToken, PERIOD_MONTHS, 1e18);
    }

    // given the amount is zero
    //  [X] it reverts

    function test_amountToReclaimIsZero_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Expect revert
        _expectRevertZeroAmount();

        // Call function
        _callReclaim(recipient, iReserveToken, PERIOD_MONTHS, 0);
    }

    // given the reclaimed amount rounds to zero
    //  [X] it reverts

    function test_reclaimedAmountIsZero_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Will round down to 0 after the reclaim rate is applied
        uint256 amount = 1;

        // Expect revert
        _expectRevertZeroAmount();

        // Call function
        _callReclaim(recipient, iReserveToken, PERIOD_MONTHS, amount);
    }

    // given there are not enough available deposits
    //  [X] it reverts

    function test_insufficientAvailableDeposits_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositTokenDefault(recipient)
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT)
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
        givenOperatorAuthorized(OPERATOR)
        givenCommitted(OPERATOR, RESERVE_TOKEN_AMOUNT)
    {
        amount_ = bound(amount_, 1, RESERVE_TOKEN_AMOUNT);

        // At this stage:
        // - The recipient has started redemption for 10e18 via the ConvertibleDepositFacility
        // - DepositManager has 10e18 in deposits from the ConvertibleDepositFacility, of which 10e18 are committed for redemption
        // - DepositManager has 10e18 in deposits from the YieldDepositFacility, of which 0 are committed for redemption
        // - The recipient has committed 10e18 of funds from the ConvertibleDepositFacility via the OPERATOR

        // Expect revert
        _expectRevertInsufficientDeposits(amount_, 0);

        // Call function
        _callReclaim(recipient, iReserveToken, PERIOD_MONTHS, amount_);
    }

    // given the spending is not approved
    //  [X] it reverts

    function test_spendingIsNotApproved_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Expect revert
        _expectRevertReceiptTokenInsufficientAllowance(
            address(depositManager),
            0,
            RESERVE_TOKEN_AMOUNT
        );

        // Call function
        _callReclaim(recipient, iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT);
    }

    // given the caller has receipt tokens from a different facility
    //  [X] it reverts

    function test_differentReceiptToken_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        mintYieldDepositToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenAddressHasReserveToken(recipientTwo, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipientTwo,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
        mintConvertibleDepositToken(recipientTwo, RESERVE_TOKEN_AMOUNT) // Ensures that there are deposits
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Expect revert
        _expectRevertReceiptTokenInsufficientBalance(0, RESERVE_TOKEN_AMOUNT);

        // Call function
        _callReclaim(recipient, iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT);
    }

    // given the amount is less than the available deposits
    //  [X] it succeeds
    //  [X] it transfers the deposit tokens from the facility to the caller
    //  [X] it burns the receipt tokens

    function test_success()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        uint256 expectedReclaimedAmount = (RESERVE_TOKEN_AMOUNT *
            depositManager.getAssetPeriodReclaimRate(
                iReserveToken,
                PERIOD_MONTHS,
                address(facility)
            )) / 100e2;
        uint256 expectedForfeitedAmount = RESERVE_TOKEN_AMOUNT - expectedReclaimedAmount;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Reclaimed(
            recipient,
            address(iReserveToken),
            PERIOD_MONTHS,
            expectedReclaimedAmount,
            expectedForfeitedAmount
        );

        // Call function
        _callReclaim(recipient, iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT);

        // Assert convertible deposit tokens are transferred from the recipient
        uint256 receiptTokenId = depositManager.getReceiptTokenId(
            iReserveToken,
            PERIOD_MONTHS,
            address(facility)
        );
        assertEq(
            receiptTokenManager.balanceOf(recipient, receiptTokenId),
            0,
            "receiptToken.balanceOf(recipient)"
        );

        // Deposit token is transferred to the recipient
        assertEq(
            iReserveToken.balanceOf(recipient),
            expectedReclaimedAmount,
            "reserveToken.balanceOf(recipient)"
        );

        // Assert that the available deposits are correct (should be 0)
        assertEq(facility.getAvailableDeposits(iReserveToken), 0, "available deposits should be 0");
    }

    function test_success_fuzz(
        uint16 reclaimRate_,
        uint256 depositAmount_,
        uint256 yieldAmount_
    ) public givenLocallyActive {
        reclaimRate_ = uint16(bound(reclaimRate_, 1, 100e2));
        depositAmount_ = bound(depositAmount_, 1e4, RESERVE_TOKEN_AMOUNT);
        yieldAmount_ = bound(yieldAmount_, 1e4, RESERVE_TOKEN_AMOUNT);

        // Set the reclaim rate
        vm.prank(admin);
        depositManager.setAssetPeriodReclaimRate(
            iReserveToken,
            PERIOD_MONTHS,
            address(facility),
            reclaimRate_
        );

        // Do a normal, sizeable deposit
        _mintReserveToken(recipientTwo, RESERVE_TOKEN_AMOUNT);
        _approveReserveTokenSpendingByDepositManager(recipientTwo, RESERVE_TOKEN_AMOUNT);
        _mintReceiptToken(recipientTwo, RESERVE_TOKEN_AMOUNT);

        // Deposit
        _mintReserveToken(recipient, depositAmount_);
        _approveReserveTokenSpendingByDepositManager(recipient, depositAmount_);
        _mintReceiptToken(recipient, depositAmount_);

        // Approve receipt token spending
        _approveReceiptTokenSpendingByDepositManager(recipient, depositAmount_);

        // Accrue yield
        _accrueYield(iVault, yieldAmount_);

        uint256 expectedReclaimedAmount = (depositAmount_ *
            depositManager.getAssetPeriodReclaimRate(
                iReserveToken,
                PERIOD_MONTHS,
                address(facility)
            )) / 100e2;
        uint256 expectedForfeitedAmount = depositAmount_ - expectedReclaimedAmount;

        // Expect event
        vm.expectEmit(true, true, true, false); // reclaimed and forfeited amounts are non-deterministic due to rounding
        emit Reclaimed(
            recipient,
            address(iReserveToken),
            PERIOD_MONTHS,
            expectedReclaimedAmount,
            expectedForfeitedAmount
        );

        // Call function
        _callReclaim(recipient, iReserveToken, PERIOD_MONTHS, depositAmount_);

        // Assert convertible deposit tokens are transferred from the recipient
        uint256 receiptTokenId = depositManager.getReceiptTokenId(
            iReserveToken,
            PERIOD_MONTHS,
            address(facility)
        );
        assertEq(
            receiptTokenManager.balanceOf(recipient, receiptTokenId),
            0,
            "receiptToken.balanceOf(recipient)"
        );

        // Deposit token is transferred to the recipient
        assertEq(
            iReserveToken.balanceOf(recipient),
            expectedReclaimedAmount,
            "reserveToken.balanceOf(recipient)"
        );

        // Assert that the available deposits are correct
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            RESERVE_TOKEN_AMOUNT,
            "available deposits should be 0"
        );
    }
}
