// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";

// Contracts
import {ERC165, IERC165} from "@openzeppelin-5.3.0/utils/introspection/ERC165.sol";

/// @title EnablerV2
/// @notice An abstract base contract that implements `IEnablerV2` and exposes
///         authorization and lifecycle hooks for inheriting contracts.
/// @dev The contract is agnostic to the access control model used by the
///      implementation. Inheriting contracts must override `_authorizeEnable`
///      and `_authorizeDisable` to revert when the caller is not permitted to
///      perform the requested transition, and may override `_beforeEnable` and
///      `_beforeDisable` to perform implementation-specific state changes
///      alongside the transition.
///
///     The legacy `IEnabler` surface is preserved: `enable` and `disable`
///     retain their selectors and payload semantics, and the `Enabled` and
///     `Disabled` events are emitted in addition to the new `Transition` event
///     on every successful transition. Storage layout is intentionally compact:
///     `isEnabled` and `lastTransitionAt` share a single slot.
abstract contract EnablerV2 is IEnablerV2, ERC165 {
    // ========== STATE VARIABLES ========== //

    /// @inheritdoc IEnabler
    /// @dev The flag is initialized to false at construction time, so a freshly
    ///      deployed contract always starts in the disabled state and must be
    ///      explicitly enabled before its gated functionality becomes available.
    bool public override isEnabled;

    /// @inheritdoc IEnablerV2
    /// @dev The value remains zero until the first successful `enable`, after
    ///      which it tracks the timestamp of the most recent transition.
    ///      The field is packed into the same storage slot as `isEnabled`.
    uint48 public override lastTransitionAt;

    // ========== INITIALIZATION ========== //

    constructor() {
        // The contract is disabled at construction time and `lastTransitionAt`
        // stays at zero until the first successful `enable`.
    }

    // ========== STATE-CHANGING FUNCTIONS ========== //

    /// @inheritdoc IEnabler
    /// @dev On success, the contract is moved to the enabled state,
    ///      `lastTransitionAt` is updated to the current timestamp, and both
    ///      the legacy `Enabled` event and the `Transition` event are emitted.
    ///
    ///      Reverts if:
    ///      - The contract is currently enabled.
    ///      - `_authorizeEnable` rejects the caller.
    ///      - `_beforeEnable` reverts.
    function enable(bytes calldata data_) public virtual override givenDisabled {
        _authorizeEnable(data_);
        _beforeEnable(data_);
        isEnabled = true;
        lastTransitionAt = _getBlockTimestamp();
        emit Enabled();
        emit Transition(msg.sender, true, data_, _getBlockTimestamp());
    }

    /// @inheritdoc IEnabler
    /// @dev On success, the contract is moved to the disabled state,
    ///      `lastTransitionAt` is updated to the current timestamp, and both
    ///      the legacy `Disabled` event and the `Transition` event are emitted.
    ///
    ///      Reverts if:
    ///      - The contract is currently disabled.
    ///      - `_authorizeDisable` rejects the caller.
    ///      - `_beforeDisable` reverts.
    function disable(bytes calldata data_) public virtual override givenEnabled {
        _authorizeDisable(data_);
        _beforeDisable(data_);
        isEnabled = false;
        lastTransitionAt = _getBlockTimestamp();
        emit Disabled();
        emit Transition(msg.sender, false, data_, _getBlockTimestamp());
    }

    // ========== HOOKS ========== //

    /// @notice Validates that the caller is permitted to enable the contract.
    /// @dev The function is invoked from `enable` before any state mutation.
    ///      The `data_` payload is forwarded unchanged so that authorization
    ///      may depend on the contents of the call.
    ///
    ///      Reverts if:
    ///      - The caller is not authorized to perform the enable.
    /// @param data_ The calldata payload passed to `enable`.
    function _authorizeEnable(bytes calldata data_) internal view virtual;

    /// @notice Validates that the caller is permitted to disable the contract.
    /// @dev The function is invoked from `disable` before any state mutation.
    ///      The `data_` payload is forwarded unchanged so that authorization
    ///      may depend on the contents of the call.
    ///
    ///      Reverts if:
    ///      - The caller is not authorized to perform the disable.
    /// @param data_ The calldata payload passed to `disable`.
    function _authorizeDisable(bytes calldata data_) internal view virtual;

    /// @notice Performs implementation-specific state changes that must run
    ///         immediately before the contract is moved to the enabled state.
    /// @dev The function is invoked from `enable` after `_authorizeEnable`
    ///      succeeds and before `isEnabled` is updated. The default
    ///      implementation is a no-op.
    /// @param data_ The calldata payload passed to `enable`.
    function _beforeEnable(bytes calldata data_) internal virtual {}

    /// @notice Performs implementation-specific state changes that must run
    ///         immediately before the contract is moved to the disabled state.
    /// @dev The function is invoked from `disable` after `_authorizeDisable`
    ///      succeeds and before `isEnabled` is updated. The default
    ///      implementation is a no-op.
    /// @param data_ The calldata payload passed to `disable`.
    function _beforeDisable(bytes calldata data_) internal virtual {}

    // ========== INTERNAL HELPERS ========== //

    /// @notice Asserts that the contract is currently enabled.
    /// @dev The check is exposed as a function so that inheriting contracts
    ///      can compose it without using a modifier.
    ///
    ///      Reverts if:
    ///      - The contract is currently disabled.
    function _requireEnabled() internal view {
        if (!isEnabled) revert NotEnabled();
    }

    /// @notice Modifier that reverts when the contract is not currently enabled.
    modifier givenEnabled() {
        _requireEnabled();
        _;
    }

    /// @notice Asserts that the contract is currently disabled.
    /// @dev The check is exposed as a function so that inheriting contracts
    ///      can compose it without using a modifier.
    ///
    ///      Reverts if:
    ///      - The contract is currently enabled.
    function _requireDisabled() internal view {
        if (isEnabled) revert NotDisabled();
    }

    /// @notice Modifier that reverts when the contract is currently enabled.
    modifier givenDisabled() {
        _requireDisabled();
        _;
    }

    /// @notice Returns the current block timestamp narrowed to `uint48`.
    /// @dev The function is exposed as a virtual hook so that test doubles can
    ///      override the source of time without modifying the implementation.
    /// @return timestamp The current block timestamp.
    function _getBlockTimestamp() internal view virtual returns (uint48 timestamp) {
        return uint48(block.timestamp);
    }

    // ========== ERC-165 ========== //

    /// @inheritdoc IERC165
    /// @dev The contract advertises support for `IEnablerV2`, the legacy
    ///      `IEnabler`, and any interface advertised by the parent
    ///      `ERC165` implementation. Extension mixins are expected to
    ///      override this function and add their own interface identifiers.
    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IEnablerV2).interfaceId ||
            interfaceId_ == type(IEnabler).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
