// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {EnablerV2TestBase} from "src/test/bases/EnablerV2/EnablerV2TestBase.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @dev Tests for the state-guard helpers `_requireEnabled` and
///      `_requireDisabled`, exposed via the harness as `requireEnabled` and
///      `requireDisabled`, and for the `givenEnabled` and `givenDisabled`
///      modifiers, exposed via `gatedGivenEnabled` and `gatedGivenDisabled`.
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

    // ========== givenEnabled MODIFIER ========== //

    function test_givenEnabled_doesNotRevertIfEnabled() external {
        _enableAs(caller, "");

        assertTrue(harness.gatedGivenEnabled(), "modifier passes when enabled");
    }

    function test_givenEnabled_revertsIfDisabled() external {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        harness.gatedGivenEnabled();
    }

    // ========== givenDisabled MODIFIER ========== //

    function test_givenDisabled_doesNotRevertIfDisabled() external view {
        assertTrue(harness.gatedGivenDisabled(), "modifier passes when disabled");
    }

    function test_givenDisabled_revertsIfEnabled() external {
        _enableAs(caller, "");

        vm.expectRevert(IEnabler.NotDisabled.selector);
        harness.gatedGivenDisabled();
    }
}
