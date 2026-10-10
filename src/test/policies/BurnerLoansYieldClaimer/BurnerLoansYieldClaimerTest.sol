// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Test} from "@forge-std-1.16.2/Test.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {BurnerLoansYieldClaimer} from "src/policies/BurnerLoansYieldClaimer.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {MockBurnerLoansYieldClaimerTarget} from "./MockBurnerLoansYieldClaimerTarget.sol";

abstract contract BurnerLoansYieldClaimerTest is Test {
    uint32 internal constant _EXECUTION_GAS_LIMIT = 1_000_000;

    address internal admin;
    address internal burnerLoansAdmin;
    address internal _emergency;
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
        _emergency = makeAddr("emergency");
        heart = makeAddr("heart");
        alice = makeAddr("alice");

        vm.startPrank(admin);
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        target = new MockBurnerLoansYieldClaimerTarget(kernel);
        claimer = new BurnerLoansYieldClaimer(kernel, address(target), _EXECUTION_GAS_LIMIT);
        vm.label(address(kernel), "Kernel");
        vm.label(address(roles), "ROLES");
        vm.label(address(rolesAdmin), "Roles admin");
        vm.label(address(target), "Burner Loans yield target");
        vm.label(address(claimer), "Burner Loans yield claimer");

        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(target));
        kernel.executeAction(Actions.ActivatePolicy, address(claimer));
        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, burnerLoansAdmin);
        rolesAdmin.grantRole(EMERGENCY_ROLE, _emergency);
        rolesAdmin.grantRole(HEART_ROLE, heart);
        claimer.enable("");
        vm.stopPrank();
    }

    function _authorizedClaimerAdmin(bool adminCalls_) internal view returns (address caller_) {
        return adminCalls_ ? admin : burnerLoansAdmin;
    }

    function _setClaimerLifecycle(bool active_, bool enabled_) internal {
        if (!enabled_) {
            vm.prank(_emergency);
            claimer.disable("");
        }
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(claimer));
        }
    }

    function _setTargetLifecycle(bool active_, bool enabled_) internal {
        if (!enabled_) target.disable("");
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(target));
        }
    }

    function _boundUint32(uint32 value_, uint32 min_, uint32 max_) internal pure returns (uint32) {
        // bound() guarantees that the result remains within the supplied uint32 interval.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint32(bound(value_, min_, max_));
    }

    function _boundUint8(uint8 value_, uint8 min_, uint8 max_) internal pure returns (uint8) {
        // bound() guarantees that the result remains within the supplied uint8 interval.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(bound(value_, min_, max_));
    }

    function _boundUint48(uint48 value_, uint48 min_, uint48 max_) internal pure returns (uint48) {
        // bound() guarantees that the result remains within the supplied uint48 interval.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint48(bound(value_, min_, max_));
    }
}
