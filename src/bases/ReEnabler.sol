// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";

/// @title ReEnabler
/// @notice An abstract extension of `EnablerV2` that adds a parameterless `reEnable` entry
///         point intended for callers that should be able to return the contract to the
///         enabled state without the calldata payload required by the standard `enable`.
/// @dev The extension is intended to allow a caller distinct from the principal enabler,
///      such as a manager that does not hold the admin role, to return the contract to
///      the enabled state after a `disable` without supplying the calldata payload that
///      the original `enable` would require. The extension is therefore only meaningful
///      once the contract has been enabled at least once through the standard
///      `IEnabler.enable` entry point.
///
///      Inheriting contracts must override `_authorizeReEnable` to revert when the caller
///      is not permitted to perform the re-enable.
///
///      A successful re-enable updates `lastTransitionAt` to the current timestamp and
///      emits both the legacy `Enabled` event and a `Transition` event with an empty
///      `data` field, mirroring the behavior of `enable` aside from the absent payload.
abstract contract ReEnabler is IReEnabler, EnablerV2 {
    // ========== INITIALIZATION ========== //

    constructor() {}

    // ========== STATE-CHANGING FUNCTIONS ========== //

    /// @inheritdoc IReEnabler
    /// @dev The "never been enabled" check uses `lastTransitionAt`, which is zero before the
    ///      first successful `enable`. On success, the contract is moved to the enabled
    ///      state, `lastTransitionAt` is updated to the current timestamp, and both the
    ///      legacy `Enabled` event and a `Transition` event with an empty `data` field are
    ///      emitted.
    ///
    ///      Reverts if:
    ///      - The contract is currently enabled.
    ///      - The contract has never been enabled (`lastTransitionAt` is zero).
    ///      - `_authorizeReEnable` rejects the caller.
    ///      - `_beforeReEnable` reverts.
    function reEnable() public virtual override givenDisabled {
        if (lastTransitionAt == 0) revert NeverEnabled();
        _authorizeReEnable();
        _beforeReEnable();
        isEnabled = true;
        lastTransitionAt = _getBlockTimestamp();
        emit Enabled();
        emit Transition(msg.sender, true, "", _getBlockTimestamp());
    }

    // ========== HOOKS ========== //

    /// @dev Validates that the caller is permitted to re-enable the contract.
    ///
    ///      The function is invoked from `reEnable` after the state checks pass and before
    ///      any state mutation.
    ///
    ///      Reverts if:
    ///      - The caller is not authorized to perform the re-enable.
    function _authorizeReEnable() internal view virtual;

    /// @dev Performs implementation-specific state changes that must run immediately
    ///      before the contract is moved back to the enabled state.
    ///
    ///      The function is invoked from `reEnable` after `_authorizeReEnable` succeeds and
    ///      before `isEnabled` is updated. Implementations that share state-restoration
    ///      logic with `_beforeEnable` should factor the common path into a private helper
    ///      invoked from both hooks, since `reEnable` does not forward a calldata payload.
    ///      The default implementation is a no-op.
    function _beforeReEnable() internal virtual {}

    // ========== ERC-165 ========== //

    /// @inheritdoc EnablerV2
    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IReEnabler).interfaceId || super.supportsInterface(interfaceId_);
    }
}
