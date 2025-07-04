// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract ConvertibleDepositFacilityFinishRedemptionTest is ConvertibleDepositFacilityTest {
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
        IDepositRedemptionVault.UserRedemption memory redemption = facility.getUserRedemption(
            user_,
            redemptionId_
        );

        // Assert redemption values
        assertEq(redemption.depositToken, address(depositToken_), "deposit token mismatch");
        assertEq(redemption.depositPeriod, depositPeriod_, "deposit period mismatch");
        assertEq(redemption.amount, 0, "Commitment amount not 0");

        // Assert receipt token balances
        uint256 receiptTokenId_ = depositManager.getReceiptTokenId(depositToken_, depositPeriod_);
        assertEq(
            depositManager.balanceOf(user_, receiptTokenId_),
            cancelledAmount_,
            "User: receipt token balance mismatch"
        );
        assertEq(
            depositManager.balanceOf(address(facility), receiptTokenId_),
            otherUserCommitmentAmount_,
            "ConvertibleDepositFacility: receipt token balance mismatch"
        );

        // Assert underlying token balances
        assertEq(
            depositToken_.balanceOf(user_),
            alreadyRedeemedAmount_ + amount_,
            "User: underlying token balance mismatch"
        );
        assertEq(
            depositToken_.balanceOf(address(facility)),
            0,
            "ConvertibleDepositFacility: underlying token balance mismatch"
        );
    }

    modifier givenCommitmentPeriodElapsed(uint16 redemptionId_) {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = facility.getUserRedemption(recipient, redemptionId_).redeemableAt;
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
        facility.finishRedemption(0);
    }

    // given the redemption ID does not exist
    //  [X] it reverts

    function test_redemptionIdDoesNotExist_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidRedemptionId.selector,
                recipient,
                0
            )
        );

        // Call function
        vm.prank(recipient);
        facility.finishRedemption(0);
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
        facility.finishRedemption(0);
    }

    // given it is before the redeemable timestamp
    //  [X] it reverts

    function test_beforeRedeemableTimestamp_reverts(
        uint48 timestamp_
    ) public givenLocallyActive givenCommitted(recipient, COMMITMENT_AMOUNT) {
        // Warp to before redeemable timestamp
        uint48 redeemableAt = facility.getUserRedemption(recipient, 0).redeemableAt;
        timestamp_ = uint48(bound(timestamp_, block.timestamp, redeemableAt - 1));
        vm.warp(timestamp_);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_TooEarly.selector,
                recipient,
                0
            )
        );

        // Call function
        vm.prank(recipient);
        facility.finishRedemption(0);
    }

    // given the redemption has already been redeemed
    //  [X] it reverts

    function test_alreadyRedeemed_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, COMMITMENT_AMOUNT)
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
        facility.finishRedemption(0);
    }

    // given there is an existing redemption for the caller
    //  [X] it does not affect the other redemption

    function test_existingCommitment_sameUser(
        uint8 index_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, COMMITMENT_AMOUNT)
        givenCommitted(recipient, COMMITMENT_AMOUNT)
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
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipient);
        facility.finishRedemption(index_);

        // Assertions
        _assertRedeemed(
            recipient,
            index_,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            COMMITMENT_AMOUNT,
            0,
            0
        );

        // The other redemption should not be affected
        uint16 otherCommitmentId = index_ == 0 ? 1 : 0;
        IDepositRedemptionVault.UserRedemption memory otherCommitment = facility.getUserRedemption(
            recipient,
            otherCommitmentId
        );
        assertEq(otherCommitment.amount, COMMITMENT_AMOUNT, "Other redemption amount mismatch");

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    // given there is an existing redemption for a different user
    //  [X] it does not affect the other redemption

    function test_existingCommitment_differentUser()
        public
        givenLocallyActive
        givenCommitted(recipient, COMMITMENT_AMOUNT)
        givenCommitted(recipientTwo, COMMITMENT_AMOUNT)
        givenCommitmentPeriodElapsed(0)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionFinished(
            recipientTwo,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        );

        // Call function
        vm.prank(recipientTwo);
        facility.finishRedemption(0);

        // Assertions
        _assertRedeemed(
            recipientTwo,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            COMMITMENT_AMOUNT,
            0,
            0
        );

        // The other redemption should not be affected
        IDepositRedemptionVault.UserRedemption memory otherCommitment = facility.getUserRedemption(
            recipient,
            0
        );
        assertEq(otherCommitment.amount, COMMITMENT_AMOUNT, "Other redemption amount mismatch");
        assertEq(reserveToken.balanceOf(recipient), 0, "User: reserve token balance mismatch");

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    // given there has been an amount of receipt tokens cancelled
    //  [X] the updated redemption amount is used

    function test_cancelled(
        uint256 cancelledAmount_
    ) public givenLocallyActive givenCommitted(recipient, COMMITMENT_AMOUNT) {
        // Cancel an amount
        cancelledAmount_ = bound(cancelledAmount_, 1, COMMITMENT_AMOUNT - 1);
        vm.prank(recipient);
        facility.cancelRedemption(0, cancelledAmount_);

        // Warp to after redeemable timestamp
        uint48 redeemableAt = facility.getUserRedemption(recipient, 0).redeemableAt;
        vm.warp(redeemableAt);

        // Redeem the redemption
        vm.prank(recipient);
        facility.finishRedemption(0);

        // Assertions
        _assertRedeemed(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT - cancelledAmount_,
            0,
            0,
            cancelledAmount_
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(cancelledAmount_);
    }

    // [X] it burns the receipt tokens
    // [X] it transfers the underlying asset to the caller
    // [X] it sets the redemption amount to 0
    // [X] it emits a RedemptionFinished event

    /// forge-config: default.isolate = true
    function test_success() public givenLocallyActive givenCommitted(recipient, COMMITMENT_AMOUNT) {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = facility.getUserRedemption(recipient, 0).redeemableAt;
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
        facility.finishRedemption(0);

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
    ) public givenLocallyActive givenCommitted(recipient, COMMITMENT_AMOUNT) {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = facility.getUserRedemption(recipient, 0).redeemableAt;
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
        facility.finishRedemption(0);

        // Assertions
        _assertRedeemed(recipient, 0, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT, 0, 0, 0);

        // Assert that the available deposits are correct
        _assertAvailableDeposits(0);
    }

    // given there are other deposits
    //  [X] it updates the available deposits

    function test_givenOtherDeposits()
        public
        givenLocallyActive
        givenCommitted(recipient, COMMITMENT_AMOUNT)
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT
        )
    {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = facility.getUserRedemption(recipient, 0).redeemableAt;
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
        facility.finishRedemption(0);

        // Stop gas snapshot
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("Gas used", gasUsed);

        // Assertions
        _assertRedeemed(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            COMMITMENT_AMOUNT,
            0,
            0,
            COMMITMENT_AMOUNT
        );

        // Assert that the available deposits are correct
        _assertAvailableDeposits(COMMITMENT_AMOUNT);
    }
}
