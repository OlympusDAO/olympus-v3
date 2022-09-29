// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "src/Kernel.sol";

// ERRORS
error ROLES_CallerIsNotNewAdmin();
error ROLES_OnlyAdmin();
error ROLES_InvalidAddress();
error ROLES_InvalidRole(Role role_);
error ROLES_OnlyRole(Role role_);
error ROLES_RoleDoesNotExist(Role role_);
error ROLES_AddressAlreadyHasRole(address addr_, Role role_);
error ROLES_AddressDoesNotHaveRole(address addr_, Role role_);

type Role is bytes32;

function toRole(bytes32 role_) pure returns (Role) {
    return Role.wrap(role_);
}

function fromRole(Role role_) pure returns (bytes32) {
    return Role.unwrap(role_);
}

/// @notice Module that holds multisig roles needed by various policies.
contract OlympusRoles is Module {
    event RoleGranted(Role indexed role_, address indexed addr_);
    event RoleRevoked(Role indexed role_, address indexed addr_);
    event RolesAdminPushed(address indexed newAdmin_);
    event RolesAdminPulled(address indexed newAdmin_);

    /// @notice Special role that is responsible for assigning policy-defined roles to addresses.
    address public rolesAdmin;

    /// @notice Proposed new admin. Address must call `pullRolesAdmin` to become the new roles admin.
    address public newAdmin;

    /// @notice Mapping for if an address has a policy-defined role.
    mapping(address => mapping(Role => bool)) public hasRole;

    /// @notice Mapping for if role exists.
    mapping(Role => bool) public isRole;

    /*//////////////////////////////////////////////////////////////
                            MODULE INTERFACE
    //////////////////////////////////////////////////////////////*/

    constructor(Kernel kernel_) Module(kernel_) {
        rolesAdmin = msg.sender;
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("ROLES");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    function pushRolesAdmin(address newAdmin_) external {
        if (msg.sender != rolesAdmin) revert ROLES_OnlyAdmin();
        newAdmin = newAdmin_;
        emit RolesAdminPushed(newAdmin_);
    }

    function pullRolesAdmin() external {
        if (msg.sender != newAdmin) revert ROLES_CallerIsNotNewAdmin();
        rolesAdmin = newAdmin;
        newAdmin = address(0);
        emit RolesAdminPulled(rolesAdmin);
    }

    /// @notice "Modifier" to restrict policy function access to certain addresses with a role.
    /// @dev    Roles are defined in the policy and set by the ROLES admin.
    function onlyRole(bytes32 role_, address caller_) external {
        Role role = toRole(role_);
        if (!hasRole[caller_][role]) revert ROLES_OnlyRole(role);
    }

    /// @notice Function to grant policy-defined roles to some address. Can only be called by admin.
    function grantRole(Role role_, address addr_) public {
        if (msg.sender != rolesAdmin) revert ROLES_OnlyAdmin();
        if (hasRole[addr_][role_]) revert ROLES_AddressAlreadyHasRole(addr_, role_);

        ensureValidRole(role_);

        // Activate this role
        if (!isRole[role_]) isRole[role_] = true;

        // Grant role to the address
        hasRole[addr_][role_] = true;

        emit RoleGranted(role_, addr_);
    }

    /// @notice Function to revoke policy-defined roles from some address. Can only be called by admin.
    function revokeRole(Role role_, address addr_) public {
        if (msg.sender != rolesAdmin) revert ROLES_OnlyAdmin();
        if (!isRole[role_]) revert ROLES_RoleDoesNotExist(role_);
        if (!hasRole[addr_][role_]) revert ROLES_AddressDoesNotHaveRole(addr_, role_);

        hasRole[addr_][role_] = false;

        emit RoleRevoked(role_, addr_);
    }


    function ensureValidRole(Role role_) public pure {
        bytes32 unwrapped = Role.unwrap(role_);

        for (uint256 i = 0; i < 32; ) {
            bytes1 char = unwrapped[i];
            if ((char < 0x61 || char > 0x7A) && char != 0x5f && char != 0x00) {
                revert ROLES_InvalidRole(role_); // a-z only
            }
            unchecked {
                i++;
            }
        }
    }
}