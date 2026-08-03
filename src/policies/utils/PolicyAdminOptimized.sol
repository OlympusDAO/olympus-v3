// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE, MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title PolicyAdminOptimized
/// @notice A mix-in that gates functions by the admin, emergency, and manager roles,
///         resolving role membership through the `ROLES` module.
/// @dev A bytecode-optimized copy of `PolicyAdmin` with identical behaviour.
abstract contract PolicyAdminOptimized is IPolicyAdmin, RolesConsumer {
    /// @notice Reverts if the caller does not have the emergency or admin role.
    modifier onlyEmergencyOrAdminRole() {
        _requireAuthorized(!_isEmergency(msg.sender) && !_isAdmin(msg.sender));
        _;
    }

    /// @notice Reverts if the caller does not have the manager or admin role.
    modifier onlyManagerOrAdminRole() {
        _requireAuthorized(!_isManager(msg.sender) && !_isAdmin(msg.sender));
        _;
    }

    /// @notice Reverts if the caller does not have the admin role.
    modifier onlyAdminRole() {
        _requireRole(msg.sender, ADMIN_ROLE);
        _;
    }

    /// @notice Reverts if the caller does not have the emergency role.
    modifier onlyEmergencyRole() {
        _requireRole(msg.sender, EMERGENCY_ROLE);
        _;
    }

    /// @notice Reverts if the caller does not have the manager role.
    modifier onlyManagerRole() {
        _requireRole(msg.sender, MANAGER_ROLE);
        _;
    }

    /// @notice Returns whether `account_` holds the admin role.
    ///
    /// @param account_ The account whose role membership is being checked.
    /// @return bool True if `account_` holds the admin role, false otherwise.
    function _isAdmin(address account_) internal view returns (bool) {
        return _hasRole(account_, ADMIN_ROLE);
    }

    /// @notice Returns whether `account_` holds the emergency role.
    ///
    /// @param account_ The account whose role membership is being checked.
    /// @return bool True if `account_` holds the emergency role, false otherwise.
    function _isEmergency(address account_) internal view returns (bool) {
        return _hasRole(account_, EMERGENCY_ROLE);
    }

    /// @notice Returns whether `account_` holds the manager role.
    ///
    /// @param account_ The account whose role membership is being checked.
    /// @return bool True if `account_` holds the manager role, false otherwise.
    function _isManager(address account_) internal view returns (bool) {
        return _hasRole(account_, MANAGER_ROLE);
    }

    /// @notice Returns whether `account_` holds `role_` on the `ROLES` module.
    ///
    /// @param account_ The address whose role membership is being checked.
    /// @param role_ The role identifier to test.
    /// @return bool True if `account_` holds `role_`, false otherwise.
    function _hasRole(address account_, bytes32 role_) internal view returns (bool) {
        return ROLES.hasRole(account_, role_);
    }

    /// @notice Reverts if `account_` does not hold `role_` on the `ROLES` module.
    /// @dev Reverts with `ROLESv1.ROLES_RequireRole` if `account_` does not hold `role_`.
    ///
    /// @param account_ The address whose role membership is being checked.
    /// @param role_ The role identifier that `account_` must hold.
    function _requireRole(address account_, bytes32 role_) internal view {
        if (!_hasRole(account_, role_)) revert ROLESv1.ROLES_RequireRole(role_);
    }

    /// @notice Reverts when an authorization check has failed.
    /// @dev Reverts with `NotAuthorised` when `unauthorized_` is true.
    ///
    /// @param unauthorized_ True if the caller is not authorized, false otherwise.
    function _requireAuthorized(bool unauthorized_) internal view {
        if (unauthorized_) revert NotAuthorised();
    }
}
