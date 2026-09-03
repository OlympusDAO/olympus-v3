// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// Contracts
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";

/// @notice The test harness exposing `_requireGrace` of `ReEnablerGracePeriod` as an
///         external pass-through. The `_authorizeEnable`, `_authorizeDisable`,
///         `_authorizeReEnable`, and `_authorizeSetGracePeriod` hooks are stubbed to
///         no-ops so that the tests can drive the underlying `EnablerV2`/`ReEnabler`
///         lifecycle and the grace-period setter without any external authorisation
///         plumbing.
contract ReEnablerGracePeriodHarness is ReEnablerGracePeriod {
    constructor(uint32 period_) ReEnablerGracePeriod(period_) {}

    function _authorizeEnable(bytes calldata) internal view override {}

    function _authorizeDisable(bytes calldata) internal view override {}

    function _authorizeReEnable() internal view override {}

    function _authorizeSetGracePeriod() internal view override {}

    /// @notice The external pass-through to `_requireGrace`.
    function requireGrace() external view {
        _requireGrace();
    }
}
