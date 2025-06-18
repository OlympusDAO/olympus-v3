// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract ConvertibleDepositFacilityCommitRedeemTest is ConvertibleDepositFacilityTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    event Committed(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    function _assertCommitment(
        address user_,
        uint16 commitmentId_,
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 receiptTokenBalanceBefore_,
        uint256 amount_,
        uint256 previousUserCommitmentAmount_,
        uint256 previousOtherUserCommitmentAmount_
    ) internal view {
        // Get commitment
        IDepositRedemptionVault.UserCommitment memory commitment = facility.getRedeemCommitment(
            user_,
            commitmentId_
        );

        // Assert commitment values
        assertEq(
            address(commitment.depositToken),
            address(depositToken_),
            "deposit token mismatch"
        );
        assertEq(commitment.depositPeriod, depositPeriod_, "deposit period mismatch");
        assertEq(commitment.amount, amount_, "Amount mismatch");
        assertEq(
            commitment.redeemableAt,
            block.timestamp + depositPeriod_ * 30 days,
            "RedeemableAt mismatch"
        );

        // Assert commitment count
        assertEq(
            facility.getRedeemCommitmentCount(user_),
            commitmentId_ + 1,
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
        facility.commitRedeem(iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT);
    }

    // when the CD token is not supported by CDEPO
    //  [X] it reverts

    function test_cdTokenNotSupported_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertDepositNotConfigured(iReserveToken, PERIOD_MONTHS + 1);

        // Call function
        vm.prank(recipient);
        facility.commitRedeem(iReserveToken, PERIOD_MONTHS + 1, COMMITMENT_AMOUNT);
    }

    // when the amount is 0
    //  [X] it reverts

    function test_amountIsZero_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        facility.commitRedeem(iReserveToken, PERIOD_MONTHS, 0);
    }

    // when the caller has not approved spending of the CD token by the contract
    //  [X] it reverts

    function test_cdTokenNotApproved_reverts()
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
        facility.commitRedeem(iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT);
    }

    // when the caller does not have enough CD tokens
    //  [X] it reverts

    function test_cdTokenInsufficientBalance_reverts()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(recipient, address(facility), 2e18)
    {
        // Expect revert
        _expectRevertReceiptTokenInsufficientBalance(COMMITMENT_AMOUNT, 2e18);

        // Call function
        vm.prank(recipient);
        facility.commitRedeem(iReserveToken, PERIOD_MONTHS, 2e18);
    }

    // given there is an existing commitment for the caller
    //  given the existing commitment is for the same CD token
    //   [X] it creates a new commitment for the caller
    //   [X] it returns a commitment ID of 1

    function test_existingCommitment_sameCDToken()
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
        emit Committed(recipient, 1, address(iReserveToken), PERIOD_MONTHS, COMMITMENT_AMOUNT);

        // Call function
        vm.prank(recipient);
        uint16 commitmentId = facility.commitRedeem(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Assertions
        assertEq(commitmentId, 1, "Commitment ID mismatch");
        _assertCommitment(
            recipient,
            commitmentId,
            iReserveToken,
            PERIOD_MONTHS,
            2e18,
            COMMITMENT_AMOUNT,
            COMMITMENT_AMOUNT,
            0
        );
    }

    //  [X] it creates a new commitment for the caller
    //  [X] it returns a commitment ID of 1

    function test_existingCommitment_differentCDToken()
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
        emit Committed(recipient, 1, address(iReserveTokenTwo), PERIOD_MONTHS, COMMITMENT_AMOUNT);

        // Call function
        vm.prank(recipient);
        uint16 commitmentId = facility.commitRedeem(
            iReserveTokenTwo,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Assertions
        assertEq(commitmentId, 1, "Commitment ID mismatch");
        _assertCommitment(
            recipient,
            commitmentId,
            iReserveTokenTwo,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            COMMITMENT_AMOUNT,
            0,
            0
        );
    }

    // given there is an existing commitment for a different user
    //  [X] it returns a commitment ID of 0

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
        emit Committed(recipientTwo, 0, address(iReserveToken), PERIOD_MONTHS, COMMITMENT_AMOUNT);

        // Call function
        vm.prank(recipientTwo);
        uint16 commitmentId = facility.commitRedeem(
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Assertions
        assertEq(commitmentId, 0, "Commitment ID mismatch");
        _assertCommitment(
            recipientTwo,
            commitmentId,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            COMMITMENT_AMOUNT,
            0,
            COMMITMENT_AMOUNT
        );
    }

    // [X] it transfers the CD tokens from the caller to the contract
    // [X] it creates a new commitment for the caller
    // [X] the new commitment has the same CD token
    // [X] the new commitment has an amount equal to the amount of CD tokens committed
    // [X] the new commitment has a redeemable timestamp of the current timestamp + the number of months in the CD token's period * 30 days
    // [X] it emits a Committed event
    // [X] it returns a commitment ID of 0

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
        emit Committed(recipient, 0, address(iReserveToken), PERIOD_MONTHS, amount_);

        // Call function
        vm.prank(recipient);
        uint16 commitmentId = facility.commitRedeem(iReserveToken, PERIOD_MONTHS, amount_);

        // Assertions
        assertEq(commitmentId, 0, "Commitment ID mismatch");
        _assertCommitment(
            recipient,
            commitmentId,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            amount_,
            0,
            0
        );
    }
}
