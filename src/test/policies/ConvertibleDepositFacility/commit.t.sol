// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositRedemptionVault} from "src/policies/interfaces/IConvertibleDepositRedemptionVault.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

contract CommitCDFTest is ConvertibleDepositFacilityTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    event Committed(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed cdToken,
        uint256 amount
    );

    function _assertCommitment(
        address user_,
        uint16 commitmentId_,
        IConvertibleDepositERC20 cdToken_,
        uint256 cdTokenBalanceBefore_,
        uint256 amount_,
        uint256 previousUserCommitmentAmount_,
        uint256 previousOtherUserCommitmentAmount_
    ) internal {
        // Get commitment
        IConvertibleDepositRedemptionVault.UserCommitment memory commitment = facility
            .getUserCommitment(user_, commitmentId_);

        // Assert commitment values
        assertEq(address(commitment.cdToken), address(cdToken_), "CD token mismatch");
        assertEq(commitment.amount, amount_, "Amount mismatch");
        assertEq(
            commitment.redeemableAt,
            block.timestamp + cdToken_.periodMonths() * 30 days,
            "RedeemableAt mismatch"
        );

        // Assert commitment count
        assertEq(
            facility.getUserCommitmentCount(user_),
            commitmentId_ + 1,
            "Commitment count mismatch"
        );

        // Assert CD token balances
        assertEq(
            cdToken_.balanceOf(user_),
            cdTokenBalanceBefore_ - amount_ - previousUserCommitmentAmount_,
            "user: CD token balance mismatch"
        );
        assertEq(
            cdToken_.balanceOf(address(facility)),
            amount_ + previousUserCommitmentAmount_ + previousOtherUserCommitmentAmount_,
            "CDFacility: CD token balance mismatch"
        );
    }

    // given the contract is disabled
    //  [X] it reverts
    // when the CD token is not supported by CDEPO
    //  [X] it reverts
    // when the amount is 0
    //  [X] it reverts
    // when the caller has not approved spending of the CD token by the contract
    //  [X] it reverts
    // when the caller does not have enough CD tokens
    //  [X] it reverts
    // given there is an existing commitment for the caller
    //  given the existing commitment is for the same CD token
    //   [X] it creates a new commitment for the caller
    //   [X] it returns a commitment ID of 1
    //  [X] it creates a new commitment for the caller
    //  [X] it returns a commitment ID of 1
    // given there is an existing commitment for a different user
    //  [X] it returns a commitment ID of 0
    // [X] it transfers the CD tokens from the caller to the contract
    // [X] it creates a new commitment for the caller
    // [X] the new commitment has the same CD token
    // [X] the new commitment has an amount equal to the amount of CD tokens committed
    // [X] the new commitment has a redeemable timestamp of the current timestamp + the number of months in the CD token's period * 30 days
    // [X] it emits a Committed event
    // [X] it returns a commitment ID of 0

    function test_contractDisabled_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call function
        vm.prank(recipient);
        facility.commit(cdToken, COMMITMENT_AMOUNT);
    }

    function test_cdTokenNotSupported_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositRedemptionVault.CDRedemptionVault_InvalidCDToken.selector,
                address(reserveToken)
            )
        );

        // Call function
        vm.prank(recipient);
        facility.commit(IConvertibleDepositERC20(address(reserveToken)), COMMITMENT_AMOUNT);
    }

    function test_amountIsZero_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositRedemptionVault.CDRedemptionVault_ZeroAmount.selector,
                recipient
            )
        );

        // Call function
        vm.prank(recipient);
        facility.commit(cdToken, 0);
    }

    function test_cdTokenNotApproved_reverts()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(recipient, cdToken, COMMITMENT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(recipient);
        facility.commit(cdToken, COMMITMENT_AMOUNT);
    }

    function test_cdTokenInsufficientBalance_reverts()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(recipient, cdToken, COMMITMENT_AMOUNT)
        givenConvertibleDepositTokenSpendingIsApproved(recipient, address(facility), 2e18)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(recipient);
        facility.commit(cdToken, 2e18);
    }

    function test_existingCommitment_sameCDToken()
        public
        givenLocallyActive
        givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT)
        givenAddressHasConvertibleDepositToken(recipient, cdToken, COMMITMENT_AMOUNT)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(facility),
            COMMITMENT_AMOUNT
        )
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Committed(recipient, 1, address(cdToken), COMMITMENT_AMOUNT);

        // Call function
        vm.prank(recipient);
        uint16 commitmentId = facility.commit(cdToken, COMMITMENT_AMOUNT);

        // Assertions
        assertEq(commitmentId, 1, "Commitment ID mismatch");
        _assertCommitment(
            recipient,
            commitmentId,
            cdToken,
            2e18,
            COMMITMENT_AMOUNT,
            COMMITMENT_AMOUNT,
            0
        );
    }

    function test_existingCommitment_differentCDToken()
        public
        givenLocallyActive
        givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT)
        givenAddressHasConvertibleDepositToken(recipient, cdTokenTwo, COMMITMENT_AMOUNT)
    {
        // Approve spending of the second CD token
        vm.prank(recipient);
        cdTokenTwo.approve(address(facility), COMMITMENT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Committed(recipient, 1, address(cdTokenTwo), COMMITMENT_AMOUNT);

        // Call function
        vm.prank(recipient);
        uint16 commitmentId = facility.commit(cdTokenTwo, COMMITMENT_AMOUNT);

        // Assertions
        assertEq(commitmentId, 1, "Commitment ID mismatch");
        _assertCommitment(
            recipient,
            commitmentId,
            cdTokenTwo,
            COMMITMENT_AMOUNT,
            COMMITMENT_AMOUNT,
            0,
            0
        );
    }

    function test_existingCommitment_differentUser()
        public
        givenLocallyActive
        givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT)
        givenAddressHasConvertibleDepositToken(recipientTwo, cdToken, COMMITMENT_AMOUNT)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipientTwo,
            address(facility),
            COMMITMENT_AMOUNT
        )
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Committed(recipientTwo, 0, address(cdToken), COMMITMENT_AMOUNT);

        // Call function
        vm.prank(recipientTwo);
        uint16 commitmentId = facility.commit(cdToken, COMMITMENT_AMOUNT);

        // Assertions
        assertEq(commitmentId, 0, "Commitment ID mismatch");
        _assertCommitment(
            recipientTwo,
            commitmentId,
            cdToken,
            COMMITMENT_AMOUNT,
            COMMITMENT_AMOUNT,
            0,
            COMMITMENT_AMOUNT
        );
    }

    function test_success(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(recipient, cdToken, COMMITMENT_AMOUNT)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(facility),
            COMMITMENT_AMOUNT
        )
    {
        amount_ = bound(amount_, 1, COMMITMENT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Committed(recipient, 0, address(cdToken), amount_);

        // Call function
        vm.prank(recipient);
        uint16 commitmentId = facility.commit(cdToken, amount_);

        // Assertions
        assertEq(commitmentId, 0, "Commitment ID mismatch");
        _assertCommitment(recipient, commitmentId, cdToken, COMMITMENT_AMOUNT, amount_, 0, 0);
    }
}
