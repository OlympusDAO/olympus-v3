// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

// Contracts
import {ReEnabler} from "src/bases/ReEnabler.sol";

/// @title ReEnablerGracePeriod
/// @notice An abstract extension of `ReEnabler` that gates `reEnable` on a grace window
///         measured from the most recent transition timestamp.
/// @dev The contract exposes the configured grace window via `gracePeriod()` and wires
///      the grace check into the `_beforeReEnable` hook. Inheriting contracts that
///      override `_beforeReEnable` must call `super._beforeReEnable()` (or invoke
///      `_requireGrace()` themselves) to keep the gate.
///
///      The grace window restarts on every transition recorded by the underlying
///      `EnablerV2` state, so a fresh transition opens a new window of the same length.
///
///      The window is mutable: an authorized caller may update it after construction via
///      `setGracePeriod` while the contract is enabled. The contract is agnostic to the
///      access-control model used by the implementation, so an inheriting contract must
///      override `_authorizeSetGracePeriod` to revert when the caller is not permitted to
///      update the window. An implementation that prefers an immutable window may inherit
///      `ReEnablerGracePeriodImmutable` instead, which overrides `setGracePeriod` to
///      revert with the canonical `GracePeriod_NotConfigurable` error.
abstract contract ReEnablerGracePeriod is ReEnabler, IGracePeriod {
    // ========== STATE VARIABLES ========== //

    /// @inheritdoc IGracePeriod
    /// @dev The length of the grace window in seconds. Initialized by the constructor and
    ///      updatable through `setGracePeriod` while the contract is enabled and when the
    ///      implementation authorizes the caller.
    ///
    ///      The value is the length of the window measured from
    ///      `IEnablerV2.lastTransitionAt`, so a fresh transition restarts the window at
    ///      its full length. The value is mutable through `setGracePeriod` unless the
    ///      implementation has locked the setter.
    uint32 public override gracePeriod;

    // ========== INITIALIZATION ========== //

    /// @notice Configures the initial grace window with the supplied length in seconds.
    /// @dev The constructor routes the value through `_setGracePeriod` so that the
    ///      zero-check and the `GracePeriodSet` event share a single code path with the
    ///      external setter.
    ///
    ///      Reverts if:
    ///      - `period_` is zero.
    /// @param period_ The initial length of the grace window in seconds.
    constructor(uint32 period_) {
        _setGracePeriod(period_);
    }

    // ========== STATE-CHANGING FUNCTIONS ========== //

    /// @inheritdoc IGracePeriod
    /// @dev The function delegates the caller authorization to
    ///      `_authorizeSetGracePeriod` and the value validation plus event emission to
    ///      `_setGracePeriod`. The function is declared `virtual` so that an
    ///      implementation that wishes to lock the window after construction can
    ///      override it and revert with `GracePeriod_NotConfigurable`; see
    ///      `ReEnablerGracePeriodImmutable` for the canonical lock.
    ///
    ///      The setter is gated by `givenEnabled`, so the grace window is fixed at the
    ///      value it held when the contract was last disabled and cannot be changed while
    ///      the contract is in the disabled state.
    ///
    ///      Reverts if:
    ///      - The contract is disabled.
    ///      - `_authorizeSetGracePeriod` rejects the caller.
    ///      - `period_` is zero.
    function setGracePeriod(uint32 period_) public virtual override givenEnabled {
        _authorizeSetGracePeriod();
        _setGracePeriod(period_);
    }

    // ========== HOOKS ========== //

    /// @inheritdoc ReEnabler
    /// @dev Asserts that the grace window since the last transition has not yet elapsed
    ///      via `_requireGrace`.
    function _beforeReEnable() internal virtual override {
        _requireGrace();
    }

    /// @notice Validates that the caller is permitted to update the grace window.
    /// @dev The function is invoked from `setGracePeriod` before any state mutation. The
    ///      base contract is agnostic to the access-control model, so the inheriting
    ///      contract must implement the hook and revert when the caller is not
    ///      authorized. An implementation that overrides `setGracePeriod` to always
    ///      revert is still required to provide an implementation; reverting is the
    ///      recommended default in that case.
    ///
    ///      Reverts if:
    ///      - The caller is not authorized to update the grace window.
    function _authorizeSetGracePeriod() internal view virtual;

    // ========== INTERNAL HELPERS ========== //

    /// @notice Asserts that the grace window measured from `lastTransitionAt` has not
    ///         yet elapsed.
    /// @dev The deadline is computed as `lastTransitionAt + gracePeriod`, and the check
    ///      passes when the current timestamp is less than or equal to that deadline.
    ///      The function is virtual so that an inheriting contract can extend or replace
    ///      the deadline calculation.
    ///
    ///      Reverts if:
    ///      - The current timestamp is strictly greater than the computed deadline.
    function _requireGrace() internal view virtual {
        uint48 deadline = lastTransitionAt + gracePeriod;
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }

    /// @notice Validates the supplied window length, writes it to storage, and emits the
    ///         `GracePeriodSet` event.
    /// @dev The helper centralizes the zero-check and the event so that the constructor
    ///      and the external setter share a single code path.
    ///
    ///      Reverts if:
    ///      - `period_` is zero.
    /// @param period_ The new length of the grace window in seconds.
    function _setGracePeriod(uint32 period_) internal {
        if (period_ == 0) revert GracePeriod_ZeroPeriod();
        gracePeriod = period_;
        emit GracePeriodSet(period_);
    }

    // ========== ERC-165 ========== //

    /// @inheritdoc ReEnabler
    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IGracePeriod).interfaceId || super.supportsInterface(interfaceId_);
    }
}
