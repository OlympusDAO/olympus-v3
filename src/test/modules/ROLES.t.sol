// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import "src/Kernel.sol";

contract ROLESTest is Test {
    using ModuleTestFixtureGenerator for OlympusRoles;

    Kernel internal kernel;
    OlympusRoles public ROLES;
    address public testUser;
    address public testUser2;
    address public godmode;

    uint256 internal constant INITIAL_TOKEN_AMOUNT = 100e18;

    function setUp() public {
        kernel = new Kernel();
        ROLES = new OlympusRoles(kernel);

        address[] memory users = (new UserFactory()).create(2);
        testUser = users[0];
        testUser2 = users[1];

        kernel.executeAction(Actions.InstallModule, address(ROLES));

        // Generate test policy with all authorizations
        godmode = ROLES.generateGodmodeFixture(type(OlympusRoles).name);
        kernel.executeAction(Actions.ActivatePolicy, godmode);
    }

    function testCorrectness_KEYCODE() public {
        assertEq32("ROLES", fromKeycode(ROLES.KEYCODE()));
    }

    function testCorrectness_SaveRole() public {
        bytes32 testRole = "test_role";

        // Give role to test user
        vm.prank(godmode);
        ROLES.saveRole(testRole, testUser);

        assertTrue(ROLES.hasRole(testUser, testRole));
    }

    function testCorrectness_RemoveRole() public {
        bytes32 testRole = "test_role";

        // Give then remove role from test user
        vm.startPrank(godmode);
        ROLES.saveRole(testRole, testUser);
        ROLES.removeRole(testRole, testUser);
        vm.stopPrank();

        assertFalse(ROLES.hasRole(testUser, testRole));
    }

    function testCorrectness_EnsureValidRole() public {
        ROLES.ensureValidRole("valid");

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_InvalidRole.selector,
            bytes32("INVALID_ID")
        );
        vm.expectRevert(err);
        ROLES.ensureValidRole("INVALID_ID");
    }
}
