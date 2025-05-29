// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {PolicyAdminTest} from "./PolicyAdminTest.sol";

contract PolicyAdminOnlyEmergencyOrAdminRoleTest is PolicyAdminTest {
    // given the caller does not have the admin or emergency role
    //  [X] it reverts
    // given the caller has the admin role
    //  [X] it does not revert
    // given the caller has the emergency role
    //  [X] it does not revert

    function test_callerNotEmergencyOrAdminRole_reverts() public {
        // Expect revert
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);

        // Call function
        policyAdmin.gatedToEmergencyOrAdminRole();
    }

    function test_callerHasAdminRole() public {
        // Call function
        vm.prank(ADMIN);
        policyAdmin.gatedToEmergencyOrAdminRole();
    }

    function test_callerHasEmergencyRole() public {
        // Call function
        vm.prank(EMERGENCY);
        policyAdmin.gatedToEmergencyOrAdminRole();
    }
}
