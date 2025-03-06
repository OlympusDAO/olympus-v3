// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {PolicyAdminTest} from "./PolicyAdminTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract PolicyAdminOnlyAdminRoleTest is PolicyAdminTest {
    // given the caller does not have the admin role
    //  [X] it reverts
    // given the caller has the admin role
    //  [X] it does not revert

    function test_callerNotAdminRole_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));

        // Call function
        policyAdmin.gatedToAdminRole();
    }

    function test_callerHasAdminRole() public {
        // Call function
        vm.prank(ADMIN);
        policyAdmin.gatedToAdminRole();
    }
}
