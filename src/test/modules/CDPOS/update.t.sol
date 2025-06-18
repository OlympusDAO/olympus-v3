// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {CDPOSTest} from "./CDPOSTest.sol";

import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {Module} from "src/Kernel.sol";

contract UpdateCDPOSTest is CDPOSTest {
    event PositionUpdated(uint256 indexed positionId, uint256 remainingDeposit);

    // when the position does not exist
    //  [X] it reverts
    // when the caller is not a permissioned address
    //  [X] it reverts
    // when the caller is the owner of the position
    //  [X] it reverts
    // when the amount is 0
    //  [X] it sets the remaining deposit to 0
    // [X] it updates the remaining deposit
    // [X] it emits a PositionUpdated event

    function test_invalidPosition_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidPositionId.selector, 0));

        // Call function
        _updatePosition(0, 1e18);
    }

    function test_callerNotPermissioned_reverts()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        )
    {
        address owner1 = address(0x1);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, owner1));

        // Call function
        vm.prank(owner1);
        CDPOS.update(0, 1e18);
    }

    function test_callerIsOwner_reverts()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        )
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );

        // Call function
        CDPOS.update(0, 1e18);
    }

    function test_amountIsZero()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        )
    {
        // Call function
        _updatePosition(0, 0);

        // Assert
        assertEq(CDPOS.getPosition(0).remainingDeposit, 0);
    }

    function test_updatesRemainingDeposit(
        uint256 remainingDeposit_
    )
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        )
    {
        uint256 remainingDeposit = bound(remainingDeposit_, 0, REMAINING_DEPOSIT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(0, remainingDeposit);

        // Call function
        _updatePosition(0, remainingDeposit);

        // Assert
        _assertPosition(
            0,
            address(this),
            remainingDeposit,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        );
    }
}
