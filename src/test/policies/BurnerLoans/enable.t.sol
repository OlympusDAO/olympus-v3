// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
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

    // borrow
    // given the policy is disabled
    //  when borrow is called
    //   then it reverts before reaching the placeholder implementation
    function test_borrow_givenDisabled_revertsBeforePlaceholder() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, alice, 0);
    }

    // extend
    // given the policy is disabled
    //  when extend is called
    //   then it reverts before reaching the placeholder implementation
    function test_extend_givenDisabled_revertsBeforePlaceholder() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.extend(address(usds), alice, 1, 0);
    }

    // repay
    // given the policy is disabled
    //  when repay is called
    //   then it reaches the placeholder implementation
    function test_repay_givenDisabled_reachesPlaceholder() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectRevert(IBurnerLoans.BurnerLoans_NotImplemented.selector);
        burnerLoans.repay(address(usds), 1e9, alice);
    }

    // seize
    // given the policy is disabled
    //  when seize is called
    //   then it reaches the placeholder implementation
    function test_seize_givenDisabled_reachesPlaceholder() public {
        address[] memory borrowers = new address[](1);
        borrowers[0] = alice;
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectRevert(IBurnerLoans.BurnerLoans_NotImplemented.selector);
        burnerLoans.seize(address(usds), borrowers);
    }
}
