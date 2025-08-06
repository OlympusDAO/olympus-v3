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

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_contractDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = 1; // Dummy position ID

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, 1e18);
    }

    // given the amount is zero
    //  [X] it reverts

    function test_amountToReclaimIsZero_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient(address(depositManager))
        givenReceiptTokenSpendingIsApprovedByRecipient(address(depositManager))
    {
        // Create a position
        (uint256 positionId, , ) = _createYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // Expect revert
        _expectRevertZeroAmount();

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, 0);
    }

    // when the caller does not provide any position IDs
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
            abi.encodeWithSelector(IDepositFacility.DepositFacility_NoPositions.selector)
        );

        vm.prank(recipient);
        yieldDepositFacility.reclaim(
            new uint256[](0), // No position IDs
            _previousDepositActualAmount
        );
    }

    // when any of the positions are not owned by the caller
    //  [X] it reverts

    function test_differentOwner_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, DEPOSIT_AMOUNT)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
    {
        // Create a position
        (uint256 positionId, , ) = _createYieldDepositPosition(recipient, DEPOSIT_AMOUNT);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositFacility.DepositFacility_InvalidPositionOwner.selector,
                positionId
            )
        );

        // Call function
        vm.prank(recipientTwo);
        yieldDepositFacility.reclaim(positionIds, 1e18);
    }

    // when any of the positions are not from YieldDepositFacility
    //  [X] it reverts

    function test_givenPositionsFromCDF_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, DEPOSIT_AMOUNT)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
    {
        // Create a position in CDF
        uint256 positionId = _createConvertibleDepositPosition(recipient, DEPOSIT_AMOUNT, 2e18);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositFacility.DepositFacility_InvalidPositionFacility.selector,
                positionId
            )
        );

        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, DEPOSIT_AMOUNT / 2);
    }

    // when any of the positions have a different asset
    //  [X] it reverts

    function test_differentAsset_reverts()
        public
        givenLocallyActive
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
    {
        // Mint reserve token and reserve token two
        _mintToken(iReserveToken, recipient, DEPOSIT_AMOUNT);
        _mintToken(iReserveTokenTwo, recipient, DEPOSIT_AMOUNT);

        // Approve spending
        vm.startPrank(recipient);
        iReserveToken.approve(address(depositManager), DEPOSIT_AMOUNT);
        iReserveTokenTwo.approve(address(depositManager), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Create a position
        (uint256 positionId, , ) = _createYieldDepositPosition(recipient, DEPOSIT_AMOUNT);
        (uint256 positionIdTwo, , ) = _createYieldDepositPosition(
            iReserveTokenTwo,
            PERIOD_MONTHS,
            recipient,
            DEPOSIT_AMOUNT
        );

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](2);
        positionIds[0] = positionId;
        positionIds[1] = positionIdTwo;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositFacility.DepositFacility_MultipleAssetPeriods.selector,
                positionIds
            )
        );

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, DEPOSIT_AMOUNT);
    }

    // when any of the positions have a different period
    //  [X] it reverts

    function test_differentPeriod_reverts()
        public
        givenLocallyActive
        givenReceiptTokenSpendingIsApproved(recipient, address(depositManager), DEPOSIT_AMOUNT)
    {
        // Add a different period
        vm.startPrank(admin);
        depositManager.addAssetPeriod(iReserveToken, 3, 90e2);
        vm.stopPrank();

        // Mint reserve token
        _mintToken(iReserveToken, recipient, DEPOSIT_AMOUNT);

        // Approve spending
        vm.startPrank(recipient);
        iReserveToken.approve(address(depositManager), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Create a position
        (uint256 positionId, , ) = _createYieldDepositPosition(recipient, DEPOSIT_AMOUNT / 2);
        (uint256 positionIdTwo, , ) = _createYieldDepositPosition(
            iReserveToken,
            3,
            recipient,
            DEPOSIT_AMOUNT / 2
        );

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](2);
        positionIds[0] = positionId;
        positionIds[1] = positionIdTwo;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositFacility.DepositFacility_MultipleAssetPeriods.selector,
                positionIds
            )
        );

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, DEPOSIT_AMOUNT);
    }

    // when the positions do not have sufficient remaining deposit
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

        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // First reclaim some amount
        uint256 firstReclaimAmount = actualAmount / 2;
        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, firstReclaimAmount);

        // Try to reclaim more than remaining
        uint256 excessAmount = DEPOSIT_AMOUNT; // More than the remaining actualAmount / 2

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositFacility.DepositFacility_InsufficientRemainingDeposit.selector,
                address(iReserveToken),
                PERIOD_MONTHS,
                excessAmount,
                actualAmount - firstReclaimAmount
            )
        );

        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, excessAmount);
    }

    // given the reclaimed amount rounds to zero
    //  [X] it reverts

    function test_reclaimedAmountIsZero_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient(address(depositManager))
        givenReceiptTokenSpendingIsApprovedByRecipient(address(depositManager))
    {
        // Create a position
        (uint256 positionId, , ) = _createYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // Will round down to 0 after the reclaim rate is applied
        uint256 amount = 1;

        // Expect revert
        _expectRevertZeroAmount();

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, amount);
    }

    // given there are not enough available deposits
    //  [X] it reverts

    function test_insufficientAvailableDeposits_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT)
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient(address(depositManager))
        givenAddressHasConvertibleDepositPosition(recipient, RESERVE_TOKEN_AMOUNT, 2e18)
        givenReceiptTokenSpendingIsApprovedByRecipient(address(depositManager))
        givenOperatorAuthorized(OPERATOR)
        givenCommitted(OPERATOR, RESERVE_TOKEN_AMOUNT - 1)
    {
        amount_ = bound(amount_, 1, RESERVE_TOKEN_AMOUNT - 1);

        // At this stage:
        // - The recipient has started redemption for 10e18 via the ConvertibleDepositFacility
        // - DepositManager has 10e18 in deposits from the ConvertibleDepositFacility, of which 10e18 are committed for redemption
        // - DepositManager has 10e18 in deposits from the YieldDepositFacility, of which 0 are committed for redemption
        // - The recipient has committed 10e18 of funds from the ConvertibleDepositFacility via the OPERATOR

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = 0;

        // Expect revert
        _expectRevertInsufficientDeposits(amount_, 0);

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, amount_);
    }

    // given the spending is not approved
    //  [X] it reverts

    function test_spendingIsNotApproved_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient(address(depositManager))
    {
        // Create a position
        (uint256 positionId, , ) = _createYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // Expect revert
        _expectRevertReceiptTokenInsufficientAllowance(
            address(depositManager),
            0,
            RESERVE_TOKEN_AMOUNT - 1
        );

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, RESERVE_TOKEN_AMOUNT - 1);
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

        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // Reclaim half the position
        vm.prank(recipient);
        uint256 actualReclaimed = yieldDepositFacility.reclaim(positionIds, reclaimAmount);

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

        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // Reclaim entire position
        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, actualAmount);

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
