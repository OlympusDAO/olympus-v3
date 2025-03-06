// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

contract DisableCDFTest is ConvertibleDepositFacilityTest {
    event Disabled();

    // given the caller does not have the emergency role
    //  [X] it reverts
    // given the contract is already disabled
    //  [X] it reverts
    // [X] it sets the contract to disabled
    // [X] it emits a Disabled event

    function test_callerDoesNotHaveRole_reverts() public {
        // Expect revert
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);

        // Call function
        facility.disable("");
    }

    function test_contractInactive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call function
        vm.prank(emergency);
        facility.disable("");
    }

    function test_success() public givenLocallyActive {
        vm.prank(emergency);
        facility.disable("");

        assertEq(facility.isEnabled(), false, "disabled");
    }
}
