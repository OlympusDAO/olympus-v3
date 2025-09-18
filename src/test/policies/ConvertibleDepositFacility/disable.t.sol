// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

contract ConvertibleDepositFacilityDisableTest is ConvertibleDepositFacilityTest {
    event Disabled();

    // given the caller does not have the emergency role
    //  [X] it reverts

    function test_callerDoesNotHaveRole_reverts() public {
        // Expect revert
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);

        // Call function
        facility.disable("");
    }

    // given the contract is already disabled
    //  [X] it reverts

    function test_contractInactive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));

        // Call function
        vm.prank(emergency);
        facility.disable("");
    }

    // [X] it sets the contract to disabled
    // [X] it emits a Disabled event

    function test_success() public givenLocallyActive {
        vm.prank(emergency);
        facility.disable("");

        assertEq(facility.isEnabled(), false, "disabled");
    }
}
