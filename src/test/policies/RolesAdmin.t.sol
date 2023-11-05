// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {RolesAdmin} from "policies/RolesAdmin.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import "src/Kernel.sol";

contract RolesAdminTest is Test {
    UserFactory public userCreator;
    address internal admin;
    address internal testUser;
    address internal newAdmin;

    bytes32 internal testRole = "test_role";

    Kernel internal kernel;
    OlympusRoles internal ROLES;
    RolesAdmin internal rolesAdmin;

    function setUp() public {
        userCreator = new UserFactory();

        address[] memory users = userCreator.create(2);
        testUser = users[0];
        newAdmin = users[1];

        kernel = new Kernel(); // this contract will be the executor

        ROLES = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // NOTE: This test contract is the rolesAdmin, since it is the deployer
        admin = address(this);
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](1);
        expectedDeps[0] = toKeycode("ROLES");

        Keycode[] memory deps = rolesAdmin.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](2);
        Keycode ROLES_KEYCODE = toKeycode("ROLES");
        expectedPerms[0] = Permissions(ROLES_KEYCODE, ROLES.saveRole.selector);
        expectedPerms[1] = Permissions(ROLES_KEYCODE, ROLES.removeRole.selector);
        Permissions[] memory perms = rolesAdmin.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    // ======== ROLES TESTS ======= //

    function testCorrectness_OnlyAdmin() public {
        bytes memory err = abi.encodeWithSelector(RolesAdmin.Roles_OnlyAdmin.selector);
        vm.expectRevert(err);
        vm.prank(testUser);
        rolesAdmin.grantRole(testRole, testUser);

        vm.prank(admin);
        rolesAdmin.grantRole(testRole, testUser);

        assertTrue(ROLES.hasRole(testUser, testRole));
    }

    function testCorrectness_GrantRole() public {
        // Give role to test user
        vm.prank(admin);
        rolesAdmin.grantRole(testRole, testUser);

        assertTrue(ROLES.hasRole(testUser, testRole));
    }

    function testCorrectness_RevokeRole() public {
        // Give then remove role from test user
        vm.startPrank(admin);
        rolesAdmin.grantRole(testRole, testUser);
        rolesAdmin.revokeRole(testRole, testUser);
        vm.stopPrank();

        assertFalse(ROLES.hasRole(testUser, testRole));
    }

    function testCorrectness_ChangeAdmin() public {
        // try pulling admin without push
        bytes memory err = abi.encodeWithSelector(RolesAdmin.Roles_OnlyNewAdmin.selector);
        vm.expectRevert(err);
        vm.prank(newAdmin);
        rolesAdmin.pullNewAdmin();

        // push new admin
        vm.prank(admin);
        rolesAdmin.pushNewAdmin(newAdmin);

        // pull new admin
        vm.prank(newAdmin);
        rolesAdmin.pullNewAdmin();

        assertEq(rolesAdmin.admin(), newAdmin);
    }
}
