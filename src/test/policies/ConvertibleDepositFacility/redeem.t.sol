// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

contract RedeemCDFTest is ConvertibleDepositFacilityTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    event Redeemed(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed cdToken,
        uint256 amount
    );

    function _assertRedeemed(
        address user_,
        uint16 commitmentId_,
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_,
        uint256 otherUserCommitmentAmount_,
        uint256 alreadyRedeemedAmount_,
        uint256 uncommittedAmount_
    ) internal {
        // Get commitment
        IDepositRedemptionVault.UserCommitment memory commitment = facility.getRedeemCommitment(
            user_,
            commitmentId_
        );

        // Assert commitment values
        assertEq(address(commitment.cdToken), address(cdToken_), "CD token mismatch");
        assertEq(commitment.amount, 0, "Commitment amount not 0");

        // Assert CD token balances
        assertEq(cdToken_.balanceOf(user_), uncommittedAmount_, "User: CD token balance mismatch");
        assertEq(
            cdToken_.balanceOf(address(facility)),
            otherUserCommitmentAmount_,
            "CDFacility: CD token balance mismatch"
        );

        // Assert underlying token balances
        IERC20 underlyingToken = cdToken_.asset();
        assertEq(
            underlyingToken.balanceOf(user_),
            alreadyRedeemedAmount_ + amount_,
            "User: underlying token balance mismatch"
        );
        assertEq(
            underlyingToken.balanceOf(address(facility)),
            0,
            "CDFacility: underlying token balance mismatch"
        );
    }

    modifier givenCommitmentPeriodElapsed(uint16 commitmentId_) {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = facility.getRedeemCommitment(recipient, commitmentId_).redeemableAt;
        vm.warp(redeemableAt);
        _;
    }

    // given the contract is disabled
    //  [X] it reverts
    // given the commitment ID does not exist
    //  [X] it reverts
    // given the commitment ID exists for a different user
    //  [X] it reverts
    // given it is before the redeemable timestamp
    //  [X] it reverts
    // given the commitment has already been redeemed
    //  [X] it reverts
    // given there is an existing commitment for the caller
    //  [X] it does not affect the other commitment
    // given there is an existing commitment for a different user
    //  [X] it does not affect the other commitment
    // given there has been an amount of CD tokens uncommitted
    //  [X] the updated commitment amount is used
    // [X] it burns the CD tokens
    // [X] it transfers the underlying asset to the caller
    // [X] it sets the commitment amount to 0
    // [X] it emits a Redeemed event

    function test_contractDisabled_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call function
        vm.prank(recipient);
        facility.redeem(0);
    }

    function test_commitmentIdDoesNotExist_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.CDRedemptionVault_InvalidCommitmentId.selector,
                recipient,
                0
            )
        );

        // Call function
        vm.prank(recipient);
        facility.redeem(0);
    }

    function test_commitmentIdExistsForDifferentUser_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.CDRedemptionVault_InvalidCommitmentId.selector,
                recipientTwo,
                0
            )
        );

        // Call function
        vm.prank(recipientTwo);
        facility.redeem(0);
    }

    function test_beforeRedeemableTimestamp_reverts(
        uint48 timestamp_
    ) public givenLocallyActive givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT) {
        // Warp to before redeemable timestamp
        uint48 redeemableAt = facility.getRedeemCommitment(recipient, 0).redeemableAt;
        timestamp_ = uint48(bound(timestamp_, block.timestamp, redeemableAt - 1));
        vm.warp(timestamp_);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.CDRedemptionVault_TooEarly.selector,
                recipient,
                0
            )
        );

        // Call function
        vm.prank(recipient);
        facility.redeem(0);
    }

    function test_alreadyRedeemed_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT)
        givenCommitmentPeriodElapsed(0)
        givenRedeemed(recipient, 0)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.CDRedemptionVault_AlreadyRedeemed.selector,
                recipient,
                0
            )
        );

        // Call function
        vm.prank(recipient);
        facility.redeem(0);
    }

    function test_success(
        uint48 timestamp_
    ) public givenLocallyActive givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT) {
        // Warp to after redeemable timestamp
        uint48 redeemableAt = facility.getRedeemCommitment(recipient, 0).redeemableAt;
        timestamp_ = uint48(bound(timestamp_, redeemableAt, type(uint48).max));
        vm.warp(timestamp_);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Redeemed(recipient, 0, address(cdToken), COMMITMENT_AMOUNT);

        // Call function
        vm.prank(recipient);
        facility.redeem(0);

        // Assertions
        _assertRedeemed(recipient, 0, cdToken, COMMITMENT_AMOUNT, 0, 0, 0);
    }

    function test_existingCommitment_sameUser(
        uint8 index_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT)
        givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT)
        givenCommitmentPeriodElapsed(0)
    {
        // Redeem the chosen commitment
        index_ = uint8(bound(index_, 0, 1));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Redeemed(recipient, index_, address(cdToken), COMMITMENT_AMOUNT);

        // Call function
        vm.prank(recipient);
        facility.redeem(index_);

        // Assertions
        _assertRedeemed(recipient, index_, cdToken, COMMITMENT_AMOUNT, COMMITMENT_AMOUNT, 0, 0);

        // The other commitment should not be affected
        uint16 otherCommitmentId = index_ == 0 ? 1 : 0;
        IDepositRedemptionVault.UserCommitment memory otherCommitment = facility
            .getRedeemCommitment(recipient, otherCommitmentId);
        assertEq(otherCommitment.amount, COMMITMENT_AMOUNT, "Other commitment amount mismatch");
    }

    function test_existingCommitment_differentUser()
        public
        givenLocallyActive
        givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT)
        givenCommitted(recipientTwo, cdToken, COMMITMENT_AMOUNT)
        givenCommitmentPeriodElapsed(0)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Redeemed(recipientTwo, 0, address(cdToken), COMMITMENT_AMOUNT);

        // Call function
        vm.prank(recipientTwo);
        facility.redeem(0);

        // Assertions
        _assertRedeemed(recipientTwo, 0, cdToken, COMMITMENT_AMOUNT, COMMITMENT_AMOUNT, 0, 0);

        // The other commitment should not be affected
        IDepositRedemptionVault.UserCommitment memory otherCommitment = facility
            .getRedeemCommitment(recipient, 0);
        assertEq(otherCommitment.amount, COMMITMENT_AMOUNT, "Other commitment amount mismatch");
        assertEq(reserveToken.balanceOf(recipient), 0, "User: reserve token balance mismatch");
    }

    function test_uncommitted(
        uint256 uncommittedAmount_
    ) public givenLocallyActive givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT) {
        // Uncommit an amount
        uncommittedAmount_ = bound(uncommittedAmount_, 1, COMMITMENT_AMOUNT - 1);
        vm.prank(recipient);
        facility.uncommitRedeem(0, uncommittedAmount_);

        // Warp to after redeemable timestamp
        uint48 redeemableAt = facility.getRedeemCommitment(recipient, 0).redeemableAt;
        vm.warp(redeemableAt);

        // Redeem the commitment
        vm.prank(recipient);
        facility.redeem(0);

        // Assertions
        _assertRedeemed(
            recipient,
            0,
            cdToken,
            COMMITMENT_AMOUNT - uncommittedAmount_,
            0,
            0,
            uncommittedAmount_
        );
    }
}
