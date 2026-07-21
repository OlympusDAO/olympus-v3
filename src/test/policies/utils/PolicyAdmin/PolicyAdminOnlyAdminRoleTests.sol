// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

import {PolicyAdminTest} from "./PolicyAdminTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @notice Shared `onlyAdminRole` modifier tests.
/// @dev    Run against each mix-in by the concrete `PolicyAdmin_OnlyAdminRole` and
///         `PolicyAdminOptimized_OnlyAdminRole` test contracts.
abstract contract PolicyAdminOnlyAdminRoleTests is PolicyAdminTest {
    // given the caller has the emergency role
    //  [X] it reverts
    // given the caller does not have the admin role
    //  [X] it reverts
    // given the caller has the admin role
    //  [X] it does not revert

    function test_callerHasEmergencyRole_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));

        vm.prank(emergency);
        policyAdmin.gatedToAdminRole();
    }

    function testFuzz_callerNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));

        vm.prank(caller_);
        policyAdmin.gatedToAdminRole();
    }

    function test_callerHasAdminRole() public {
        vm.prank(admin);
        policyAdmin.gatedToAdminRole();
    }
}
