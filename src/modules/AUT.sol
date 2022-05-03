// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// LOCAL
// interfaces (enums events errors)
import "src/OlympusErrors.sol";

// types
import {Kernel, Module} from "src/Kernel.sol";

contract Auth is Module {
    mapping(address => bytes32) public getUserRoles;

    mapping(address => mapping(bytes4 => bool)) public isCapabilityPublic;

    mapping(address => mapping(bytes4 => bytes32))
        public getRolesWithCapability;

    event AUT_UserRoleUpdated(
        address indexed user,
        uint8 indexed role,
        bool enabled
    );

    event AUT_PublicCapabilityUpdated(
        address indexed target,
        bytes4 indexed functionSig,
        bool enabled
    );

    event AUT_RoleCapabilityUpdated(
        uint8 indexed role,
        address indexed target,
        bytes4 indexed functionSig,
        bool enabled
    );

    constructor(address kernel_) Module(Kernel(kernel_)) {}

    function KEYCODE() external pure virtual override returns (bytes3) {
        return "AUT";
    }

    function doesUserHaveRole(address user, uint8 role)
        public
        view
        virtual
        returns (bool)
    {
        return (uint256(getUserRoles[user]) >> role) & 1 != 0;
    }

    function doesRoleHaveCapability(
        uint8 role,
        address target,
        bytes4 functionSig
    ) public view virtual returns (bool) {
        return
            (uint256(getRolesWithCapability[target][functionSig]) >> role) &
                1 !=
            0;
    }

    function canCall(
        address user,
        address target,
        bytes4 functionSig
    ) public view virtual returns (bool) {
        return
            isCapabilityPublic[target][functionSig] ||
            bytes32(0) !=
            getUserRoles[user] & getRolesWithCapability[target][functionSig];
    }

    function setPublicCapability(
        address target,
        bytes4 functionSig,
        bool enabled
    ) public virtual onlyPolicy {
        isCapabilityPublic[target][functionSig] = enabled;

        emit AUT_PublicCapabilityUpdated(target, functionSig, enabled);
    }

    function setRoleCapability(
        uint8 role,
        address target,
        bytes4 functionSig,
        bool enabled
    ) public virtual onlyPolicy {
        if (enabled) {
            getRolesWithCapability[target][functionSig] |= bytes32(1 << role);
        } else {
            getRolesWithCapability[target][functionSig] &= ~bytes32(1 << role);
        }

        emit AUT_RoleCapabilityUpdated(role, target, functionSig, enabled);
    }

    function setUserRole(
        address user,
        uint8 role,
        bool enabled
    ) public virtual onlyPolicy {
        if (enabled) {
            getUserRoles[user] |= bytes32(1 << role);
        } else {
            getUserRoles[user] &= ~bytes32(1 << role);
        }

        emit AUT_UserRoleUpdated(user, role, enabled);
    }
}
