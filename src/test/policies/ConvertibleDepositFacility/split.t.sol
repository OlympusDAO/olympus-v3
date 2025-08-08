// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

contract ConvertibleDepositFacilitySplitTest is ConvertibleDepositFacilityTest {
    uint256 public DEPOSIT_AMOUNT = 9e18;
    uint256 public POSITION_ID = 0;

    function _split(uint256 amount_) internal returns (uint256) {
        vm.prank(recipient);
        return facility.split(POSITION_ID, amount_, recipientTwo, false);
    }

    // ===== TESTS ===== //

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
