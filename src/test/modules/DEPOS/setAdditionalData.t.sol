// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DEPOSTest} from "./DEPOSTest.sol";

import {Module} from "src/Kernel.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

contract UpdateDEPOSTest is DEPOSTest {
    event PositionAdditionalDataUpdated(uint256 indexed positionId, bytes additionalData);

    // when the position does not exist
    //  [X] it reverts
    // when the caller is not a permissioned address
    //  [X] it reverts
    // when the caller is not the operator of the position
    //  [X] it reverts
    // when the caller is the owner of the position
    //  [X] it reverts
    // when the additional data is empty
    //  [X] it sets the additional data to an empty bytes
    // [X] it updates the additional data
    // [X] it emits a PositionAdditionalDataUpdated event

    function test_invalidPosition_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IDepositPositionManager.DEPOS_InvalidPositionId.selector, 0)
        );

        // Call function
        vm.prank(godmode);
        DEPOS.setAdditionalData(0, "test");
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
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, OTHER));

        // Call function
        vm.prank(OTHER);
        DEPOS.setAdditionalData(0, "test");
    }

    function test_callerNotOperator_reverts()
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
            abi.encodeWithSelector(IDepositPositionManager.DEPOS_NotOperator.selector, 0)
        );

        // Call function
        vm.prank(godmodeTwo);
        DEPOS.setAdditionalData(0, "test");
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
        DEPOS.setAdditionalData(0, "test");
    }

    function test_additionalDataIsEmpty()
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
        vm.prank(godmode);
        DEPOS.setAdditionalData(0, "");

        // Assert
        assertEq(DEPOS.getPosition(0).additionalData, bytes(""), "additional data");
    }

    function test_updatesAdditionalData(
        bytes memory additionalData_
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
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionAdditionalDataUpdated(0, additionalData_);

        // Call function
        vm.prank(godmode);
        DEPOS.setAdditionalData(0, additionalData_);

        // Assert
        assertEq(DEPOS.getPosition(0).additionalData, additionalData_, "additional data");
    }
}
