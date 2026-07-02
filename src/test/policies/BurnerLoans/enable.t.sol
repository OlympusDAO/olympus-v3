// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansEnableTest is BurnerLoansTest {
    function test_enable_givenAdminCaller_enablesPolicyAndRecordsTransition() public {
        vm.warp(1234);
        vm.prank(admin);
        burnerLoans.enable("");

        assertTrue(burnerLoans.isEnabled(), "enabled");
        assertEq(burnerLoans.lastTransitionAt(), 1234, "last transition");
    }

    function test_enable_givenNonAdminCaller_reverts() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoans.enable("");
    }

    function test_disable_givenEmergencyCaller_disablesPolicy() public {
        vm.prank(admin);
        burnerLoans.enable("");

        vm.warp(2345);
        vm.prank(emergency);
        burnerLoans.disable("");

        assertFalse(burnerLoans.isEnabled(), "enabled");
        assertEq(burnerLoans.lastTransitionAt(), 2345, "last transition");
    }

    function test_disable_givenAdminCaller_disablesPolicy() public {
        vm.prank(admin);
        burnerLoans.enable("");

        vm.prank(admin);
        burnerLoans.disable("");

        assertFalse(burnerLoans.isEnabled(), "enabled");
    }

    function test_disable_givenNonAdminAndNonEmergencyCaller_reverts() public {
        vm.prank(admin);
        burnerLoans.enable("");

        vm.prank(unauthorized);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        burnerLoans.disable("");
    }

    function test_enable_givenAlreadyEnabled_reverts() public {
        vm.prank(admin);
        burnerLoans.enable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        burnerLoans.enable("");
    }

    function test_disable_givenAlreadyDisabled_reverts() public {
        vm.prank(emergency);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.disable("");
    }

    function test_disable_givenEmergencyRoleIsRequiredOnlyForDisable() public {
        vm.prank(emergency);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoans.enable("");

        vm.prank(admin);
        burnerLoans.enable("");

        vm.prank(emergency);
        burnerLoans.disable("");

        assertFalse(burnerLoans.isEnabled(), "enabled");
        assertTrue(roles.hasRole(emergency, EMERGENCY_ROLE), "emergency role");
    }

    function test_borrow_givenDisabled_revertsBeforePlaceholder() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, alice, 0);
    }

    function test_extend_givenDisabled_revertsBeforePlaceholder() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.extend(address(usds), alice, 1, 0);
    }

    function test_repay_givenDisabled_reachesPlaceholder() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_NotImplemented.selector);
        burnerLoans.repay(address(usds), 1e9, alice);
    }

    function test_seize_givenDisabled_reachesPlaceholder() public {
        address[] memory borrowers = new address[](1);
        borrowers[0] = alice;

        vm.expectRevert(IBurnerLoans.BurnerLoans_NotImplemented.selector);
        burnerLoans.seize(address(usds), borrowers);
    }
}
