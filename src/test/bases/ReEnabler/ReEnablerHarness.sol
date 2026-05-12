// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

// Contracts
import {ReEnabler} from "src/bases/ReEnabler.sol";
import {StaticCallProbe} from "src/test/bases/EnablerV2/StaticCallProbe.sol";

/// @notice Test harness exposing every internal hook of `ReEnabler` as a
///         togglable mock. Inherits the abstract base directly so that the
///         re-enable surface can be exercised in isolation. The
///         `_authorizeEnable` and `_authorizeDisable` hooks inherited from
///         `EnablerV2` are stubbed to view no-ops so that tests can drive the
///         underlying lifecycle without external authorization plumbing. The
///         `_authorizeReEnable` hook is `view` and routes through an external
///         `StaticCallProbe` so that tests can still observe its
///         invocation via `vm.expectCall`.
contract ReEnablerHarness is ReEnabler {
    // ========== ERRORS ========== //

    error MockUnauthorizedReEnable();
    error MockBeforeReEnableReverted();

    // ========== TOGGLES ========== //

    bool public authorizeReEnableShouldRevert;
    bool public beforeReEnableShouldRevert;

    // ========== INVOCATION TRACKING ========== //

    uint256 public beforeReEnableCount;

    /// @notice External probe used to make `_authorizeReEnable`
    ///         invocations observable to tests via `vm.expectCall` despite
    ///         the hook being `view`.
    StaticCallProbe public probe;

    // ========== TOGGLE SETTERS ========== //

    function setAuthorizeReEnableShouldRevert(bool v_) external {
        authorizeReEnableShouldRevert = v_;
    }

    function setBeforeReEnableShouldRevert(bool v_) external {
        beforeReEnableShouldRevert = v_;
    }

    function setProbe(StaticCallProbe probe_) external {
        probe = probe_;
    }

    // ========== HOOK OVERRIDES ========== //

    function _authorizeEnable(bytes calldata) internal view override {}

    function _authorizeDisable(bytes calldata) internal view override {}

    function _authorizeReEnable() internal view override {
        if (address(probe) != address(0)) probe.note();
        if (authorizeReEnableShouldRevert) revert MockUnauthorizedReEnable();
    }

    function _beforeReEnable() internal override {
        ++beforeReEnableCount;
        if (beforeReEnableShouldRevert) revert MockBeforeReEnableReverted();
    }
}

/// @notice Companion harness that intentionally does not override
///         `_beforeReEnable`, so the default no-op implementation in
///         `ReEnabler` is the one that runs. Used to confirm that the
///         default body is reachable on the standard happy path.
contract ReEnablerDefaultBeforeHarness is ReEnabler {
    function _authorizeEnable(bytes calldata) internal view override {}

    function _authorizeDisable(bytes calldata) internal view override {}

    function _authorizeReEnable() internal view override {}
}
