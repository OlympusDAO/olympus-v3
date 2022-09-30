// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {RolesAdmin} from "policies/RolesAdmin.sol";
import "modules/ROLES.sol";

import "src/Kernel.sol";

contract TreasuryCustodianTest is Test {
    UserFactory public userCreator;
    address internal admin;
    address internal testUser;
    address internal newAdmin;

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
        address admin = address(this);
    }

    function testCorrectness_OnlyAdmin() public {}

    function testCorrectness_GrantRole() public {}

    function testCorrectness_RevokeRole() public {}

    function testCorrectness_ChangeAdmin() public {
        // try pulling admin without push
        // push new admin
        // pull new admin
    }
}
