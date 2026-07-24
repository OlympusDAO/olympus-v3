// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansEnableTest is BurnerLoansTest {
    event Enabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at);

    // enable
    // given caller has the admin role
    //  when enable is called while disabled
    //   then the policy is enabled and transition time is recorded
    function test_enable_givenAdminCaller_enablesPolicyAndRecordsTransition() public {
        vm.warp(1234);
        vm.prank(admin);
        burnerLoans.disable("");

        vm.prank(admin);
        vm.expectEmit(address(burnerLoans));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit Transition(admin, true, "", 1234);
        burnerLoans.enable("");

        assertTrue(burnerLoans.isEnabled(), "enabled");
        assertEq(burnerLoans.lastTransitionAt(), 1234, "last transition");
    }

    // enable
    // given caller does not have the admin role
    //  when enable is called
    //   then it reverts
    function test_enable_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.prank(admin);
        burnerLoans.disable("");

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoans.enable("");
    }

    // enable
    // given the policy is already enabled
    //  when enable is called by admin
    //   then it reverts
    function test_enable_givenAlreadyEnabled_reverts() public {
        vm.prank(admin);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        burnerLoans.enable("");
    }
}
