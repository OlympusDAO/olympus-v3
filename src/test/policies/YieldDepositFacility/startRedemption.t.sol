// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract YieldDepositFacilityStartRedemptionTest is YieldDepositFacilityTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    event RedemptionStarted(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed asset,
        uint8 periodMonths,
        uint256 amount
    );

    function _assertCommitment(
        address user_,
        uint16 redemptionId_,
        IERC20 asset_,
        uint8 periodMonths_,
        uint256 receiptTokenBalanceBefore_,
        uint256 amount_,
        uint256 previousUserCommitmentAmount_,
        uint256 previousOtherUserCommitmentAmount_
    ) internal view {
        // Get redemption
        IDepositRedemptionVault.UserRedemption memory redemption = yieldDepositFacility
            .getUserRedemption(user_, redemptionId_);

        // Assert redemption values
        assertEq(redemption.depositToken, address(asset_), "asset mismatch");
        assertEq(redemption.depositPeriod, periodMonths_, "periodMonths mismatch");
        assertEq(redemption.amount, amount_, "Amount mismatch");
        assertEq(
            redemption.redeemableAt,
            block.timestamp + periodMonths_ * 30 days,
            "RedeemableAt mismatch"
        );

        // Assert redemption count
        assertEq(
            yieldDepositFacility.getUserRedemptionCount(user_),
            redemptionId_ + 1,
            "Commitment count mismatch"
        );

        // Assert receipt token balances
        uint256 currentReceiptTokenId = depositManager.getReceiptTokenId(asset_, periodMonths_);
        assertEq(
            depositManager.balanceOf(user_, currentReceiptTokenId),
            receiptTokenBalanceBefore_ - amount_ - previousUserCommitmentAmount_,
            "user: receipt token balance mismatch"
        );
        assertEq(
            depositManager.balanceOf(address(yieldDepositFacility), currentReceiptTokenId),
            amount_ + previousUserCommitmentAmount_ + previousOtherUserCommitmentAmount_,
            "CDFacility: receipt token balance mismatch"
        );
    }

    // given the contract is disabled
    //  [X] it reverts

    function test_contractDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.startRedemption(iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT);
    }

    // when the receipt token is not supported by DepositManager
    //  [X] it reverts

    function test_receiptTokenNotSupported_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertRedemptionVaultInvalidToken(iReserveToken, PERIOD_MONTHS + 1);

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.startRedemption(iReserveToken, PERIOD_MONTHS + 1, COMMITMENT_AMOUNT);
    }

    // when the amount is 0
    //  [X] it reverts

    function test_amountIsZero_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.startRedemption(iReserveToken, PERIOD_MONTHS, 0);
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
        _expectRevertReceiptTokenInsufficientAllowance(
            address(yieldDepositFacility),
            0,
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.startRedemption(iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT);
    }

    // when the caller does not have enough receipt tokens
    //  [X] it reverts

    function test_receiptTokenInsufficientBalance_reverts()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(recipient, iReserveToken, PERIOD_MONTHS, 2e18)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(yieldDepositFacility),
            _previousDepositActualAmount + 1
        )
    {
        // Expect revert
        _expectRevertReceiptTokenInsufficientBalance(
            _previousDepositActualAmount,
            _previousDepositActualAmount + 1
        );

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            _previousDepositActualAmount + 1
        );
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
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(yieldDepositFacility),
            _previousDepositActualAmount
        )
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(
            recipient,
            1,
            address(iReserveToken),
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Call function
        vm.prank(recipient);
        uint16 redemptionId = yieldDepositFacility.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Assertions
        assertEq(redemptionId, 1, "Commitment ID mismatch");
        _assertCommitment(
            recipient,
            redemptionId,
            iReserveToken,
            PERIOD_MONTHS,
            _previousDepositActualAmount * 2,
            _previousDepositActualAmount,
            _previousDepositActualAmount,
            0
        );
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
        depositManager.approve(
            address(yieldDepositFacility),
            _receiptTokenIdTwo,
            _previousDepositActualAmount
        );

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(
            recipient,
            1,
            address(iReserveTokenTwo),
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Call function
        vm.prank(recipient);
        uint16 redemptionId = yieldDepositFacility.startRedemption(
            iReserveTokenTwo,
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Assertions
        assertEq(redemptionId, 1, "Commitment ID mismatch");
        _assertCommitment(
            recipient,
            redemptionId,
            iReserveTokenTwo,
            PERIOD_MONTHS,
            _previousDepositActualAmount,
            _previousDepositActualAmount,
            0,
            0
        );
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
        givenConvertibleDepositTokenSpendingIsApproved(
            recipientTwo,
            address(yieldDepositFacility),
            _previousDepositActualAmount
        )
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(
            recipientTwo,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Call function
        vm.prank(recipientTwo);
        uint16 redemptionId = yieldDepositFacility.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Assertions
        assertEq(redemptionId, 0, "Commitment ID mismatch");
        _assertCommitment(
            recipientTwo,
            redemptionId,
            iReserveToken,
            PERIOD_MONTHS,
            _previousDepositActualAmount,
            _previousDepositActualAmount,
            0,
            _previousDepositActualAmount
        );
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
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(yieldDepositFacility),
            _previousDepositActualAmount
        )
    {
        amount_ = bound(amount_, 1, _previousDepositActualAmount);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionStarted(recipient, 0, address(iReserveToken), PERIOD_MONTHS, amount_);

        // Call function
        vm.prank(recipient);
        uint16 redemptionId = yieldDepositFacility.startRedemption(
            iReserveToken,
            PERIOD_MONTHS,
            amount_
        );

        // Assertions
        assertEq(redemptionId, 0, "Commitment ID mismatch");
        _assertCommitment(
            recipient,
            redemptionId,
            iReserveToken,
            PERIOD_MONTHS,
            _previousDepositActualAmount,
            amount_,
            0,
            0
        );
    }
}
