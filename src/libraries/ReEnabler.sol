// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

// Interfaces
import {IEnablerV2ReEnable} from "src/interfaces/IEnablerV2ReEnable.sol";

// Contracts
import {EnablerV2} from "src/libraries/EnablerV2.sol";

/// @title ReEnabler
/// @notice An abstract extension of `EnablerV2` that adds a parameterless
///         `reEnable` entry point intended for callers that should be able to
///         return the contract to the enabled state without the calldata
///         payload required by the standard `enable`.
/// @dev Inheriting contracts must override `_authorizeReEnable` to revert when
///      the caller is not permitted to perform the re-enable.
///
///      A successful re-enable updates `lastTransitionAt` to the current
///      timestamp and emits both the legacy `Enabled` event and a
///      `Transition` event with an empty `data` field, mirroring the
///      behavior of `enable` aside from the absent payload.
abstract contract ReEnabler is IEnablerV2ReEnable, EnablerV2 {
    // ========== INITIALIZATION ========== //

    constructor() {}

    // ========== STATE-CHANGING FUNCTIONS ========== //

    /// @inheritdoc IEnablerV2ReEnable
    /// @dev The "never been enabled" check uses `lastTransitionAt`, which is
    ///      zero before the first successful `enable`. On success, the
    ///      contract is moved to the enabled state, `lastTransitionAt` is
    ///      updated to the current timestamp, and both the legacy `Enabled`
    ///      event and a `Transition` event with an empty `data` field are
    ///      emitted.
    ///
    ///      Reverts if:
    ///      - The contract is currently enabled.
    ///      - The contract has never been enabled (`lastTransitionAt` is zero).
    ///      - `_authorizeReEnable` rejects the caller.
    ///      - `_beforeReEnable` reverts.
    function reEnable() external override whenDisabled {
        if (lastTransitionAt == 0) revert NeverEnabled();
        _authorizeReEnable();
        _beforeReEnable();
        isEnabled = true;
        lastTransitionAt = _getBlockTimestamp();
        emit Enabled();
        emit Transition(msg.sender, true, "", _getBlockTimestamp());
    }

    // ========== HOOKS ========== //

    /// @notice Validates that the caller is permitted to re-enable the contract.
    /// @dev The function is invoked from `reEnable` after the state checks
    ///      pass and before any state mutation.
    ///
    ///      Reverts if:
    ///      - The caller is not authorized to perform the re-enable.
    function _authorizeReEnable() internal virtual;

    /// @notice Performs implementation-specific state changes that must run
    ///         immediately before the contract is moved back to the enabled state.
    /// @dev The function is invoked from `reEnable` after `_authorizeReEnable`
    ///      succeeds and before `isEnabled` is updated. Implementations that
    ///      share state-restoration logic with `_beforeEnable` should factor
    ///      the common path into a private helper invoked from both hooks,
    ///      since `reEnable` does not forward a calldata payload. The default
    ///      implementation is a no-op.
    function _beforeReEnable() internal virtual {}

    // ========== ERC-165 ========== //

    /// @inheritdoc EnablerV2
    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IEnablerV2ReEnable).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
