// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {Kernel, Actions} from "src/Kernel.sol";

import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {MockPolicyAdmin} from "./MockPolicyAdmin.sol";

contract PolicyAdminTest is Test {
    address public constant EMERGENCY = address(0xAAAA);
    address public constant ADMIN = address(0xBBBB);

    Kernel public kernel;
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;
    MockPolicyAdmin public policyAdmin;

    function setUp() public {
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        policyAdmin = new MockPolicyAdmin(kernel);

        // Install
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(policyAdmin));

        // Grant roles
        rolesAdmin.grantRole(ADMIN_ROLE, ADMIN);
        rolesAdmin.grantRole(EMERGENCY_ROLE, EMERGENCY);
    }
}
