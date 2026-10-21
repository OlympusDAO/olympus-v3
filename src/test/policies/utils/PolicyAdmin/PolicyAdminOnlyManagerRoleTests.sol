// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {PolicyAdminTest} from "./PolicyAdminTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @notice Shared `onlyManagerRole` modifier tests.
/// @dev    Run against each mix-in by the concrete `PolicyAdmin_OnlyManagerRole` and
///         `PolicyAdminOptimized_OnlyManagerRole` test contracts.
abstract contract PolicyAdminOnlyManagerRoleTests is PolicyAdminTest {
    // given the caller has the admin role
    //  [X] it reverts
    // given the caller does not have the manager role
    //  [X] it reverts
    // given the caller has the manager role
    //  [X] it does not revert

    function test_callerHasAdminRole_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, MANAGER_ROLE));

        vm.prank(admin);
        policyAdmin.gatedToManagerRole();
    }

    function testFuzz_callerNotManager_reverts(address caller_) public {
        vm.assume(caller_ != manager);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, MANAGER_ROLE));

        vm.prank(caller_);
        policyAdmin.gatedToManagerRole();
    }

    function test_callerHasManagerRole() public {
        vm.prank(manager);
        policyAdmin.gatedToManagerRole();
    }
}
