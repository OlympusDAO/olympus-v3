// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

// Contracts
import {EnablerV2} from "src/libraries/EnablerV2.sol";

/// @notice Test harness exposing every internal hook of `EnablerV2` as a
///         togglable mock. Inherits the abstract base directly so that the
///         `EnablerV2` surface can be exercised in isolation from any
///         policy-specific role plumbing. Each hook tracks its invocation
///         count and the data it received, and exposes a `setXShouldRevert`
///         knob that flips the hook into the revert branch with a dedicated
///         custom error so tests can match on the exact selector.
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

    uint256 public authorizeEnableCount;
    uint256 public authorizeDisableCount;
    uint256 public beforeEnableCount;
    uint256 public beforeDisableCount;

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

    // ========== HOOK OVERRIDES ========== //

    function _authorizeEnable(bytes calldata) internal override {
        ++authorizeEnableCount;
        if (authorizeEnableShouldRevert) revert MockUnauthorizedEnable();
    }

    function _authorizeDisable(bytes calldata) internal override {
        ++authorizeDisableCount;
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

    /// @notice Trivial gated function that exercises the `whenEnabled` modifier.
    function gatedWhenEnabled() external view whenEnabled returns (bool) {
        return true;
    }

    /// @notice Trivial gated function that exercises the `whenDisabled` modifier.
    function gatedWhenDisabled() external view whenDisabled returns (bool) {
        return true;
    }
}
