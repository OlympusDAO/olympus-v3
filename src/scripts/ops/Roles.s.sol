// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {console2} from "forge-std/console2.sol";

import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract RolesScript is WithEnvironment {
    function hasRole(
        string calldata chain_,
        string calldata role_,
        address to_
    ) external returns (bool) {
        _loadEnv(chain_);

        console2.log("Checking role", role_, "for", to_);

        bool hasRoleResult = ROLESv1(_envAddressNotZero("olympus.modules.OlympusRoles")).hasRole(
            to_,
            bytes32(bytes(role_))
        );

        console2.log("Address has role:", hasRoleResult);

        return hasRoleResult;
    }

    function grantRole(string calldata chain_, string calldata role_, address to_) external {
        _loadEnv(chain_);

        console2.log("Granting role", role_, "to", to_);

        RolesAdmin(_envAddressNotZero("olympus.policies.RolesAdmin")).grantRole(
            bytes32(bytes(role_)),
            to_
        );

        console2.log("Role granted");
    }

    function revokeRole(string calldata chain_, string calldata role_, address to_) external {
        _loadEnv(chain_);

        console2.log("Revoking role", role_, "from", to_);

        RolesAdmin(_envAddressNotZero("olympus.policies.RolesAdmin")).revokeRole(
            bytes32(bytes(role_)),
            to_
        );

        console2.log("Role revoked");
    }
}
