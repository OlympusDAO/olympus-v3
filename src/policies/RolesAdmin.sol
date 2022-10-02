// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ROLES_V1} from "modules/ROLES.sol";
import "../Kernel.sol";

error OnlyAdmin();
error OnlyNewAdmin();

/// @notice The RolesAdmin Policy grants and revokes Roles in the ROLES module.
contract RolesAdmin is Policy {
    /////////////////////////////////////////////////////////////////////////////////
    //                         Kernel Policy Configuration                         //
    /////////////////////////////////////////////////////////////////////////////////

    ROLES_V1 public ROLES;

    constructor(Kernel _kernel) Policy(_kernel) {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLES_V1(getModuleAddress(dependencies[0]));
    }

    function requestPermissions()
        external
        view
        override
        onlyKernel
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](2);
        requests[0] = Permissions(toKeycode("ROLES"), ROLES.saveRole.selector);
        requests[1] = Permissions(toKeycode("ROLES"), ROLES.removeRole.selector);
    }

    /////////////////////////////////////////////////////////////////////////////////
    //                             Policy Variables                                //
    /////////////////////////////////////////////////////////////////////////////////

    event NewAdminPushed(address indexed newAdmin_);
    event NewAdminPulled(address indexed newAdmin_);

    /// @notice Special role that is responsible for assigning policy-defined roles to addresses.
    address public admin;

    /// @notice Proposed new admin. Address must call `pullRolesAdmin` to become the new roles admin.
    address public newAdmin;

    function grantRole(bytes32 role_, address wallet_) external onlyAdmin {
        ROLES.saveRole(role_, wallet_);
    }

    function revokeRole(bytes32 role_, address wallet_) external onlyAdmin {
        ROLES.removeRole(role_, wallet_);
    }

    function pushNewAdmin(address newAdmin_) external onlyAdmin {
        newAdmin = newAdmin_;
        emit NewAdminPushed(newAdmin_);
    }

    function pullNewAdmin() external {
        if (msg.sender != newAdmin) revert OnlyNewAdmin();
        admin = newAdmin;
        newAdmin = address(0);
        emit NewAdminPulled(admin);
    }
}
