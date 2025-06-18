// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

contract UncommitRedeemCDFTest is ConvertibleDepositFacilityTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    event Uncommitted(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed cdToken,
        uint256 amount
    );

    function _assertUncommitment(
        address user_,
        uint16 commitmentId_,
        IConvertibleDepositERC20 cdToken_,
        uint256 cdTokenBalanceBefore_,
        uint256 amount_,
        uint256 previousUserCommitmentAmount_
    ) internal {
        // Get commitment
        IDepositRedemptionVault.UserCommitment memory commitment = facility.getRedeemCommitment(
            user_,
            commitmentId_
        );

        // Assert commitment values
        assertEq(address(commitment.cdToken), address(cdToken_), "CD token mismatch");
        assertEq(commitment.amount, previousUserCommitmentAmount_ - amount_, "Amount mismatch");

        // Assert CD token balances
        assertEq(
            cdToken_.balanceOf(user_),
            cdTokenBalanceBefore_ + amount_,
            "user: CD token balance mismatch"
        );
        assertEq(
            cdToken_.balanceOf(address(facility)),
            previousUserCommitmentAmount_ - amount_,
            "CDFacility: CD token balance mismatch"
        );
    }

    // given the contract is disabled
    //  [X] it reverts
    // given the commitment ID does not exist
    //  [X] it reverts
    // given the commitment ID exists for a different user
    //  [X] it reverts
    // given the amount to uncommit is 0
    //  [X] it reverts
    // given the amount to uncommit is more than the commitment
    //  [X] it reverts
    // given there has been a partial uncommit
    //  [X] it reduces the commitment amount
    // [X] it transfers the CD tokens from the contract to the caller
    // [X] it reduces the commitment amount
    // [X] it emits an Uncommitted event

    function test_contractDisabled_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call function
        vm.prank(recipient);
        facility.uncommitRedeem(0, COMMITMENT_AMOUNT);
    }

    function test_invalidCommitmentId_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.CDRedemptionVault_InvalidCommitmentId.selector,
                recipient,
                1
            )
        );

        // Call function
        vm.prank(recipient);
        facility.uncommitRedeem(1, COMMITMENT_AMOUNT);
    }

    function test_amountIsZero_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.CDRedemptionVault_ZeroAmount.selector,
                recipient
            )
        );

        // Call function
        vm.prank(recipient);
        facility.uncommitRedeem(0, 0);
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
        facility.uncommitRedeem(0, COMMITMENT_AMOUNT);
    }

    function test_amountGreaterThanCommitment_reverts(
        uint256 amount_
    ) public givenLocallyActive givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT) {
        // Bound the amount to be greater than the commitment
        amount_ = bound(amount_, COMMITMENT_AMOUNT + 1, type(uint256).max);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.CDRedemptionVault_InvalidAmount.selector,
                recipient,
                0,
                amount_
            )
        );

        // Call function
        vm.prank(recipient);
        facility.uncommitRedeem(0, amount_);
    }

    function test_success(
        uint256 amount_
    ) public givenLocallyActive givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT) {
        // Bound the amount to be between 1 and the commitment amount
        amount_ = bound(amount_, 1, COMMITMENT_AMOUNT);

        // Get CD token balance before
        uint256 cdTokenBalanceBefore = cdToken.balanceOf(recipient);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Uncommitted(recipient, 0, address(cdToken), amount_);

        // Call function
        vm.prank(recipient);
        facility.uncommitRedeem(0, amount_);

        // Assertions
        _assertUncommitment(
            recipient,
            0,
            cdToken,
            cdTokenBalanceBefore,
            amount_,
            COMMITMENT_AMOUNT
        );
    }

    function test_success_partialUncommitRedeem(
        uint256 firstAmount_,
        uint256 secondAmount_
    ) public givenLocallyActive givenCommitted(recipient, cdToken, COMMITMENT_AMOUNT) {
        // Bound the first amount to be between 1 and half the commitment amount
        firstAmount_ = bound(firstAmount_, 1, COMMITMENT_AMOUNT / 2);

        // Bound the second amount to be between 1 and the remaining commitment amount
        secondAmount_ = bound(secondAmount_, 1, COMMITMENT_AMOUNT - firstAmount_);

        // First uncommit
        vm.prank(recipient);
        facility.uncommitRedeem(0, firstAmount_);

        // Get CD token balance before second uncommit
        uint256 cdTokenBalanceBefore = cdToken.balanceOf(recipient);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Uncommitted(recipient, 0, address(cdToken), secondAmount_);

        // Call function again
        vm.prank(recipient);
        facility.uncommitRedeem(0, secondAmount_);

        // Assertions
        _assertUncommitment(
            recipient,
            0,
            cdToken,
            cdTokenBalanceBefore,
            secondAmount_,
            COMMITMENT_AMOUNT - firstAmount_
        );
    }
}
