// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

contract DeactivateCDFTest is ConvertibleDepositFacilityTest {
    event Deactivated();

    // given the caller does not have the emergency_shutdown role
    //  [X] it reverts
    // given the contract is already inactive
    //  [X] it does nothing
    // [X] it sets the contract to inactive
    // [X] it emits a Deactivated event

    function test_callerDoesNotHaveRole_reverts() public {
        _expectRoleRevert("emergency_shutdown");

        facility.deactivate();
    }

    function test_contractInactive() public {
        vm.prank(emergency);
        facility.deactivate();

        assertEq(facility.locallyActive(), false, "inactive");
    }

    function test_success() public givenLocallyActive {
        vm.prank(emergency);
        facility.deactivate();

        assertEq(facility.locallyActive(), false, "inactive");
    }
}
