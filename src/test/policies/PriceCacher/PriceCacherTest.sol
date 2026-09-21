// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {PriceCacher} from "src/policies/PriceCacher.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {MockPriceCacherCache} from "./MockPriceCacherCache.sol";

abstract contract PriceCacherTest is Test {
    address internal admin;
    address internal emergency;
    address internal heart;
    address internal alice;
    address internal ohm;
    address internal usds;
    address internal usde;

    Kernel internal kernel;
    OlympusRoles internal roles;
    RolesAdmin internal rolesAdmin;
    MockPriceCacherCache internal priceCache;
    PriceCacher internal cacher;

    function setUp() public virtual {
        admin = makeAddr("admin");
        emergency = makeAddr("emergency");
        heart = makeAddr("heart");
        alice = makeAddr("alice");
        ohm = makeAddr("ohm");
        usds = makeAddr("usds");
        usde = makeAddr("usde");

        vm.startPrank(admin);
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        priceCache = new MockPriceCacherCache(kernel);
        cacher = new PriceCacher(kernel, priceCache);

        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(priceCache));
        kernel.executeAction(Actions.ActivatePolicy, address(cacher));
        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);
        rolesAdmin.grantRole(HEART_ROLE, heart);
        priceCache.enable("");
        cacher.addAssetPair(ohm, usds);
        cacher.addAssetPair(ohm, usde);
        cacher.enable("");
        vm.stopPrank();
    }

    function _pairKey(address asset_, address quote_) internal pure returns (bytes32) {
        return keccak256(abi.encode(asset_, quote_));
    }
}
