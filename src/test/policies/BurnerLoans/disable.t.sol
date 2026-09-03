// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansDisableTest is BurnerLoansTest {
    event Disabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at);

    // disable
    // given caller has neither admin nor emergency role
    //  when disable is called while enabled
    //   then it reverts
    function test_givenNonAdminAndNonEmergencyCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != emergency);

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        burnerLoans.disable("");
    }

    // disable
    // given the policy is already disabled
    //  when disable is called by emergency
    //   then it reverts
    function test_givenAlreadyDisabled_reverts() public {
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.prank(emergency);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.disable("");
    }

    // disable
    // given caller has only the emergency role
    //  when enable and disable are called
    //   then only disable is authorized
    function test_givenEmergencyRoleIsRequiredOnlyForDisable() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.prank(emergency);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoans.enable("");

        vm.prank(admin);
        burnerLoans.enable("");

        vm.prank(emergency);
        vm.expectEmit(address(burnerLoans));
        emit Disabled();
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit Transition(emergency, false, "", uint48(block.timestamp));
        burnerLoans.disable("");

        assertFalse(burnerLoans.isEnabled(), "enabled");
        assertTrue(roles.hasRole(emergency, EMERGENCY_ROLE), "emergency role");
    }

    // disable
    // given caller has the emergency role
    //  when disable is called while enabled
    //   then the policy is disabled and transition time is recorded
    function test_givenEmergencyCaller_disablesPolicy() public {
        vm.warp(2345);
        vm.prank(emergency);
        vm.expectEmit(address(burnerLoans));
        emit Disabled();
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit Transition(emergency, false, "", 2345);
        burnerLoans.disable("");

        assertFalse(burnerLoans.isEnabled(), "enabled");
        assertEq(burnerLoans.lastTransitionAt(), 2345, "last transition");
    }

    // disable
    // given caller has the admin role
    //  when disable is called while enabled
    //   then the policy is disabled
    function test_givenAdminCaller_disablesPolicy() public {
        vm.prank(admin);
        vm.expectEmit(address(burnerLoans));
        emit Disabled();
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit Transition(admin, false, "", uint48(block.timestamp));
        burnerLoans.disable("");

        assertFalse(burnerLoans.isEnabled(), "enabled");
    }
}
