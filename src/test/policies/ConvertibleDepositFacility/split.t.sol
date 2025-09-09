// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";

contract ConvertibleDepositFacilitySplitTest is ConvertibleDepositFacilityTest {
    uint256 internal constant DEPOSIT_AMOUNT = 9e18;
    uint256 internal constant POSITION_ID = 0;

    function _split(uint256 amount_) internal returns (uint256) {
        vm.prank(recipient);
        return facility.split(POSITION_ID, amount_, recipientTwo, false);
    }

    // ===== TESTS ===== //

    // given the position was created by the YieldDepositFacility
    //  [X] it reverts when splitting via ConvertibleDepositFacility
    function test_whenPositionFromYDF_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
    {
        // Create YDF position for the recipient
        uint256 ydfPositionId = _createYieldDepositPosition(recipient, 1e18);

        // Expect revert when attempting to split via CDF
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositPositionManager.DEPOS_NotOperator.selector,
                ydfPositionId
            )
        );

        vm.prank(recipient);
        facility.split(ydfPositionId, 5e17, recipientTwo, false);
    }

    // given the contract is disabled
    //  [X] it reverts

    function test_whenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        vm.prank(recipient);
        facility.split(POSITION_ID, 1e18, recipientTwo, false);
    }

    // given the position does not exist
    //  [X] it reverts

    function test_whenPositionDoesNotExist_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositPositionManager.DEPOS_InvalidPositionId.selector,
                POSITION_ID
            )
        );

        vm.prank(recipient);
        facility.split(POSITION_ID, 1e18, recipientTwo, false);
    }

    // given the caller is not the owner of the position
    //  [X] it reverts

    function test_whenNotOwner_reverts(
        address caller_
    )
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPositionNoWrap(recipient, DEPOSIT_AMOUNT)
    {
        vm.assume(caller_ != recipient);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IDepositPositionManager.DEPOS_NotOwner.selector, POSITION_ID)
        );

        vm.prank(caller_);
        facility.split(POSITION_ID, 1e18, recipientTwo, false);
    }

    // given there is a minimum deposit
    //  when the new position would be below the minimum deposit
    //   [X] it reverts
    //  when the remaining deposit would be below the minimum deposit
    //   [X] it reverts
    //  [X] it succeeds

    function test_givenMinimumDeposit_newPositionBelowMinimumDeposit(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPositionNoWrap(recipient, DEPOSIT_AMOUNT)
        givenMinimumDeposit(1e18)
    {
        // New position < minimum deposit
        amount_ = bound(amount_, 1, 1e18 - 1);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositNotMet.selector,
                address(iReserveToken),
                amount_,
                1e18
            )
        );

        // Call function
        _split(amount_);
    }

    function test_givenMinimumDeposit_oldPositionBelowMinimumDeposit(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPositionNoWrap(recipient, DEPOSIT_AMOUNT)
        givenMinimumDeposit(1e18)
    {
        // Old position < minimum deposit
        amount_ = bound(amount_, previousDepositActual - 1e18 + 1, previousDepositActual);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositNotMet.selector,
                address(iReserveToken),
                previousDepositActual - amount_,
                1e18
            )
        );

        // Call function
        _split(amount_);
    }

    function test_givenMinimumDeposit(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPositionNoWrap(recipient, DEPOSIT_AMOUNT)
        givenMinimumDeposit(1e18)
    {
        // New position >= minimum deposit
        // Old position >= minimum deposit
        amount_ = bound(amount_, 1e18, previousDepositActual - 1e18);

        // Call function
        uint256 newPositionId = _split(amount_);

        // Check the new position was created
        assertEq(
            convertibleDepositPositions.getPosition(newPositionId).remainingDeposit,
            amount_,
            "New position amount mismatch"
        );
        assertEq(
            convertibleDepositPositions.getPosition(newPositionId).owner,
            recipientTwo,
            "New position owner mismatch"
        );

        // Check the original position was updated
        assertEq(
            convertibleDepositPositions.getPosition(POSITION_ID).remainingDeposit,
            previousDepositActual - amount_,
            "Original position amount mismatch"
        );
    }

    // [X] it creates a new position with the specified amount
    // [X] it updates the remaining deposit of the original position

    function test_success(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPositionNoWrap(recipient, DEPOSIT_AMOUNT)
    {
        amount_ = bound(amount_, 1, previousDepositActual);

        // Call function
        uint256 newPositionId = _split(amount_);

        // Check the new position was created
        assertEq(
            convertibleDepositPositions.getPosition(newPositionId).remainingDeposit,
            amount_,
            "New position amount mismatch"
        );
        assertEq(
            convertibleDepositPositions.getPosition(newPositionId).owner,
            recipientTwo,
            "New position owner mismatch"
        );

        // Check the original position was updated
        assertEq(
            convertibleDepositPositions.getPosition(POSITION_ID).remainingDeposit,
            previousDepositActual - amount_,
            "Original position amount mismatch"
        );
    }
}
