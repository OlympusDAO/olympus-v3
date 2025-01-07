// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

contract ActivateCDFTest is ConvertibleDepositFacilityTest {
    event Activated();

    // given the caller does not have the emergency_shutdown role
    //  [X] it reverts
    // given the contract is already active
    //  [X] it does nothing
    // [X] it sets the contract to active
    // [X] it emits an Activated event

    function test_callerDoesNotHaveRole_reverts() public {
        _expectRoleRevert("emergency_shutdown");

        // Call function
        facility.activate();
    }

    function test_contractActive() public givenLocallyActive {
        // Call function
        vm.prank(emergency);
        facility.activate();

        // Assert state
        assertEq(facility.locallyActive(), true, "active");
    }

    function test_success() public {
        // Emits event
        vm.expectEmit(true, true, true, true);
        emit Activated();

        // Call function
        vm.prank(emergency);
        facility.activate();

        // Assert state
        assertEq(facility.locallyActive(), true, "active");
    }
}
