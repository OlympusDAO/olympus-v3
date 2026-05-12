// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import {PolicyEnablerV2TestBase} from "src/test/policies/utils/PolicyEnablerV2/PolicyEnablerV2TestBase.sol";
import {MockPolicyEnablerV2} from "src/test/policies/utils/PolicyEnablerV2/MockPolicyEnablerV2.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

/// @dev Tests for `PolicyEnablerV2.disable`. The role gate is the
///      `onlyEmergencyOrAdminRole` modifier, which permits both the admin
///      and the emergency role and rejects any other caller with the
///      `NotAuthorised` error.
contract PolicyEnablerV2Tests_Disable is PolicyEnablerV2TestBase {
    bytes internal constant SAMPLE_DATA = hex"cafef00d";

    // ========== SUCCESS ========== //

    function test_disable_succeedsForAdmin() external givenEnabled {
        vm.expectEmit(true, true, true, true, address(policy));
        emit Disabled();
        vm.expectEmit(true, true, true, true, address(policy));
        emit Transition(admin, false, SAMPLE_DATA, uint48(block.timestamp));

        vm.prank(admin);
        policy.disable(SAMPLE_DATA);

        assertFalse(policy.isEnabled(), "isEnabled false");
        assertEq(policy.lastTransitionAt(), uint48(block.timestamp), "lastTransitionAt refreshed");
        assertEq(policy.lastBeforeDisableData(), SAMPLE_DATA, "data forwarded to before hook");
    }

    function test_disable_succeedsForEmergency() external givenEnabled {
        vm.expectEmit(true, true, true, true, address(policy));
        emit Disabled();
        vm.expectEmit(true, true, true, true, address(policy));
        emit Transition(emergency, false, SAMPLE_DATA, uint48(block.timestamp));

        vm.prank(emergency);
        policy.disable(SAMPLE_DATA);

        assertFalse(policy.isEnabled(), "isEnabled false");
    }

    function test_disable_succeedsForEmergencyWithEmptyData() external givenEnabled {
        vm.prank(emergency);
        policy.disable("");

        assertFalse(policy.isEnabled(), "isEnabled false");
        assertEq(policy.lastBeforeDisableData(), "", "empty data forwarded");
    }

    // ========== REVERTS ========== //

    function test_disable_revertsIfCurrentlyDisabled() external {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(emergency);
        policy.disable(SAMPLE_DATA);
    }

    function test_disable_revertsIfCallerIsManager() external givenEnabled {
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(manager);
        policy.disable(SAMPLE_DATA);
    }

    function test_disable_revertsIfCustomLogicReverts() external givenEnabled {
        policy.setBeforeDisableShouldRevert(true);

        vm.expectRevert(MockPolicyEnablerV2.MockBeforeDisableReverted.selector);
        vm.prank(admin);
        policy.disable(SAMPLE_DATA);

        assertTrue(policy.isEnabled(), "state untouched on revert");
    }

    // ========== REVERTS - FUZZ ========== //

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_disable_revertsIfNotAdminOrEmergency(address caller_) external givenEnabled {
        vm.assume(caller_ != admin && caller_ != emergency);

        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        policy.disable(SAMPLE_DATA);
    }
}
