// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {PolicyAdminTest} from "./PolicyAdminTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @notice Shared `onlyEmergencyRole` modifier tests.
/// @dev    Run against each mix-in by the concrete `PolicyAdmin_OnlyEmergencyRole` and
///         `PolicyAdminOptimized_OnlyEmergencyRole` test contracts.
abstract contract PolicyAdminOnlyEmergencyRoleTests is PolicyAdminTest {
    // given the caller has the admin role
    //  [X] it reverts
    // given the caller does not have the emergency role
    //  [X] it reverts
    // given the caller has the emergency role
    //  [X] it does not revert

    function test_callerHasAdminRole_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));

        vm.prank(admin);
        policyAdmin.gatedToEmergencyRole();
    }

    function testFuzz_callerNotEmergency_reverts(address caller_) public {
        vm.assume(caller_ != emergency);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));

        vm.prank(caller_);
        policyAdmin.gatedToEmergencyRole();
    }

    function test_callerHasEmergencyRole() public {
        vm.prank(emergency);
        policyAdmin.gatedToEmergencyRole();
    }
}
