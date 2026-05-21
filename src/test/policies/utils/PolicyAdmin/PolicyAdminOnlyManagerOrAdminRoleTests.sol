// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

import {PolicyAdminTest} from "./PolicyAdminTest.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @notice Shared `onlyManagerOrAdminRole` modifier tests.
/// @dev    Run against each mix-in by the concrete `PolicyAdmin_OnlyManagerOrAdminRole` and
///         `PolicyAdminOptimized_OnlyManagerOrAdminRole` test contracts.
abstract contract PolicyAdminOnlyManagerOrAdminRoleTests is PolicyAdminTest {
    // given the caller has the emergency role
    //  [X] it reverts
    // given the caller has neither the manager nor admin role
    //  [X] it reverts
    // given the caller has the manager role
    //  [X] it does not revert
    // given the caller has the admin role
    //  [X] it does not revert

    function test_callerHasEmergencyRole_reverts() public {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(emergency);
        policyAdmin.gatedToManagerOrAdminRole();
    }

    function testFuzz_callerNotManagerOrAdmin_reverts(address caller_) public {
        vm.assume(caller_ != manager && caller_ != admin);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(caller_);
        policyAdmin.gatedToManagerOrAdminRole();
    }

    function test_callerHasManagerRole() public {
        vm.prank(manager);
        policyAdmin.gatedToManagerOrAdminRole();
    }

    function test_callerHasAdminRole() public {
        vm.prank(admin);
        policyAdmin.gatedToManagerOrAdminRole();
    }
}
