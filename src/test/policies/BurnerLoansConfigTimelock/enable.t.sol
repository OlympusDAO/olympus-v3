// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockEnableTest is BurnerLoansConfigTimelockTest {
    event Enabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at);

    // enable
    // given the timelock is disabled and caller has admin
    //  when enable is called
    //   then it enables the policy and records the transition
    function test_givenAdminCaller_enablesPolicyAndRecordsTransition() public {
        vm.prank(emergency);
        configTimelock.disable("");
        vm.warp(1_234);

        vm.prank(admin);
        vm.expectEmit(address(configTimelock));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit Transition(admin, true, "", 1_234);
        configTimelock.enable("");

        assertTrue(configTimelock.isEnabled(), "enabled");
        assertEq(configTimelock.lastTransitionAt(), 1_234, "last transition");
    }

    // enable
    // given the timelock is disabled and caller lacks admin
    //  when enable is called
    //   then it reverts
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.prank(emergency);
        configTimelock.disable("");

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        configTimelock.enable("");
    }

    // enable
    // given the timelock is already enabled
    //  when admin calls enable
    //   then it reverts
    function test_givenAlreadyEnabled_reverts() public {
        vm.prank(admin);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        configTimelock.enable("");
    }
}
