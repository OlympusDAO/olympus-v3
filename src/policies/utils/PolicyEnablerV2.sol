// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IPolicyEnablerV2} from "src/policies/interfaces/utils/IPolicyEnablerV2.sol";

import {PolicyAdmin, RolesConsumer} from "src/policies/utils/PolicyAdmin.sol";

abstract contract PolicyEnablerV2 is IPolicyEnablerV2, PolicyAdmin {
    // State

    State private _state;
    uint48 public override lastTransitionAt;

    // Initialization

    constructor() PolicyAdmin() RolesConsumer() {
        _state = State.AdminDisabled; // Uninitialized
        // lastTransitionAt = 0; // Not intialized
    }

    // External entry points

    function enable(bytes calldata data_) external override onlyAdminRole whenDisabled {
        State from = _state;
        _enforceTransitionPeriod(from, State.Enabled);
        _onEnable(data_, from);
        _state = State.Enabled;
        lastTransitionAt = _getBlockTimestamp();
        emit Enabled();
        emit Transition(msg.sender, from, State.Enabled, data_, _getBlockTimestamp());
    }

    function disable(bytes calldata data_) external override onlyEmergencyOrAdminRole whenEnabled {
        State next = _isAdmin(msg.sender) ? State.AdminDisabled : State.EmergencyDisabled;
        _enforceTransitionPeriod(_state, next);
        _onDisable(data_, next);
        _state = next;
        lastTransitionAt = _getBlockTimestamp();
        emit Disabled();
        emit Transition(msg.sender, State.Enabled, next, data_, _getBlockTimestamp());
    }

    function reEnable() external override onlyManagerRole {
        if (!_isEmergencyDisabled())
            revert InvalidTransition(State.EmergencyDisabled, State.Enabled);
        _enforceTransitionPeriod(State.EmergencyDisabled, State.Enabled);
        _onReEnable();
        _state = State.Enabled;
        lastTransitionAt = _getBlockTimestamp();
        emit Enabled();
        emit Transition(
            msg.sender,
            State.EmergencyDisabled,
            State.Enabled,
            "",
            _getBlockTimestamp()
        );
    }

    // External views

    function state() external view override returns (State) {
        return _state;
    }

    function isEnabled() external view override returns (bool) {
        return _isEnabled();
    }

    // Hooks

    function _enforceTransitionPeriod(State from_, State to_) internal virtual {}

    function _onEnable(bytes calldata data_, State from_) internal virtual {}

    function _onDisable(bytes calldata data_, State to_) internal virtual {}

    function _onReEnable() internal virtual {}

    // Internal helpers

    modifier whenEnabled() {
        _requireEnabled();
        _;
    }

    function _isEnabled() internal view returns (bool) {
        return _state == State.Enabled;
    }

    function _requireEnabled() internal view {
        if (!_isEnabled()) revert NotEnabled();
    }

    modifier whenDisabled() {
        _requireDisabled();
        _;
    }

    function _isAdminDisabled() internal view returns (bool) {
        return _state == State.AdminDisabled;
    }

    function _isEmergencyDisabled() internal view returns (bool) {
        return _state == State.EmergencyDisabled;
    }

    function _isDisabled() internal view returns (bool) {
        return _isAdminDisabled() || _isEmergencyDisabled();
    }

    function _requireDisabled() internal view {
        if (!_isDisabled()) revert NotDisabled();
    }

    function _getBlockTimestamp() internal view virtual returns (uint48) {
        return uint48(block.timestamp);
    }
}
