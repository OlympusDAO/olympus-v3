// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {MockBurnerLoansSeizerTarget} from "./MockBurnerLoansSeizerTarget.sol";

abstract contract BurnerLoansSeizerTest is Test {
    uint32 internal constant _EXECUTION_GAS_LIMIT = 10_000_000;

    address internal admin;
    address internal burnerLoansAdmin;
    address internal heart;
    address internal alice;
    address internal assetOne;
    address internal assetTwo;

    Kernel internal kernel;
    OlympusRoles internal roles;
    RolesAdmin internal rolesAdmin;
    MockBurnerLoansSeizerTarget internal target;
    BurnerLoansSeizer internal seizer;

    function setUp() public virtual {
        admin = makeAddr("admin");
        burnerLoansAdmin = makeAddr("burnerLoansAdmin");
        heart = makeAddr("heart");
        alice = makeAddr("alice");
        assetOne = makeAddr("assetOne");
        assetTwo = makeAddr("assetTwo");

        vm.startPrank(admin);
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        target = new MockBurnerLoansSeizerTarget(kernel);
        seizer = new BurnerLoansSeizer(kernel, address(target), 10, 5, _EXECUTION_GAS_LIMIT);

        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(seizer));
        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, burnerLoansAdmin);
        rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(seizer));
        rolesAdmin.grantRole(HEART_ROLE, heart);
        vm.stopPrank();
    }

    function _single(address account_) internal pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account_;
    }
}
