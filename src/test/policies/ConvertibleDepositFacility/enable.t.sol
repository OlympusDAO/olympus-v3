// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract ConvertibleDepositFacilityEnableTest is ConvertibleDepositFacilityTest {
    event Enabled();

    // given the caller does not have the admin role
    //  [X] it reverts

    function test_callerDoesNotHaveRole_reverts() public {
        _expectRoleRevert("admin");

        // Call function
        facility.enable("");
    }

    // given the contract is already enabled
    //  [X] it reverts

    function test_contractActive_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));

        // Call function
        vm.prank(admin);
        facility.enable("");
    }

    // [X] it sets the contract to enabled
    // [X] it emits an Enabled event

    function test_success() public {
        // Emits event
        vm.expectEmit(true, true, true, true);
        emit Enabled();

        // Call function
        vm.prank(admin);
        facility.enable("");

        // Assert state
        assertEq(facility.isEnabled(), true, "enabled");
    }
}
