// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {PolicyAdminTest} from "./PolicyAdminTest.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @notice Shared `onlyEmergencyOrAdminRole` modifier tests.
/// @dev    Run against each mix-in by the concrete `PolicyAdmin_OnlyEmergencyOrAdminRole` and
///         `PolicyAdminOptimized_OnlyEmergencyOrAdminRole` test contracts.
abstract contract PolicyAdminOnlyEmergencyOrAdminRoleTests is PolicyAdminTest {
    // given the caller has the manager role
    //  [X] it reverts
    // given the caller has neither the emergency nor admin role
    //  [X] it reverts
    // given the caller has the emergency role
    //  [X] it does not revert
    // given the caller has the admin role
    //  [X] it does not revert

    function test_callerHasManagerRole_reverts() public {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(manager);
        policyAdmin.gatedToEmergencyOrAdminRole();
    }

    function testFuzz_callerNotEmergencyOrAdmin_reverts(address caller_) public {
        vm.assume(caller_ != emergency && caller_ != admin);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(caller_);
        policyAdmin.gatedToEmergencyOrAdminRole();
    }

    function test_callerHasEmergencyRole() public {
        vm.prank(emergency);
        policyAdmin.gatedToEmergencyOrAdminRole();
    }

    function test_callerHasAdminRole() public {
        vm.prank(admin);
        policyAdmin.gatedToEmergencyOrAdminRole();
    }
}
