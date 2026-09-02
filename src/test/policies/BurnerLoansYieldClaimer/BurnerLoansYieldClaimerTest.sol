// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {BurnerLoansYieldClaimer} from "src/policies/BurnerLoansYieldClaimer.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {MockBurnerLoansYieldClaimerTarget} from "./MockBurnerLoansYieldClaimerTarget.sol";

abstract contract BurnerLoansYieldClaimerTest is Test {
    uint32 internal constant _EXECUTION_GAS_LIMIT = 1_000_000;

    address internal admin;
    address internal burnerLoansAdmin;
    address internal heart;
    address internal alice;

    Kernel internal kernel;
    OlympusRoles internal roles;
    RolesAdmin internal rolesAdmin;
    MockBurnerLoansYieldClaimerTarget internal target;
    BurnerLoansYieldClaimer internal claimer;

    function setUp() public virtual {
        admin = makeAddr("admin");
        burnerLoansAdmin = makeAddr("burnerLoansAdmin");
        heart = makeAddr("heart");
        alice = makeAddr("alice");

        vm.startPrank(admin);
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        target = new MockBurnerLoansYieldClaimerTarget(kernel);
        claimer = new BurnerLoansYieldClaimer(kernel, address(target), _EXECUTION_GAS_LIMIT);

        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(target));
        kernel.executeAction(Actions.ActivatePolicy, address(claimer));
        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, burnerLoansAdmin);
        rolesAdmin.grantRole(HEART_ROLE, heart);
        vm.stopPrank();
    }
}
