// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {StaticCallProbe} from "src/test/bases/EnablerV2/StaticCallProbe.sol";

/// @notice Test harness exposing every internal hook of `EnablerV2` as a
///         togglable mock. Inherits the abstract base directly so that the
///         `EnablerV2` surface can be exercised in isolation from any
///         policy-specific role plumbing. The `_before*` hooks track their
///         invocation count and received data; the `_authorize*` hooks are
///         `view` and therefore route through an external `StaticCallProbe`
///         so that tests can still observe their invocation via
///         `vm.expectCall`. Every hook exposes a `setXShouldRevert` knob that
///         flips it into the revert branch with a dedicated custom error so
///         tests can match on the exact selector.
contract EnablerV2Harness is EnablerV2 {
    // ========== ERRORS ========== //

    error MockUnauthorizedEnable();
    error MockUnauthorizedDisable();
    error MockBeforeEnableReverted();
    error MockBeforeDisableReverted();

    // ========== TOGGLES ========== //

    bool public authorizeEnableShouldRevert;
    bool public authorizeDisableShouldRevert;
    bool public beforeEnableShouldRevert;
    bool public beforeDisableShouldRevert;

    // ========== INVOCATION TRACKING ========== //

    bytes public lastBeforeEnableData;
    bytes public lastBeforeDisableData;

    uint256 public beforeEnableCount;
    uint256 public beforeDisableCount;

    /// @notice External probe used to make `_authorize*` invocations
    ///         observable to tests via `vm.expectCall`. The hooks read this
    ///         storage slot and forward to the probe under STATICCALL
    ///         semantics; tests install an instance via `setProbe`.
    StaticCallProbe public probe;

    // ========== TOGGLE SETTERS ========== //

    function setAuthorizeEnableShouldRevert(bool v_) external {
        authorizeEnableShouldRevert = v_;
    }

    function setAuthorizeDisableShouldRevert(bool v_) external {
        authorizeDisableShouldRevert = v_;
    }

    function setBeforeEnableShouldRevert(bool v_) external {
        beforeEnableShouldRevert = v_;
    }

    function setBeforeDisableShouldRevert(bool v_) external {
        beforeDisableShouldRevert = v_;
    }

    function setProbe(StaticCallProbe probe_) external {
        probe = probe_;
    }

    // ========== HOOK OVERRIDES ========== //

    function _authorizeEnable(bytes calldata) internal view override {
        if (address(probe) != address(0)) probe.note();
        if (authorizeEnableShouldRevert) revert MockUnauthorizedEnable();
    }

    function _authorizeDisable(bytes calldata) internal view override {
        if (address(probe) != address(0)) probe.note();
        if (authorizeDisableShouldRevert) revert MockUnauthorizedDisable();
    }

    function _beforeEnable(bytes calldata data_) internal override {
        ++beforeEnableCount;
        lastBeforeEnableData = data_;
        if (beforeEnableShouldRevert) revert MockBeforeEnableReverted();
    }

    function _beforeDisable(bytes calldata data_) internal override {
        ++beforeDisableCount;
        lastBeforeDisableData = data_;
        if (beforeDisableShouldRevert) revert MockBeforeDisableReverted();
    }

    // ========== EXTERNAL TRAMPOLINES ========== //

    /// @notice External pass-through to `_requireEnabled`.
    function requireEnabled() external view {
        _requireEnabled();
    }

    /// @notice External pass-through to `_requireDisabled`.
    function requireDisabled() external view {
        _requireDisabled();
    }

    /// @notice Trivial gated function that exercises the `givenEnabled` modifier.
    function gatedGivenEnabled() external view givenEnabled returns (bool) {
        return true;
    }

    /// @notice Trivial gated function that exercises the `givenDisabled` modifier.
    function gatedGivenDisabled() external view givenDisabled returns (bool) {
        return true;
    }
}
