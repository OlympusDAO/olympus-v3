// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {EnablerV2TestBase} from "src/test/libraries/EnablerV2/EnablerV2TestBase.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @dev Tests for the state-guard helpers `_requireEnabled` and
///      `_requireDisabled`, exposed via the harness as `requireEnabled` and
///      `requireDisabled`, and for the `whenEnabled` and `whenDisabled`
///      modifiers, exposed via `gatedWhenEnabled` and `gatedWhenDisabled`.
contract EnablerV2Tests_StateGuards is EnablerV2TestBase {
    // ========== _requireEnabled ========== //

    function test_requireEnabled_doesNotRevertIfEnabled() external {
        _enableAs(caller, "");

        harness.requireEnabled();
    }

    function test_requireEnabled_revertsIfDisabled() external {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        harness.requireEnabled();
    }

    // ========== _requireDisabled ========== //

    function test_requireDisabled_doesNotRevertIfDisabled() external view {
        harness.requireDisabled();
    }

    function test_requireDisabled_revertsIfEnabled() external {
        _enableAs(caller, "");

        vm.expectRevert(IEnabler.NotDisabled.selector);
        harness.requireDisabled();
    }

    // ========== whenEnabled MODIFIER ========== //

    function test_whenEnabled_doesNotRevertIfEnabled() external {
        _enableAs(caller, "");

        assertTrue(harness.gatedWhenEnabled(), "modifier passes when enabled");
    }

    function test_whenEnabled_revertsIfDisabled() external {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        harness.gatedWhenEnabled();
    }

    // ========== whenDisabled MODIFIER ========== //

    function test_whenDisabled_doesNotRevertIfDisabled() external view {
        assertTrue(harness.gatedWhenDisabled(), "modifier passes when disabled");
    }

    function test_whenDisabled_revertsIfEnabled() external {
        _enableAs(caller, "");

        vm.expectRevert(IEnabler.NotDisabled.selector);
        harness.gatedWhenDisabled();
    }
}
