// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {Kernel, Actions, Keycode, toKeycode} from "src/Kernel.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

abstract contract PeriodicTaskManagerTest is Test {
    MockPeriodicTaskManager public periodicTaskManager;
    Kernel public kernel;
    OlympusRoles public ROLES;
    RolesAdmin public rolesAdmin;

    address public OWNER;
    address public ADMIN;

    function setUp() public {
        OWNER = makeAddr("OWNER");
        ADMIN = makeAddr("ADMIN");

        vm.prank(OWNER);
        kernel = new Kernel();

        ROLES = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        periodicTaskManager = new MockPeriodicTaskManager(kernel);

        // Install contracts
        vm.startPrank(OWNER);
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(periodicTaskManager));
        vm.stopPrank();

        // Grant permissions
        vm.startPrank(OWNER);
        rolesAdmin.grantRole(bytes32("admin"), ADMIN);
        vm.stopPrank();
    }
}
