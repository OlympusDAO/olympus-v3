// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import {PolicyReEnablerTestBase} from "src/test/policies/utils/PolicyReEnabler/PolicyReEnablerTestBase.sol";
import {MockPolicyReEnabler} from "src/test/policies/utils/PolicyReEnabler/MockPolicyReEnabler.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IReEnabler} from "src/interfaces/IReEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

import {MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @dev Tests for `PolicyReEnabler.reEnable`. The role gate is the
///      `onlyManagerRole` modifier, which permits only the manager role and
///      rejects every other caller, including the admin and the emergency
///      role, with `ROLES_RequireRole("manager")`.
contract PolicyReEnablerTests_ReEnable is PolicyReEnablerTestBase {
    // ========== SUCCESS ========== //

    function test_reEnable_succeedsForManager() external givenEnabledThenDisabled {
        skip(123);

        vm.expectEmit(true, true, true, true, address(policy));
        emit Enabled();
        vm.expectEmit(true, true, true, true, address(policy));
        emit Transition(manager, true, "", uint48(block.timestamp));

        vm.prank(manager);
        policy.reEnable();

        assertTrue(policy.isEnabled(), "isEnabled true");
        assertEq(policy.lastTransitionAt(), uint48(block.timestamp), "lastTransitionAt refreshed");
        assertEq(policy.reEnableCount(), 1, "before-reEnable hook invoked");
    }

    function test_reEnable_succeedsForManagerAcrossMultipleCycles() external {
        vm.prank(admin);
        policy.enable("");
        vm.prank(emergency);
        policy.disable("");

        skip(100);
        vm.prank(manager);
        policy.reEnable();
        assertTrue(policy.isEnabled(), "first re-enable");

        skip(100);
        vm.prank(emergency);
        policy.disable("");

        skip(100);
        vm.prank(manager);
        policy.reEnable();
        assertTrue(policy.isEnabled(), "second re-enable");
        assertEq(policy.reEnableCount(), 2, "before-reEnable hook invoked twice");
    }

    // ========== REVERTS ========== //

    function test_reEnable_revertsIfNeverEnabled() external {
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(manager);
        policy.reEnable();
    }

    function test_reEnable_revertsIfCurrentlyEnabled() external {
        vm.prank(admin);
        policy.enable("");

        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(manager);
        policy.reEnable();
    }

    function test_reEnable_revertsIfCallerIsAdmin() external givenEnabledThenDisabled {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, MANAGER_ROLE));
        vm.prank(admin);
        policy.reEnable();
    }

    function test_reEnable_revertsIfCallerIsEmergency() external givenEnabledThenDisabled {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, MANAGER_ROLE));
        vm.prank(emergency);
        policy.reEnable();
    }

    function test_reEnable_revertsIfCustomLogicReverts() external givenEnabledThenDisabled {
        uint48 atDisable = policy.lastTransitionAt();

        policy.setBeforeReEnableShouldRevert(true);

        vm.expectRevert(MockPolicyReEnabler.MockBeforeReEnableReverted.selector);
        vm.prank(manager);
        policy.reEnable();

        assertFalse(policy.isEnabled(), "still disabled");
        assertEq(policy.lastTransitionAt(), atDisable, "lastTransitionAt unchanged");
    }

    // ========== REVERTS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_reEnable_revertsIfNotManager(
        address caller_
    ) external givenEnabledThenDisabled {
        vm.assume(caller_ != manager);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, MANAGER_ROLE));
        vm.prank(caller_);
        policy.reEnable();
    }
}
