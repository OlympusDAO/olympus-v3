// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

import {FullMath} from "libraries/FullMath.sol";

import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";

import {BunniManager} from "policies/UniswapV3/BunniManager.sol";

import "src/Kernel.sol";

contract BunniManagerTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal policy;

    Kernel internal kernel;
    OlympusRoles internal roles;
    OlympusTreasury internal treasury;

    UniswapV3Factory internal uniswapFactory;

    BunniManager internal bunniManager;
    BunniHub internal bunniHub;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            address[] memory users = userCreator.create(2);
            alice = users[0];
            policy = users[1];
        }

        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy modules
            roles = new OlympusRoles(kernel);
            treasury = new OlympusTreasury(kernel);
        }

        {
            // Deploy BunniManager policy
            bunniManager = new BunniManager(kernel);

            // Deploy Uniswap V3 factory
            uniswapFactory = new UniswapV3Factory();

            // Deploy BunniHub
            bunniHub = new BunniHub(
                uniswapFactory,
                address(bunniManager),
                0 // No protocol fee
            );

            rolesAdmin = new RolesAdmin(kernel);
        }

        {
            // Initialize system and kernel

            // Install modules
            kernel.executeAction(Actions.InstallModule, address(treasury));
            kernel.executeAction(Actions.InstallModule, address(roles));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(bunniManager));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }

        {
            // Configure access control

            // BunniManager roles
            rolesAdmin.grantRole("bunni_admin", policy);
        }
    }

    // [ ] constructor
    // [ ] configureDependencies
    //  [ ] reverts if TRSRY version is unsupported
    //  [ ] configures correctly
    // [ ] requestPermissions
    // [ ] deployToken
    //  [ ] caller is unauthorized
    //  [ ] bunniHub not set
    //  [ ] token already deployed
    //  [ ] not a Uniswap V3 pool
    //  [ ] deploys and returns token, registers with PRICEv2
    // [ ] deposit
    //  [ ] caller is unauthorized
    //  [ ] bunniHub not set
    //  [ ] token not deployed
    //  [ ] insufficient balance of token0 in policy to deposit
    //  [ ] insufficient balance of token1 in policy to deposit
    //  [ ] token0 is OHM, deposits and returns shares
    //  [ ] token1 is OHM, deposits and returns shares
    //  [ ] burns excess OHM after deposit
    //  [ ] deposits non-OHM tokens and returns shares
    // [ ] withdraw
    //  [ ] caller is unauthorized
    //  [ ] bunniHub not set
    //  [ ] token not deployed
    //  [ ] withdraws and returns non-OHM tokens to TRSRY
    //  [ ] withdraws, burns OHM and returns non-OHM tokens to TRSRY
    // [ ] getToken
    //  [ ] bunniHub is not set
    //  [ ] token is not deployed
    //  [ ] returns token struct
    // [ ] getTRSRYBalance
    //  [ ] bunniHub is not set
    //  [ ] token is not deployed
    //  [ ] returns token balance
    // [ ] setBunniHub
    //  [ ] caller is unauthorized
    //  [ ] zero address
    //  [ ] sets bunniHub variable
    // [ ] setBunniOwner
    //  [ ] caller is unauthorized
    //  [ ] bunniHub is not set
    //  [ ] zero address
    //  [ ] sets owner of bunniHub
}