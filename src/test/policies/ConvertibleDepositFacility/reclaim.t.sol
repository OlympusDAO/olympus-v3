// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract ConvertibleDepositFacilityReclaimTest is ConvertibleDepositFacilityTest {
    event Reclaimed(
        address indexed user,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 reclaimedAmount,
        uint256 forfeitedAmount
    );

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
        facility.reclaim(positionIds, 1e18);
    }

    // given the amount is zero
    //  [X] it reverts

    function test_amountToReclaimIsZero_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Create a position
        (uint256 positionId, , ) = _createPosition(recipient, RESERVE_TOKEN_AMOUNT, 2e18, false);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // Expect revert
        _expectRevertZeroAmount();

        // Call function
        vm.prank(recipient);
        facility.reclaim(positionIds, 0);
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
            RESERVE_TOKEN_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            previousDepositActual
        )
    {
        // Expect revert when trying to reclaim without owning position
        vm.expectRevert(
            abi.encodeWithSelector(IDepositFacility.DepositFacility_NoPositions.selector)
        );

        vm.prank(recipient);
        yieldDepositFacility.reclaim(
            new uint256[](0), // No position IDs
            previousDepositActual
        );
    }

    // when any of the positions are not owned by the caller
    //  [X] it reverts

    function test_differentOwner_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Create a position
        uint256 positionId = _createYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT);

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
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Create a position in CDF
        (uint256 positionId, , ) = _createPosition(recipient, RESERVE_TOKEN_AMOUNT, 2e18, false);

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
        yieldDepositFacility.reclaim(positionIds, RESERVE_TOKEN_AMOUNT / 2);
    }

    // when any of the positions have a different asset
    //  [X] it reverts

    function test_differentAsset_reverts()
        public
        givenLocallyActive
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Mint reserve token and reserve token two
        _mintToken(iReserveToken, recipient, RESERVE_TOKEN_AMOUNT);
        _mintToken(iReserveTokenTwo, recipient, RESERVE_TOKEN_AMOUNT);

        // Approve spending
        vm.startPrank(recipient);
        iReserveToken.approve(address(depositManager), RESERVE_TOKEN_AMOUNT);
        iReserveTokenTwo.approve(address(depositManager), RESERVE_TOKEN_AMOUNT);
        vm.stopPrank();

        // Create a position
        uint256 positionId = _createYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT);
        (uint256 positionIdTwo, , ) = _createYieldDepositPosition(
            iReserveTokenTwo,
            PERIOD_MONTHS,
            recipient,
            RESERVE_TOKEN_AMOUNT
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
        yieldDepositFacility.reclaim(positionIds, RESERVE_TOKEN_AMOUNT);
    }

    // when any of the positions have a different period
    //  [X] it reverts

    function test_differentPeriod_reverts()
        public
        givenLocallyActive
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Add a different period
        vm.startPrank(admin);
        depositManager.addAssetPeriod(iReserveToken, 3, 90e2);
        vm.stopPrank();

        // Mint reserve token
        _mintToken(iReserveToken, recipient, RESERVE_TOKEN_AMOUNT);

        // Approve spending
        vm.startPrank(recipient);
        iReserveToken.approve(address(depositManager), RESERVE_TOKEN_AMOUNT);
        vm.stopPrank();

        // Create a position
        uint256 positionId = _createYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT / 2);
        (uint256 positionIdTwo, , ) = _createYieldDepositPosition(
            iReserveToken,
            3,
            recipient,
            RESERVE_TOKEN_AMOUNT / 2
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
        yieldDepositFacility.reclaim(positionIds, RESERVE_TOKEN_AMOUNT);
    }

    // when the positions do not have sufficient remaining deposit
    //  [X] it reverts

    function test_givenReclaimAmountExceedsRemainingDeposit_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Create a position
        (uint256 positionId, , uint256 actualAmount) = _createYieldDepositPosition(
            iReserveToken,
            PERIOD_MONTHS,
            recipient,
            RESERVE_TOKEN_AMOUNT
        );

        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // First reclaim some amount
        uint256 firstReclaimAmount = actualAmount / 2;
        vm.prank(recipient);
        yieldDepositFacility.reclaim(positionIds, firstReclaimAmount);

        // Try to reclaim more than remaining
        uint256 excessAmount = RESERVE_TOKEN_AMOUNT; // More than the remaining actualAmount / 2

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
        givenReserveTokenSpendingIsApprovedByRecipient
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Create a position
        (uint256 positionId, , ) = _createPosition(recipient, RESERVE_TOKEN_AMOUNT, 2e18, false);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // Will round down to 0 after the reclaim rate is applied
        uint256 amount = 1;

        // Expect revert
        _expectRevertZeroAmount();

        // Call function
        vm.prank(recipient);
        facility.reclaim(positionIds, amount);
    }

    // given there are not enough available deposits
    //  [X] it reverts

    function test_insufficientAvailableDeposits_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPositionNoWrap(recipient, RESERVE_TOKEN_AMOUNT)
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT)
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
        givenOperatorAuthorized(OPERATOR)
        givenCommitted(OPERATOR, RESERVE_TOKEN_AMOUNT)
    {
        amount_ = bound(amount_, 1, RESERVE_TOKEN_AMOUNT);

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
        facility.reclaim(positionIds, amount_);
    }

    // given the spending is not approved
    //  [X] it reverts

    function test_spendingIsNotApproved_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
    {
        // Create a position
        (uint256 positionId, , ) = _createPosition(recipient, RESERVE_TOKEN_AMOUNT, 2e18, false);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // Expect revert
        _expectRevertReceiptTokenInsufficientAllowance(
            address(depositManager),
            0,
            RESERVE_TOKEN_AMOUNT
        );

        // Call function
        vm.prank(recipient);
        facility.reclaim(positionIds, RESERVE_TOKEN_AMOUNT);
    }

    // given the amount is less than the available deposits
    //  [X] it succeeds
    //  [X] it transfers the deposit tokens from the facility to the caller
    //  [X] it burns the receipt tokens

    function test_success()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPositionNoWrap(recipient, RESERVE_TOKEN_AMOUNT)
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = 0;

        uint256 receiptTokenBalanceBefore = depositManager.balanceOf(
            recipient,
            depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS)
        );
        uint256 expectedReclaimedAmount = (receiptTokenBalanceBefore *
            depositManager.getAssetPeriodReclaimRate(iReserveToken, PERIOD_MONTHS)) / 100e2;
        uint256 expectedForfeitedAmount = receiptTokenBalanceBefore - expectedReclaimedAmount;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Reclaimed(
            recipient,
            address(iReserveToken),
            PERIOD_MONTHS,
            expectedReclaimedAmount,
            expectedForfeitedAmount
        );

        // Call function
        vm.prank(recipient);
        facility.reclaim(positionIds, receiptTokenBalanceBefore);

        // Assert convertible deposit tokens are transferred from the recipient
        uint256 receiptTokenId = depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS);
        assertEq(
            depositManager.balanceOf(recipient, receiptTokenId),
            0,
            "receiptToken.balanceOf(recipient)"
        );

        // Deposit token is transferred to the recipient
        assertEq(
            iReserveToken.balanceOf(recipient),
            expectedReclaimedAmount,
            "reserveToken.balanceOf(recipient)"
        );

        // Assert that the available deposits are correct (should be 0)
        assertEq(facility.getAvailableDeposits(iReserveToken), 0, "available deposits should be 0");
    }
}
