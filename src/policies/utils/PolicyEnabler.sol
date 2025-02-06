// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "./RoleDefinitions.sol";

/// @title  PolicyEnabler
/// @notice This contract is designed to be inherited by contracts that need to be enabled or disabled. It replaces the inconsistent usage of `active` and `locallyActive` state variables across the codebase.
/// @dev    A contract that inherits from this contract should use the `onlyEnabled` and `onlyDisabled` modifiers to gate access to certain functions.
///
///         Inheriting contracts must do the following:
///         - In `configureDependencies()`, assign the module address to the `ROLES` state variable, e.g. `ROLES = ROLESv1(getModuleAddress(toKeycode("ROLES")));`
///
///         The following are optional:
///         - Override the `_enable()` and `_disable()` functions if custom logic and/or parameters are needed for the enable/disable functions.
///           - For example, `enable()` could be called with initialisation data that is decoded, validated and assigned in `_enable()`.
abstract contract PolicyEnabler is RolesConsumer {
    // ===== STATE VARIABLES ===== //

    /// @notice Whether the policy functionality is enabled
    bool public isEnabled;

    // ===== ERRORS ===== //

    error NotAuthorised();
    error NotDisabled();
    error NotEnabled();

    // ===== EVENTS ===== //

    event Disabled();
    event Enabled();

    // ===== MODIFIERS ===== //

    /// @notice Modifier that reverts if the caller does not have the emergency or admin role
    modifier onlyEmergencyOrAdminRole() {
        if (!ROLES.hasRole(msg.sender, EMERGENCY_ROLE) && !ROLES.hasRole(msg.sender, ADMIN_ROLE))
            revert NotAuthorised();
        _;
    }

    /// @notice Modifier that reverts if the policy is not enabled
    modifier onlyEnabled() {
        if (!isEnabled) revert NotEnabled();
        _;
    }

    /// @notice Modifier that reverts if the policy is enabled
    modifier onlyDisabled() {
        if (isEnabled) revert NotDisabled();
        _;
    }

    // ===== ENABLEABLE FUNCTIONS ===== //

    /// @notice Enable the contract
    /// @dev    This function performs the following steps:
    ///         1. Validates that the caller has `ROLE` ("emergency_shutdown")
    ///         2. Validates that the contract is disabled
    ///         3. Calls the implementation-specific `_enable()` function
    ///         4. Changes the state of the contract to enabled
    ///         5. Emits the `Enabled` event
    ///
    /// @param  enableData_ The data to pass to the implementation-specific `_enable()` function
    function enable(bytes calldata enableData_) public onlyEmergencyOrAdminRole onlyDisabled {
        // Call the implementation-specific enable function
        _enable(enableData_);

        // Change the state
        isEnabled = true;

        // Emit the enabled event
        emit Enabled();
    }

    /// @notice Implementation-specific enable function
    /// @dev    This function is called by the `enable()` function
    ///
    ///         The implementing contract can override this function and perform the following:
    ///         1. Validate any parameters (if needed) or revert
    ///         2. Validate state (if needed) or revert
    ///         3. Perform any necessary actions, apart from modifying the `isEnabled` state variable
    ///
    /// @param  enableData_ Custom data that can be used by the implementation. The format of this data is
    ///         left to the discretion of the implementation.
    function _enable(bytes calldata enableData_) internal virtual {}

    /// @notice Disable the contract
    /// @dev    This function performs the following steps:
    ///         1. Validates that the caller has `ROLE` ("emergency_shutdown")
    ///         2. Validates that the contract is enabled
    ///         3. Calls the implementation-specific `_disable()` function
    ///         4. Changes the state of the contract to disabled
    ///         5. Emits the `Disabled` event
    ///
    /// @param  disableData_ The data to pass to the implementation-specific `_disable()` function
    function disable(bytes calldata disableData_) public onlyEmergencyOrAdminRole onlyEnabled {
        // Call the implementation-specific disable function
        _disable(disableData_);

        // Change the state
        isEnabled = false;

        // Emit the disabled event
        emit Disabled();
    }

    /// @notice Implementation-specific disable function
    /// @dev    This function is called by the `disable()` function.
    ///
    ///         The implementing contract can override this function and perform the following:
    ///         1. Validate any parameters (if needed) or revert
    ///         2. Validate state (if needed) or revert
    ///         3. Perform any necessary actions, apart from modifying the `isEnabled` state variable
    ///
    /// @param  disableData_ Custom data that can be used by the implementation. The format of this data is
    ///         left to the discretion of the implementation.
    function _disable(bytes calldata disableData_) internal virtual {}
}
