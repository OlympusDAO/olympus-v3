// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract YieldDepositFacilityUncommitRedeemTest is YieldDepositFacilityTest {
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    event Uncommitted(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    function _assertUncommitment(
        address user_,
        uint16 commitmentId_,
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 depositTokenBalanceBefore_,
        uint256 amount_,
        uint256 previousUserCommitmentAmount_
    ) internal view {
        // Get commitment
        IDepositRedemptionVault.UserCommitment memory commitment = yieldDepositFacility
            .getRedeemCommitment(user_, commitmentId_);

        // Assert commitment values
        assertEq(address(commitment.depositToken), address(depositToken_), "depositToken mismatch");
        assertEq(commitment.depositPeriod, depositPeriod_, "depositPeriod mismatch");
        assertEq(commitment.amount, previousUserCommitmentAmount_ - amount_, "Amount mismatch");

        // Assert receipt token balances
        uint256 receiptTokenId = depositManager.getReceiptTokenId(depositToken_, depositPeriod_);
        assertEq(
            depositManager.balanceOf(user_, receiptTokenId),
            depositTokenBalanceBefore_ + amount_,
            "user: receipt token balance mismatch"
        );
        assertEq(
            depositManager.balanceOf(address(yieldDepositFacility), receiptTokenId),
            previousUserCommitmentAmount_ - amount_,
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
        yieldDepositFacility.uncommitRedeem(0, COMMITMENT_AMOUNT);
    }

    // given the commitment ID does not exist
    //  [X] it reverts

    function test_invalidCommitmentId_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidCommitmentId.selector,
                recipient,
                1
            )
        );

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.uncommitRedeem(1, COMMITMENT_AMOUNT);
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
        yieldDepositFacility.uncommitRedeem(0, _previousDepositActualAmount);
    }

    // given the amount to uncommit is 0
    //  [X] it reverts

    function test_amountIsZero_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.uncommitRedeem(0, 0);
    }

    // given the amount to uncommit is more than the commitment
    //  [X] it reverts

    function test_amountGreaterThanCommitment_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Bound the amount to be greater than the commitment
        amount_ = bound(amount_, _previousDepositActualAmount + 1, type(uint256).max);

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
        yieldDepositFacility.uncommitRedeem(0, amount_);
    }

    // given there has been a partial uncommit
    //  [X] it reduces the commitment amount

    function test_success_partialUncommitRedeem(
        uint256 firstAmount_,
        uint256 secondAmount_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Bound the first amount to be between 1 and half the commitment amount
        firstAmount_ = bound(firstAmount_, 1, _previousDepositActualAmount / 2);

        // Bound the second amount to be between 1 and the remaining commitment amount
        secondAmount_ = bound(secondAmount_, 1, _previousDepositActualAmount - firstAmount_);

        // First uncommit
        vm.prank(recipient);
        yieldDepositFacility.uncommitRedeem(0, firstAmount_);

        // Get receipt token balance before second uncommit
        uint256 receiptTokenBalanceBefore = depositManager.balanceOf(recipient, _receiptTokenId);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Uncommitted(recipient, 0, address(iReserveToken), PERIOD_MONTHS, secondAmount_);

        // Call function again
        vm.prank(recipient);
        yieldDepositFacility.uncommitRedeem(0, secondAmount_);

        // Assertions
        _assertUncommitment(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            receiptTokenBalanceBefore,
            secondAmount_,
            _previousDepositActualAmount - firstAmount_
        );
    }

    // [X] it transfers the receipt tokens from the contract to the caller
    // [X] it reduces the commitment amount
    // [X] it emits an Uncommitted event

    function test_success(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
    {
        // Bound the amount to be between 1 and the commitment amount
        amount_ = bound(amount_, 1, _previousDepositActualAmount);

        // Get receipt token balance before
        uint256 receiptTokenBalanceBefore = depositManager.balanceOf(recipient, _receiptTokenId);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Uncommitted(recipient, 0, address(iReserveToken), PERIOD_MONTHS, amount_);

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.uncommitRedeem(0, amount_);

        // Assertions
        _assertUncommitment(
            recipient,
            0,
            iReserveToken,
            PERIOD_MONTHS,
            receiptTokenBalanceBefore,
            amount_,
            _previousDepositActualAmount
        );
    }
}
