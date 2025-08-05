// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IYieldDepositFacility} from "src/policies/interfaces/deposits/IYieldDepositFacility.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract YieldDepositFacilityReclaimTest is YieldDepositFacilityTest {
    event Reclaimed(
        address indexed user,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 reclaimedAmount,
        uint256 forfeitedAmount
    );

    uint256 public constant DEPOSIT_AMOUNT = 1e18;

    // given the user does not own a matching position
    //  [X] it reverts
    function test_givenUserDoesNotOwnMatchingPosition_reverts()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            DEPOSIT_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            _previousDepositActualAmount
        )
    {
        // Expect revert when trying to reclaim without owning position
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_NoMatchingPosition.selector,
                recipient,
                address(iReserveToken),
                PERIOD_MONTHS
            )
        );

        vm.prank(recipient);
        yieldDepositFacility.reclaimFor(
            iReserveToken,
            PERIOD_MONTHS,
            recipient,
            _previousDepositActualAmount
        );
    }

    // given the user owns a matching position with sufficient remaining deposit
    //  [X] it reduces the remaining deposit amount
    //  [X] it transfers the reclaimed amount to recipient
    //  [X] it emits the Reclaimed event
    function test_givenUserOwnsMatchingPosition_reducesRemainingDeposit()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, DEPOSIT_AMOUNT)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
    {
        // Create a position
        (uint256 positionId, , uint256 actualAmount) = _createYieldDepositPosition(
            recipient,
            DEPOSIT_AMOUNT
        );

        // Verify initial position state
        IDepositPositionManager.Position memory positionBefore = convertibleDepositPositions
            .getPosition(positionId);
        assertEq(
            positionBefore.remainingDeposit,
            actualAmount,
            "Position should start with full remaining deposit equal to actual amount"
        );

        uint256 reclaimAmount = actualAmount / 2; // Reclaim half
        uint256 recipientBalanceBefore = reserveToken.balanceOf(recipient);

        // Calculate expected reclaimed amount (90% reclaim rate by default)
        uint256 expectedReclaimed = (reclaimAmount * 9000) / 10000;

        // Expect the Reclaimed event
        vm.expectEmit(true, true, true, true);
        emit Reclaimed(
            recipient,
            address(iReserveToken),
            PERIOD_MONTHS,
            expectedReclaimed,
            reclaimAmount - expectedReclaimed
        );

        // Reclaim half the position
        vm.prank(recipient);
        uint256 actualReclaimed = yieldDepositFacility.reclaimFor(
            iReserveToken,
            PERIOD_MONTHS,
            recipient,
            reclaimAmount
        );

        // Verify the reclaimed amount
        assertEq(
            actualReclaimed,
            expectedReclaimed,
            "Actual reclaimed amount should match expected reclaimed amount"
        );
        assertEq(
            reserveToken.balanceOf(recipient),
            recipientBalanceBefore + expectedReclaimed,
            "Recipient reserve token balance should increase by expected reclaimed amount"
        );

        // Verify position was updated
        IDepositPositionManager.Position memory positionAfter = convertibleDepositPositions
            .getPosition(positionId);
        assertEq(
            positionAfter.remainingDeposit,
            actualAmount - reclaimAmount,
            "Position remaining deposit should be reduced by reclaim amount"
        );
    }

    // given the user owns multiple positions but only one matches
    //  [X] it only updates the matching position
    function test_givenMultiplePositions_onlyUpdatesMatchingPosition()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, DEPOSIT_AMOUNT * 3)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT * 3)
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT * 3)
    {
        // Add missing asset periods for this test
        vm.startPrank(admin);
        depositManager.addAssetPeriod(iReserveToken, 3, 90e2); // 3 months
        depositManager.addAssetPeriod(iReserveToken, 12, 90e2); // 12 months
        vm.stopPrank();

        // Create multiple positions with different periods
        vm.prank(recipient);
        (uint256 positionId1, , uint256 actualAmount1) = yieldDepositFacility.createPosition(
            IYieldDepositFacility.CreatePositionParams({
                asset: iReserveToken,
                periodMonths: 3,
                amount: DEPOSIT_AMOUNT,
                wrapPosition: false,
                wrapReceipt: false
            })
        );

        vm.prank(recipient);
        (uint256 positionId2, , uint256 actualAmount2) = yieldDepositFacility.createPosition(
            IYieldDepositFacility.CreatePositionParams({
                asset: iReserveToken,
                periodMonths: 6,
                amount: DEPOSIT_AMOUNT,
                wrapPosition: false,
                wrapReceipt: false
            })
        );

        vm.prank(recipient);
        (uint256 positionId3, , uint256 actualAmount3) = yieldDepositFacility.createPosition(
            IYieldDepositFacility.CreatePositionParams({
                asset: iReserveToken,
                periodMonths: 12,
                amount: DEPOSIT_AMOUNT,
                wrapPosition: false,
                wrapReceipt: false
            })
        );

        uint256 reclaimAmount = actualAmount2 / 2;

        // Reclaim from the 6-month position
        vm.prank(recipient);
        yieldDepositFacility.reclaimFor(iReserveToken, 6, recipient, reclaimAmount);

        // Verify only the 6-month position was updated
        IDepositPositionManager.Position memory position1 = convertibleDepositPositions.getPosition(
            positionId1
        );
        IDepositPositionManager.Position memory position2 = convertibleDepositPositions.getPosition(
            positionId2
        );
        IDepositPositionManager.Position memory position3 = convertibleDepositPositions.getPosition(
            positionId3
        );

        assertEq(position1.remainingDeposit, actualAmount1, "3-month position should be unchanged");
        assertEq(
            position2.remainingDeposit,
            actualAmount2 - reclaimAmount,
            "6-month position should be reduced"
        );
        assertEq(
            position3.remainingDeposit,
            actualAmount3,
            "12-month position should be unchanged"
        );
    }

    // given the user has multiple positions in the same deposit period
    //  [X] it deducts from positions in ascending order of token id
    function test_givenMultiplePositionsSamePeriod_deductsInAscendingTokenIdOrder()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, DEPOSIT_AMOUNT * 3)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT * 3)
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT * 3)
    {
        // Create multiple positions with same period (token IDs will be sequential)
        (uint256 positionId1, , uint256 actualAmount1) = _createYieldDepositPosition(
            recipient,
            DEPOSIT_AMOUNT
        );
        (uint256 positionId2, , uint256 actualAmount2) = _createYieldDepositPosition(
            recipient,
            DEPOSIT_AMOUNT
        );
        (uint256 positionId3, , uint256 actualAmount3) = _createYieldDepositPosition(
            recipient,
            DEPOSIT_AMOUNT
        );

        // Verify token IDs are sequential
        assertLt(positionId1, positionId2, "Position 1 ID should be less than Position 2 ID");
        assertLt(positionId2, positionId3, "Position 2 ID should be less than Position 3 ID");

        uint256 reclaimAmount = actualAmount1 + (actualAmount2 / 2); // 1.5 deposit amounts

        // Reclaim should deduct from positions in ascending token ID order
        vm.prank(recipient);
        yieldDepositFacility.reclaimFor(iReserveToken, PERIOD_MONTHS, recipient, reclaimAmount);

        // Verify deduction order: first position fully depleted, second position partially depleted
        IDepositPositionManager.Position memory position1 = convertibleDepositPositions.getPosition(
            positionId1
        );
        IDepositPositionManager.Position memory position2 = convertibleDepositPositions.getPosition(
            positionId2
        );
        IDepositPositionManager.Position memory position3 = convertibleDepositPositions.getPosition(
            positionId3
        );

        assertEq(
            position1.remainingDeposit,
            0,
            "First position remaining deposit should be zero after full depletion"
        );
        assertEq(
            position2.remainingDeposit,
            actualAmount2 - (actualAmount2 / 2),
            "Second position remaining deposit should be reduced by half"
        );
        assertEq(
            position3.remainingDeposit,
            actualAmount3,
            "Third position remaining deposit should be unchanged"
        );
    }

    // given the user has multiple positions where some have remaining deposit of 0
    //  [X] it skips positions with zero remaining deposit
    function test_givenPositionsWithZeroRemainingDeposit_skipsZeroPositions()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, DEPOSIT_AMOUNT * 3)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT * 3)
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT * 3)
    {
        // Create multiple positions
        (uint256 positionId1, , uint256 actualAmount1) = _createYieldDepositPosition(
            recipient,
            DEPOSIT_AMOUNT
        );
        (uint256 positionId2, , uint256 actualAmount2) = _createYieldDepositPosition(
            recipient,
            DEPOSIT_AMOUNT
        );
        (uint256 positionId3, , uint256 actualAmount3) = _createYieldDepositPosition(
            recipient,
            DEPOSIT_AMOUNT
        );

        // Fully reclaim first position
        vm.prank(recipient);
        yieldDepositFacility.reclaimFor(iReserveToken, PERIOD_MONTHS, recipient, actualAmount1);

        // Verify first position is depleted
        IDepositPositionManager.Position memory position1 = convertibleDepositPositions.getPosition(
            positionId1
        );
        assertEq(
            position1.remainingDeposit,
            0,
            "First position remaining deposit should be zero after full reclaim"
        );

        // Now reclaim more - should skip the zero position and use the second position
        uint256 secondReclaimAmount = actualAmount2 / 2;
        vm.prank(recipient);
        yieldDepositFacility.reclaimFor(
            iReserveToken,
            PERIOD_MONTHS,
            recipient,
            secondReclaimAmount
        );

        // Verify positions state
        position1 = convertibleDepositPositions.getPosition(positionId1);
        IDepositPositionManager.Position memory position2 = convertibleDepositPositions.getPosition(
            positionId2
        );
        IDepositPositionManager.Position memory position3 = convertibleDepositPositions.getPosition(
            positionId3
        );

        assertEq(
            position1.remainingDeposit,
            0,
            "First position remaining deposit should remain at zero"
        );
        assertEq(
            position2.remainingDeposit,
            actualAmount2 - secondReclaimAmount,
            "Second position remaining deposit should be reduced by second reclaim amount"
        );
        assertEq(
            position3.remainingDeposit,
            actualAmount3,
            "Third position remaining deposit should be unchanged after second reclaim"
        );
    }

    // given the user has positions from ConvertibleDepositFacility (not YieldDepositFacility)
    //  [X] it reverts
    function test_givenPositionsFromCDF_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, DEPOSIT_AMOUNT)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
        givenAddressHasConvertibleDepositPosition(recipient, DEPOSIT_AMOUNT, 2e18)
    {
        // The givenAddressHasConvertibleDepositPosition modifier creates a CDF position
        // Now try to reclaim through YDF, which should revert

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_NoMatchingPosition.selector,
                recipient,
                address(iReserveToken),
                PERIOD_MONTHS
            )
        );

        vm.prank(recipient);
        yieldDepositFacility.reclaimFor(
            iReserveToken,
            PERIOD_MONTHS,
            recipient,
            DEPOSIT_AMOUNT / 2
        );
    }

    // given the user tries to reclaim more than their remaining deposit
    //  [X] it reverts
    function test_givenReclaimAmountExceedsRemainingDeposit_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, DEPOSIT_AMOUNT)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
    {
        // Create a position
        (uint256 positionId, , uint256 actualAmount) = _createYieldDepositPosition(
            recipient,
            DEPOSIT_AMOUNT
        );

        // First reclaim some amount
        uint256 firstReclaimAmount = actualAmount / 2;
        vm.prank(recipient);
        yieldDepositFacility.reclaimFor(
            iReserveToken,
            PERIOD_MONTHS,
            recipient,
            firstReclaimAmount
        );

        // Try to reclaim more than remaining
        uint256 excessAmount = DEPOSIT_AMOUNT; // More than the remaining actualAmount / 2

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_InsufficientRemainingDeposit.selector,
                recipient,
                address(iReserveToken),
                PERIOD_MONTHS,
                excessAmount,
                actualAmount - firstReclaimAmount
            )
        );

        vm.prank(recipient);
        yieldDepositFacility.reclaimFor(iReserveToken, PERIOD_MONTHS, recipient, excessAmount);
    }

    // given the user reclaims their entire position
    //  [X] it sets remaining deposit to zero
    function test_givenUserReclaimsEntirePosition_setsRemainingDepositToZero()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, DEPOSIT_AMOUNT)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
    {
        // Create a position
        (uint256 positionId, , uint256 actualAmount) = _createYieldDepositPosition(
            recipient,
            DEPOSIT_AMOUNT
        );

        // Reclaim entire position
        vm.prank(recipient);
        yieldDepositFacility.reclaimFor(iReserveToken, PERIOD_MONTHS, recipient, actualAmount);

        // Verify position remaining deposit is zero
        IDepositPositionManager.Position memory position = convertibleDepositPositions.getPosition(
            positionId
        );
        assertEq(
            position.remainingDeposit,
            0,
            "Position remaining deposit should be zero after full reclaim"
        );
    }
}
