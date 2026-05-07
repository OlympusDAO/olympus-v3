// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Contracts
import {ReEnablerGracePeriod} from "src/libraries/ReEnablerGracePeriod.sol";

/// @notice Test harness exposing `_requireGrace` of `ReEnablerGracePeriod` as an external
///         pass-through. The `_authorizeEnable`, `_authorizeDisable`, and
///         `_authorizeReEnable` hooks are stubbed to no-ops so that tests can drive the
///         underlying `EnablerV2`/`ReEnabler` lifecycle without external authorization
///         plumbing.
contract ReEnablerGracePeriodHarness is ReEnablerGracePeriod {
    constructor(uint32 p_) ReEnablerGracePeriod(p_) {}

    function _authorizeEnable(bytes calldata) internal override {}

    function _authorizeDisable(bytes calldata) internal override {}

    function _authorizeReEnable() internal override {}

    /// @notice External pass-through to `_requireGrace`.
    function requireGrace() external view {
        _requireGrace();
    }
}
