// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract YieldDepositFacilityRedeemTest is YieldDepositFacilityTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    event Redeemed(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    function _assertRedeemed(
        address user_,
        uint16 commitmentId_,
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        uint256 otherUserCommitmentAmount_,
        uint256 alreadyRedeemedAmount_,
        uint256 uncommittedAmount_
    ) internal view {
        // Get commitment
        IDepositRedemptionVault.UserCommitment memory commitment = yieldDepositFacility
            .getRedeemCommitment(user_, commitmentId_);

        // Assert commitment values
        assertEq(address(commitment.depositToken), address(depositToken_), "depositToken mismatch");
        assertEq(commitment.depositPeriod, depositPeriod_, "depositPeriod mismatch");
        assertEq(commitment.amount, 0, "Commitment amount not 0");

        // Assert receipt token balances
        uint256 receiptTokenId = depositManager.getReceiptTokenId(depositToken_, depositPeriod_);
        assertEq(
            depositManager.balanceOf(user_, receiptTokenId),
            uncommittedAmount_,
            "User: receipt token balance mismatch"
        );
        assertEq(
            depositManager.balanceOf(address(yieldDepositFacility), receiptTokenId),
            otherUserCommitmentAmount_,
            "CDFacility: receipt token balance mismatch"
        );

        // Assert deposit token balances
        assertEq(
            depositToken_.balanceOf(user_),
            alreadyRedeemedAmount_ + amount_,
            "User: deposit token balance mismatch"
        );
        assertEq(
            depositToken_.balanceOf(address(yieldDepositFacility)),
            0,
            "CDFacility: deposit token balance mismatch"
        );
    }

    modifier givenCommitmentPeriodElapsed(uint16 commitmentId_) {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = yieldDepositFacility
            .getRedeemCommitment(recipient, commitmentId_)
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
        yieldDepositFacility.redeem(0);
    }

    // given the commitment ID does not exist
    //  [X] it reverts

    function test_commitmentIdDoesNotExist_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidCommitmentId.selector,
                recipient,
                0
            )
        );

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.redeem(0);
    }

    // given the commitment ID exists for a different user
    //  [X] it reverts

    function test_commitmentIdExistsForDifferentUser_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidCommitmentId.selector,
                recipientTwo,
                0
            )
        );

        // Call function
        vm.prank(recipientTwo);
        yieldDepositFacility.redeem(0);
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
        // Warp to before redeemable timestamp
        uint48 redeemableAt = yieldDepositFacility.getRedeemCommitment(recipient, 0).redeemableAt;
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
        yieldDepositFacility.redeem(0);
    }

    // given the commitment has already been redeemed
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
        yieldDepositFacility.redeem(0);
    }

    // given there is an existing commitment for the caller
    //  [X] it does not affect the other commitment

    function test_existingCommitment_sameUser(
        uint8 index_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenCommitmentPeriodElapsed(0)
    {
        // Redeem the chosen commitment
        index_ = uint8(bound(index_, 0, 1));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Redeemed(
            recipient,
            index_,
            address(iReserveToken),
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.redeem(index_);

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

        // The other commitment should not be affected
        uint16 otherCommitmentId = index_ == 0 ? 1 : 0;
        IDepositRedemptionVault.UserCommitment memory otherCommitment = yieldDepositFacility
            .getRedeemCommitment(recipient, otherCommitmentId);
        assertEq(
            otherCommitment.amount,
            _previousDepositActualAmount,
            "Other commitment amount mismatch"
        );
    }

    // given there is an existing commitment for a different user
    //  [X] it does not affect the other commitment

    function test_existingCommitment_differentUser()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenCommitted(recipientTwo, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenCommitmentPeriodElapsed(0)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Redeemed(
            recipientTwo,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Call function
        vm.prank(recipientTwo);
        yieldDepositFacility.redeem(0);

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

        // The other commitment should not be affected
        IDepositRedemptionVault.UserCommitment memory otherCommitment = yieldDepositFacility
            .getRedeemCommitment(recipient, 0);
        assertEq(
            otherCommitment.amount,
            _previousDepositActualAmount,
            "Other commitment amount mismatch"
        );
        assertEq(reserveToken.balanceOf(recipient), 0, "User: reserve token balance mismatch");
    }

    // given there has been an amount of receipt tokens uncommitted
    //  [X] the updated commitment amount is used

    function test_uncommitted(
        uint256 uncommittedAmount_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Uncommit an amount
        uncommittedAmount_ = bound(uncommittedAmount_, 1, _previousDepositActualAmount - 1);
        vm.prank(recipient);
        yieldDepositFacility.uncommitRedeem(0, uncommittedAmount_);

        // Warp to after redeemable timestamp
        uint48 redeemableAt = yieldDepositFacility.getRedeemCommitment(recipient, 0).redeemableAt;
        vm.warp(redeemableAt);

        // Redeem the commitment
        vm.prank(recipient);
        yieldDepositFacility.redeem(0);

        // Assertions
        _assertRedeemed(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            _previousDepositActualAmount - uncommittedAmount_,
            0,
            0,
            uncommittedAmount_
        );
    }

    // given yield has been harvested
    //  [ ] it burns the receipt tokens
    //  [ ] it transfers the underlying asset to the caller
    //  [ ] it sets the commitment amount to 0
    //  [ ] it emits a Redeemed event

    // [X] it burns the receipt tokens
    // [X] it transfers the underlying asset to the caller
    // [X] it sets the commitment amount to 0
    // [X] it emits a Redeemed event

    function test_success(
        uint48 timestamp_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = yieldDepositFacility.getRedeemCommitment(recipient, 0).redeemableAt;
        timestamp_ = uint48(bound(timestamp_, redeemableAt, type(uint48).max));
        vm.warp(timestamp_);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Redeemed(
            recipient,
            0,
            address(iReserveToken),
            PERIOD_MONTHS,
            _previousDepositActualAmount
        );

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.redeem(0);

        // Assertions
        _assertRedeemed(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            _previousDepositActualAmount,
            0,
            0,
            0
        );
    }
}
