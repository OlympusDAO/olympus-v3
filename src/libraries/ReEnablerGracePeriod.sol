// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/interfaces/IGracePeriod.sol";

// Contracts
import {ReEnabler} from "src/libraries/ReEnabler.sol";

/// @title ReEnablerGracePeriod
/// @notice An abstract extension of `ReEnabler` that gates `reEnable` on a fixed grace
///         window measured from the most recent transition timestamp.
/// @dev The contract exposes the configured grace window via `gracePeriod()` and wires
///      the grace check into the `_beforeReEnable` hook. Inheriting contracts that override
///      `_beforeReEnable` must call `super._beforeReEnable()` (or invoke `_requireGrace()`
///      themselves) to keep the gate.
///
///      The grace window restarts on every transition recorded by the underlying
///      `EnablerV2` state, so a fresh transition opens a new window of the same length.
abstract contract ReEnablerGracePeriod is ReEnabler, IGracePeriod {
    // ========== STATE VARIABLES ========== //

    /// @dev The grace window in seconds.
    uint32 internal immutable _GRACE;

    // ========== INITIALIZATION ========== //

    /// @notice Configures the grace window with the supplied length in seconds.
    /// @dev A zero window would prevent any grace-gated operation from succeeding and is
    ///      therefore rejected at construction time.
    ///
    ///      Reverts if:
    ///      - `p_` is zero.
    /// @param p_ The length of the grace window in seconds.
    constructor(uint32 p_) {
        if (p_ == 0) revert GracePeriod_ZeroPeriod();
        _GRACE = p_;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IGracePeriod
    /// @dev The value is set at construction time and cannot be changed afterwards, and
    ///      is the length of the window measured from `IEnablerV2.lastTransitionAt`, so a
    ///      fresh transition restarts the window at its full length.
    function gracePeriod() external view override returns (uint32 period) {
        return _GRACE;
    }

    // ========== HOOKS ========== //

    /// @inheritdoc ReEnabler
    /// @dev Asserts that the grace window since the last transition has not yet elapsed
    ///      via `_requireGrace`.
    function _beforeReEnable() internal virtual override {
        _requireGrace();
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Asserts that the grace window measured from `lastTransitionAt` has not yet
    ///         elapsed.
    /// @dev The deadline is computed as `lastTransitionAt + _GRACE`, and the check passes
    ///      when the current timestamp is less than or equal to that deadline. The
    ///      function is virtual so that inheriting contracts can extend or replace the
    ///      deadline calculation.
    ///
    ///      Reverts if:
    ///      - The current timestamp is strictly greater than the computed deadline.
    function _requireGrace() internal view virtual {
        uint48 deadline = lastTransitionAt + _GRACE;
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }

    // ========== ERC-165 ========== //

    /// @inheritdoc ReEnabler
    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IGracePeriod).interfaceId || super.supportsInterface(interfaceId_);
    }
}
