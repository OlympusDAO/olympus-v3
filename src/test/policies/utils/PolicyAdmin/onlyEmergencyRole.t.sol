// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {PolicyAdminTest} from "./PolicyAdminTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract PolicyAdminOnlyEmergencyRoleTest is PolicyAdminTest {
    // given the caller does not have the emergency role
    //  [X] it reverts
    // given the caller has the emergency role
    //  [X] it does not revert

    function test_callerNotEmergencyRole_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));

        // Call function
        policyAdmin.gatedToEmergencyRole();
    }

    function test_callerHasEmergencyRole() public {
        // Call function
        vm.prank(EMERGENCY);
        policyAdmin.gatedToEmergencyRole();
    }
}
