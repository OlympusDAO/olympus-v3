// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @title IEnablerV2
/// @notice The external interface of an enableable contract that augments `IEnabler`
///         with a per-transition event and a timestamp of the most recent transition.
/// @dev The wire-level surface of `IEnabler` is preserved, so callers that target
///      the legacy interface can continue to invoke `enable` and `disable` and
///      observe `Enabled` and `Disabled` events without modification. The `Transition`
///      event is emitted alongside the legacy events on every successful transition,
///      and provides the caller, the direction, the calldata payload, and the
///      timestamp at which the transition was applied.
interface IEnablerV2 is IEnabler {
    // ========== EVENTS ========== //

    /// @notice Emitted when the contract transitions between the enabled and disabled states.
    /// @dev The event is emitted in addition to the legacy `Enabled` and `Disabled` events,
    ///      so off-chain consumers may rely on either surface. The `data` field is the
    ///      raw calldata payload passed to `enable` or `disable`.
    /// @param by The address that initiated the transition.
    /// @param enable True when the transition is from disabled to enabled, false otherwise.
    /// @param data The calldata payload supplied to the transition entry point.
    /// @param at The timestamp at which the transition was applied.
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the timestamp of the most recent transition between the enabled and
    ///         disabled states.
    /// @return at The timestamp of the most recent transition, or zero before the first enable.
    function lastTransitionAt() external view returns (uint48 at);
}
