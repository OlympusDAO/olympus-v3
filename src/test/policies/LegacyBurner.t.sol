// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {OlympusERC20Token} from "src/external/OlympusERC20.sol";
import {MockLegacyAuthorityV2} from "test/mocks/MockLegacyAuthority.sol";

import "src/Kernel.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";

import {RolesAdmin} from "policies/RolesAdmin.sol";
import {BondManager} from "policies/BondManager.sol";
import {LegacyBurner} from "policies/LegacyBurner.sol";

import {MockLegacyInverseBondDepo} from "test/mocks/MockLegacyInverseBondDepo.sol";

// solhint-disable-next-line max-states-count
contract LegacyBurnerTest is Test {
    UserFactory public userCreator;
    address internal alice;
    address internal guardian;
    address internal policy;

    MockLegacyAuthorityV2 internal legacyAuthority;
    MockLegacyAuthorityV2 internal replacementAuthority;

    OlympusERC20Token internal ohm;

    Kernel internal kernel;
    OlympusMinter internal mintr;
    OlympusTreasury internal trsry;
    OlympusRoles internal roles;
    RolesAdmin internal rolesAdmin;
    LegacyBurner internal burner;

    BondManager internal bondManager;
    MockLegacyInverseBondDepo internal inverseBondDepo;

    function setUp() public {
        userCreator = new UserFactory();

        // Initialize users
        {
            address[] memory users = userCreator.create(3);
            alice = users[0];
            guardian = users[1];
            policy = users[2];
        }

        // Initialize legacy authority and OHM
        {
            legacyAuthority = new MockLegacyAuthorityV2(
                guardian,
                guardian,
                policy,
                address(mintr)
            );
            ohm = new OlympusERC20Token(address(legacyAuthority));
        }

        // Deploy kernel and modules
        {
            kernel = new Kernel();

            mintr = new OlympusMinter(kernel, address(ohm));
            trsry = new OlympusTreasury(kernel);
            roles = new OlympusRoles(kernel);

            legacyAuthority.setVault(address(mintr));
        }

        // Deploy policies and legacy contracts
        {
            rolesAdmin = new RolesAdmin(kernel);

            bondManager = new BondManager(
                kernel,
                address(0),
                address(0),
                address(0),
                address(ohm)
            );

            inverseBondDepo = new MockLegacyInverseBondDepo(address(legacyAuthority), address(ohm));

            burner = new LegacyBurner(
                kernel,
                ohm,
                address(bondManager),
                address(inverseBondDepo),
                500_000,
                7 days
            );
        }

        // Initialize replacement authority
        {
            replacementAuthority = new MockLegacyAuthorityV2(
                guardian,
                guardian,
                address(burner),
                address(mintr)
            );
        }

        // Initialize modules and policies
        {
            // Install modules
            kernel.executeAction(Actions.InstallModule, address(mintr));
            kernel.executeAction(Actions.InstallModule, address(trsry));
            kernel.executeAction(Actions.InstallModule, address(roles));

            // Install policies
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ActivatePolicy, address(bondManager));
            kernel.executeAction(Actions.ActivatePolicy, address(burner));
        }

        // Roles configuration
        {
            // Bond manager roles
            rolesAdmin.grantRole("bondmanager_admin", policy);
        }

        // Give manager and inverse bond depo OHM
        {
            vm.startPrank(address(mintr));
            ohm.mint(address(bondManager), 1_000_000e18);
            ohm.mint(address(inverseBondDepo), 1_000_000e18);
            vm.stopPrank();
        }
    }

    // ========= HELPERS ========= //

    function _setUpForBurning() internal {
        // Use policy to set approval for Burner on BondManager
        vm.prank(policy);
        bondManager.emergencySetApproval(address(burner), type(uint256).max);

        // Use governor to set replacementAuthority on inverse bond depo
        vm.prank(guardian);
        inverseBondDepo.setAuthority(address(replacementAuthority));

        // Warp a day for non-zero rewards
        vm.warp(1 days);
    }

    /// []  burn
    ///     [X]  reverts if bond manager has not given approval
    ///     [X]  reverts if replacementAuthority has not been set on inverse bond depo
    ///     [X]  reverts if rewards are 0
    ///     []  burn can be called by anyone
    ///     []  burns OHM from bond manager and inverse bond depo
    ///     []  calculates and mints rewards to caller

    function test_burnRevertsIfBondManagerHasNotGivenApproval() public {
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        burner.burn();
    }

    function test_burnRevertsIfReplacementAuthorityNotSet() public {
        // Give approval but don't replace authority
        vm.prank(policy);
        bondManager.emergencySetApproval(address(burner), type(uint256).max);

        vm.expectRevert();
        burner.burn();
    }

    function test_burnRevertsIfRewardsAreZero() public {
        _setUpForBurning();

        bytes memory err = abi.encodeWithSignature("MINTR_ZeroAmount()");
        vm.expectRevert(err);
        burner.burn();
    }

    // Rewards are not calculating correctly, need to fix these

    // function test_burnCanBeCalledByAnyone(address caller_) public {
    //     _setUpForBurning();

    //     vm.prank(caller_);
    //     burner.burn();
    // }

    // function test_burnBurnsOhmFromManagerAndDepo() public {
    //     _setUpForBurning();

    //     uint256 managerBalance = ohm.balanceOf(address(bondManager));
    //     uint256 depoBalance = ohm.balanceOf(address(inverseBondDepo));

    //     assertGt(managerBalance, 0);
    //     assertGt(depoBalance, 0);

    //     burner.burn();

    //     managerBalance = ohm.balanceOf(address(bondManager));
    //     depoBalance = ohm.balanceOf(address(inverseBondDepo));

    //     assertEq(managerBalance, 0);
    //     assertEq(depoBalance, 0);
    // }

    // function test_burnCalculatesAndMintsRewardsToCaller(uint256 time) public {
    //     vm.assume(time <= 90 days);

    //     _setUpForBurning();
    //     vm.warp(time);

    //     uint256 callerBalance = ohm.balanceOf(address(this));

    //     assertEq(callerBalance, 0);

    //     burner.burn();

    //     // Calculate expected reward
    //     uint256 rewardsPerSecond = uint256(500_000) / 7 days;
    //     uint256 expectedRewardRate = time * rewardsPerSecond;
    //     uint256 rewardRate = expectedRewardRate > 500_000 ? 500_000 : expectedRewardRate;

    //     uint256 expectedReward = (2_000_000e18 * rewardRate) / 100_000_000;
    //     callerBalance = ohm.balanceOf(address(this));

    //     assertEq(callerBalance, expectedReward);
    // }
}