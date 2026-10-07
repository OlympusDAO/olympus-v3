// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {PolicyEnablerV2TestBase} from "src/test/policies/utils/PolicyEnablerV2/PolicyEnablerV2TestBase.sol";
import {MockPolicyEnablerV2} from "src/test/policies/utils/PolicyEnablerV2/MockPolicyEnablerV2.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @dev Tests for `PolicyEnablerV2.enable`. The role gate restricts access
///      to the admin role; the emergency, manager, and random callers must
///      all be rejected.
contract PolicyEnablerV2Tests_Enable is PolicyEnablerV2TestBase {
    bytes internal constant SAMPLE_DATA = hex"deadbeef";

    // ========== SUCCESS ========== //

    function test_enable_succeedsForAdmin() external {
        vm.expectEmit(true, true, true, true, address(policy));
        emit Enabled();
        vm.expectEmit(true, true, true, true, address(policy));
        emit Transition(admin, true, SAMPLE_DATA, uint48(vm.getBlockTimestamp()));

        vm.prank(admin);
        policy.enable(SAMPLE_DATA);

        assertTrue(policy.isEnabled(), "isEnabled true");
        assertEq(
            policy.lastTransitionAt(),
            uint48(vm.getBlockTimestamp()),
            "lastTransitionAt refreshed"
        );
        assertEq(policy.lastBeforeEnableData(), SAMPLE_DATA, "data forwarded to before hook");
    }

    function test_enable_succeedsForAdminWithEmptyData() external {
        vm.prank(admin);
        policy.enable("");

        assertTrue(policy.isEnabled(), "isEnabled true");
        assertEq(policy.lastBeforeEnableData(), "", "empty data forwarded");
    }

    // ========== REVERTS ========== //

    function test_enable_revertsIfCurrentlyEnabled() external givenEnabled {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(admin);
        policy.enable(SAMPLE_DATA);
    }

    function test_enable_revertsIfCallerIsEmergency() external {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(emergency);
        policy.enable(SAMPLE_DATA);
    }

    function test_enable_revertsIfCallerIsManager() external {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(manager);
        policy.enable(SAMPLE_DATA);
    }

    function test_enable_revertsIfCustomLogicReverts() external {
        policy.setBeforeEnableShouldRevert(true);

        vm.expectRevert(MockPolicyEnablerV2.MockBeforeEnableReverted.selector);
        vm.prank(admin);
        policy.enable(SAMPLE_DATA);

        assertFalse(policy.isEnabled(), "state untouched on revert");
    }

    // ========== REVERTS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_enable_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        policy.enable(SAMPLE_DATA);
    }
}
