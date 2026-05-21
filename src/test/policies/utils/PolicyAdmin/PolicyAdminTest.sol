// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";
import {Kernel, Actions} from "src/Kernel.sol";

import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

import {ADMIN_ROLE, EMERGENCY_ROLE, MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {IMockPolicyAdmin} from "./IMockPolicyAdmin.sol";

/// @notice Shared setup for the `PolicyAdmin` and `PolicyAdminOptimized` mix-in tests.
/// @dev    Concrete test contracts implement `_deployPolicyAdmin()` to select the mix-in
///         under test, so a single copy of the test logic runs against both mix-ins.
abstract contract PolicyAdminTest is Test {
    address public emergency;
    address public admin;
    address public manager;

    Kernel public kernel;
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;
    IMockPolicyAdmin public policyAdmin;

    function setUp() public {
        emergency = makeAddr("emergency");
        admin = makeAddr("admin");
        manager = makeAddr("manager");

        kernel = new Kernel();
        vm.label(address(kernel), "Kernel");

        roles = new OlympusRoles(kernel);
        vm.label(address(roles), "OlympusRoles");

        rolesAdmin = new RolesAdmin(kernel);
        vm.label(address(rolesAdmin), "RolesAdmin");

        policyAdmin = _deployPolicyAdmin(kernel);
        vm.label(address(policyAdmin), "policyAdmin");

        // Install
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(policyAdmin));

        // Grant roles
        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);
        rolesAdmin.grantRole(MANAGER_ROLE, manager);
    }

    /// @notice Deploys the harness contract that exercises the mix-in under test.
    ///
    /// @param  kernel_ The kernel that the harness is registered against.
    /// @return The deployed harness, accessed through the common `IMockPolicyAdmin` surface.
    function _deployPolicyAdmin(Kernel kernel_) internal virtual returns (IMockPolicyAdmin);
}
