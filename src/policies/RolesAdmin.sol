// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Role, toRole, OlympusRoles} from "modules/ROLES.sol";
import "../Kernel.sol";

error OnlyAdmin();
error OnlyNewAdmin();

/// @notice The RolesAdmin Policy grants and revokes Roles in the ROLES module.
contract RolesAdmin is Policy {
    /////////////////////////////////////////////////////////////////////////////////
    //                         Kernel Policy Configuration                         //
    /////////////////////////////////////////////////////////////////////////////////

    OlympusRoles public ROLES;

    constructor(Kernel _kernel) Policy(_kernel) {
        rolesAdmin = msg.sender;
    }

    modifier onlyAdmin() {
        if (msg.sender != rolesAdmin) revert OnlyAdmin();
        _;
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = OlympusRoles(getModuleAddress(dependencies[0]));
    }

    function requestPermissions()
        external
        view
        override
        onlyKernel
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](3);
        requests[0] = Permissions(toKeycode("ROLES"), ROLES.requireRole.selector);
        requests[1] = Permissions(toKeycode("ROLES"), ROLES.saveRole.selector);
        requests[2] = Permissions(toKeycode("ROLES"), ROLES.removeRole.selector);
    }

    /////////////////////////////////////////////////////////////////////////////////
    //                             Policy Variables                                //
    /////////////////////////////////////////////////////////////////////////////////

    event RolesAdminPushed(address indexed newAdmin_);
    event RolesAdminPulled(address indexed newAdmin_);

    /// @notice Special role that is responsible for assigning policy-defined roles to addresses.
    address public rolesAdmin;

    /// @notice Proposed new admin. Address must call `pullRolesAdmin` to become the new roles admin.
    address public newAdmin;

    function grantRole(bytes32 role_, address wallet_) external onlyAdmin {
        ROLES.saveRole(toRole(role_), wallet_);
    }

    function revokeRole(bytes32 role_, address wallet_) external onlyAdmin {
        ROLES.removeRole(toRole(role_), wallet_);
    }

    function pushRolesAdmin(address newAdmin_) external onlyAdmin {
        newAdmin = newAdmin_;
        emit RolesAdminPushed(newAdmin_);
    }

    function pullRolesAdmin() external {
        if (msg.sender != newAdmin) revert OnlyNewAdmin();
        rolesAdmin = newAdmin;
        newAdmin = address(0);
        emit RolesAdminPulled(rolesAdmin);
    }
}
