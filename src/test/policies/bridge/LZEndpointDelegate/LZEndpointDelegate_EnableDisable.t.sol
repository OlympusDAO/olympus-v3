// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZEndpointDelegateTestBase} from "src/test/policies/bridge/LZEndpointDelegate/LZEndpointDelegateTestBase.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Enable/disable lifecycle for the LZEndpointDelegate policy.
contract LZEndpointDelegateTests_EnableDisable is LZEndpointDelegateTestBase {
    // ========= ENABLE ========= //

    function test_enable() external {
        _disableDelegate();
        assertFalse(lzDelegate.isEnabled(), "Should be disabled");

        vm.prank(admin);
        lzDelegate.enable(bytes(""));
        assertTrue(lzDelegate.isEnabled(), "Should be enabled");
    }

    function test_enable_updatesLastTransitionAt() external {
        _disableDelegate();
        uint48 disabledAt = lzDelegate.lastTransitionAt();
        assertGt(uint256(disabledAt), 0, "lastTransitionAt should be non-zero after disable");

        vm.warp(vm.getBlockTimestamp() + 30);

        vm.prank(admin);
        lzDelegate.enable(bytes(""));
        assertEq(
            uint256(lzDelegate.lastTransitionAt()),
            uint256(uint48(vm.getBlockTimestamp())),
            "lastTransitionAt should be refreshed on enable"
        );
    }

    function test_enable_emitsTransitionEvent() external {
        _disableDelegate();

        vm.expectEmit(true, true, false, true);
        emit IEnablerV2.Transition(admin, true, bytes(""), uint48(vm.getBlockTimestamp()));
        vm.prank(admin);
        lzDelegate.enable(bytes(""));
    }

    function test_enable_revertsIfAlreadyEnabled() external {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
        vm.prank(admin);
        lzDelegate.enable(bytes(""));
    }

    function testFuzz_enable_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);
        _disableDelegate();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        lzDelegate.enable(bytes(""));
    }

    // ========= DISABLE ========= //

    function test_disable_adminCanCall() external {
        assertTrue(lzDelegate.isEnabled(), "Should be enabled after setUp");

        vm.prank(admin);
        lzDelegate.disable(bytes(""));
        assertFalse(lzDelegate.isEnabled(), "Should be disabled");
    }

    function test_disable_emergencyCanCall() external {
        assertTrue(lzDelegate.isEnabled(), "Should be enabled after setUp");

        vm.prank(emergency);
        lzDelegate.disable(bytes(""));
        assertFalse(lzDelegate.isEnabled(), "Should be disabled");
    }

    function test_disable_updatesLastTransitionAt() external {
        vm.warp(vm.getBlockTimestamp() + 60);

        vm.prank(emergency);
        lzDelegate.disable(bytes(""));
        assertEq(
            uint256(lzDelegate.lastTransitionAt()),
            uint256(uint48(vm.getBlockTimestamp())),
            "lastTransitionAt should be refreshed on disable"
        );
    }

    function test_disable_emitsTransitionEvent() external {
        vm.expectEmit(true, true, false, true);
        emit IEnablerV2.Transition(emergency, false, bytes(""), uint48(vm.getBlockTimestamp()));
        vm.prank(emergency);
        lzDelegate.disable(bytes(""));
    }

    function test_disable_revertsIfAlreadyDisabled() external {
        _disableDelegate();

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(admin);
        lzDelegate.disable(bytes(""));
    }

    function testFuzz_disable_revertsIfNotAdminOrEmergency(address caller_) external {
        vm.assume(caller_ != admin && caller_ != emergency);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        lzDelegate.disable(bytes(""));
    }
}
