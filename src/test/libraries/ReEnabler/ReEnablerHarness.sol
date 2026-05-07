// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

// Contracts
import {ReEnabler} from "src/libraries/ReEnabler.sol";

/// @notice Test harness exposing every internal hook of `ReEnabler` as a
///         togglable mock. Inherits the abstract base directly so that the
///         re-enable surface can be exercised in isolation. The
///         `_authorizeEnable` and `_authorizeDisable` hooks inherited from
///         `EnablerV2` are stubbed to no-ops so that tests can drive the
///         underlying lifecycle without external authorization plumbing.
contract ReEnablerHarness is ReEnabler {
    // ========== ERRORS ========== //

    error MockUnauthorizedReEnable();
    error MockBeforeReEnableReverted();

    // ========== TOGGLES ========== //

    bool public authorizeReEnableShouldRevert;
    bool public beforeReEnableShouldRevert;

    // ========== INVOCATION TRACKING ========== //

    uint256 public authorizeReEnableCount;
    uint256 public beforeReEnableCount;

    // ========== TOGGLE SETTERS ========== //

    function setAuthorizeReEnableShouldRevert(bool v_) external {
        authorizeReEnableShouldRevert = v_;
    }

    function setBeforeReEnableShouldRevert(bool v_) external {
        beforeReEnableShouldRevert = v_;
    }

    // ========== HOOK OVERRIDES ========== //

    function _authorizeEnable(bytes calldata) internal override {}

    function _authorizeDisable(bytes calldata) internal override {}

    function _authorizeReEnable() internal override {
        ++authorizeReEnableCount;
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
    function _authorizeEnable(bytes calldata) internal override {}

    function _authorizeDisable(bytes calldata) internal override {}

    function _authorizeReEnable() internal override {}
}
