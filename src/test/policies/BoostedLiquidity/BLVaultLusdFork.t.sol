// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test, stdError} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {larping} from "test/lib/larping.sol";

import {FullMath} from "libraries/FullMath.sol";

import {MockLegacyAuthority} from "test/mocks/MockLegacyAuthority.sol";
import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {OlympusERC20Token, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IVault, IBasePool, IBalancerHelper} from "policies/BoostedLiquidity/interfaces/IBalancer.sol";
import {IAuraBooster, IAuraRewardPool, IAuraMiningLib} from "policies/BoostedLiquidity/interfaces/IAura.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusBoostedLiquidityRegistry} from "modules/BLREG/OlympusBoostedLiquidityRegistry.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {IBLVaultManager} from "policies/BoostedLiquidity/interfaces/IBLVaultManager.sol";
import {BLVaultManagerLusd} from "policies/BoostedLiquidity/BLVaultManagerLusd.sol";
import {BLVaultLusd} from "policies/BoostedLiquidity/BLVaultLusd.sol";

import "src/Kernel.sol";

import {console2} from "forge-std/console2.sol";

// solhint-disable-next-line max-states-count
contract BLVaultLusdTestFork is Test {
    using FullMath for uint256;

    address internal alice;
    address internal bob;
    address internal guardian;
    address public godmode;

    OlympusERC20Token internal ohm;
    MockERC20 internal lusd;
    ERC20 internal aura;
    ERC20 internal bal;

    AggregatorV2V3Interface internal ohmEthPriceFeed;
    AggregatorV2V3Interface internal ethUsdPriceFeed;
    AggregatorV2V3Interface internal lusdUsdPriceFeed;

    IVault internal vault;
    IBasePool internal liquidityPool;
    IBalancerHelper internal balancerHelper;

    IAuraBooster internal booster;
    IAuraRewardPool internal auraPool;
    IAuraMiningLib internal auraMiningLib;
    ERC20 internal auraDepositToken;

    IOlympusAuthority internal auth;

    Kernel internal kernel;
    OlympusMinter internal minter;
    OlympusTreasury internal treasury;
    OlympusBoostedLiquidityRegistry internal blreg;
    OlympusRoles internal roles;

    RolesAdmin internal rolesAdmin;
    BLVaultManagerLusd internal vaultManager;
    BLVaultLusd internal vaultImplementation;

    BLVaultLusd internal aliceVault;

    uint256[] internal minAmountsOut = [0, 0];

    function setUp() public {
        {
            // Set up users
            alice = payable(address(uint160(uint256(keccak256(abi.encodePacked("alice"))))));
            bob = payable(address(uint160(uint256(keccak256(abi.encodePacked("bob"))))));
            guardian = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;

            // Give ETH to alice
            vm.deal(alice, 100 ether);
            vm.deal(bob, 100 ether);

            // Label addresses
            vm.label(alice, "alice");
            vm.label(bob, "bob");
            vm.label(guardian, "guardian");
        }

        {
            // Get tokens
            ohm = OlympusERC20Token(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
            lusd = MockERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
            aura = ERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
            bal = ERC20(0xba100000625a3754423978a60c9317c58a424e3D);

            // Give LUSD to alice
            vm.prank(0x24179CD81c9e782A4096035f7eC97fB8B783e007);
            lusd.mint(alice, 1000e18);

            // Label tokens
            vm.label(address(ohm), "ohm");
            vm.label(address(lusd), "lusd");
            vm.label(address(aura), "aura");
            vm.label(address(bal), "bal");
        }

        {
            // Get price feeds
            ohmEthPriceFeed = AggregatorV2V3Interface(0x9a72298ae3886221820B1c878d12D872087D3a23);
            ethUsdPriceFeed = AggregatorV2V3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
            lusdUsdPriceFeed = AggregatorV2V3Interface(0x3D7aE7E594f2f2091Ad8798313450130d0Aba3a0);

            // Label price feeds
            vm.label(address(ohmEthPriceFeed), "ohmEthPriceFeed");
            vm.label(address(ethUsdPriceFeed), "ethUsdPriceFeed");
            vm.label(address(lusdUsdPriceFeed), "lusdUsdPriceFeed");
        }

        {
            // Get Balancer contracts
            vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
            liquidityPool = IBasePool(0x18FDf15ff782e44C1f9B6C5846ff6B0F0004F6a2);
            balancerHelper = IBalancerHelper(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);

            // Label Balancer contracts
            vm.label(address(vault), "balancerVault");
            vm.label(address(liquidityPool), "liquidityPool");
            vm.label(address(balancerHelper), "balancerHelper");
        }

        {
            // Get Aura contracts
            booster = IAuraBooster(0xA57b8d98dAE62B26Ec3bcC4a365338157060B234);
            auraMiningLib = IAuraMiningLib(0x744Be650cea753de1e69BF6BAd3c98490A855f52);

            // determine by calling poolInfo(127) on booster
            auraPool = IAuraRewardPool(0x3b395A27F77C3450393047fF564E893243aC29fF);
            auraDepositToken = ERC20(0x1D15D9B189F61F26f4C2D09451A1da7c698eE502);

            // Label Aura contracts
            vm.label(address(booster), "booster");
            vm.label(address(auraPool), "auraPool");
            vm.label(address(auraMiningLib), "auraMiningLib");
            vm.label(address(auraDepositToken), "auraDepositToken");
        }

        {
            // Get Kernel and Modules
            kernel = Kernel(0x2286d7f9639e8158FaD1169e76d1FbC38247f54b);

            minter = OlympusMinter(0xa90bFe53217da78D900749eb6Ef513ee5b6a491e);
            treasury = OlympusTreasury(0xa8687A15D4BE32CC8F0a8a7B9704a4C3993D9613);
            roles = OlympusRoles(0x6CAfd730Dc199Df73C16420C4fCAb18E3afbfA59);

            // Lebel Kernel and Modules
            vm.label(address(kernel), "kernel");
            vm.label(address(minter), "minter");
            vm.label(address(treasury), "treasury");
            vm.label(address(roles), "roles");
        }

        {
            // Deploy BLREG
            blreg = new OlympusBoostedLiquidityRegistry(kernel);

            // Label BLREG
            vm.label(address(blreg), "blreg");
        }

        {
            // Get Policies
            rolesAdmin = RolesAdmin(0xb216d714d91eeC4F7120a732c11428857C659eC8);

            // Label Policies
            vm.label(address(rolesAdmin), "rolesAdmin");
        }

        {
            // Deploy BLVault implementation
            vaultImplementation = new BLVaultLusd();

            // Deploy BLVault Manager
            IBLVaultManager.TokenData memory tokenData = IBLVaultManager.TokenData({
                ohm: address(ohm),
                pairToken: address(lusd),
                aura: address(aura),
                bal: address(bal)
            });

            IBLVaultManager.BalancerData memory balancerData = IBLVaultManager.BalancerData({
                vault: address(vault),
                liquidityPool: address(liquidityPool),
                balancerHelper: address(0)
            });

            IBLVaultManager.AuraData memory auraData = IBLVaultManager.AuraData({
                pid: uint256(127),
                auraBooster: address(booster),
                auraRewardPool: address(auraPool)
            });

            IBLVaultManager.OracleFeed memory ohmEthPriceFeedData = IBLVaultManager.OracleFeed({
                feed: ohmEthPriceFeed,
                updateThreshold: uint48(1 days)
            });

            IBLVaultManager.OracleFeed memory ethUsdPriceFeedData = IBLVaultManager.OracleFeed({
                feed: ethUsdPriceFeed,
                updateThreshold: uint48(1 hours)
            });

            IBLVaultManager.OracleFeed memory lusdUsdPriceFeedData = IBLVaultManager.OracleFeed({
                feed: lusdUsdPriceFeed,
                updateThreshold: uint48(1 hours)
            });

            vaultManager = new BLVaultManagerLusd(
                kernel,
                tokenData,
                balancerData,
                auraData,
                address(auraMiningLib),
                ohmEthPriceFeedData,
                ethUsdPriceFeedData,
                lusdUsdPriceFeedData,
                address(vaultImplementation),
                233_645e9, // 233_645e9 // $2.5m = 233,645 OHM
                0,
                1 minutes
            );

            // Label BLVault system
            vm.label(address(vaultImplementation), "vaultImplementation");
            vm.label(address(vaultManager), "vaultManager");
        }

        {
            vm.startPrank(guardian);

            // Initialize modules
            kernel.executeAction(Actions.UpgradeModule, address(blreg));

            // Activate policies
            kernel.executeAction(Actions.ActivatePolicy, address(vaultManager));

            vm.stopPrank();
        }

        {
            // Set roles
            vm.startPrank(guardian);
            rolesAdmin.grantRole("liquidityvault_admin", address(this));
            rolesAdmin.grantRole("emergency_admin", address(this));
            vm.stopPrank();
        }

        {
            // Activate BLVault Manager
            vaultManager.activate();
        }

        {
            // Create alice's vault
            vm.startPrank(alice);
            aliceVault = BLVaultLusd(vaultManager.deployVault());

            // Approve LUSD to alice's vault
            lusd.approve(address(aliceVault), type(uint256).max);
            vm.stopPrank();
        }
    }

    //============================================================================================//
    //                                      LIQUIDITY FUNCTIONS                                   //
    //============================================================================================//

    /// [X]  deposit
    ///     [X]  can only be called when the manager is active
    ///     [X]  can only be called by the vault's owner
    ///     [X]  correctly increases state values (deployedOhm and totalLp)
    ///     [X]  correctly deploys liquidity

    function testCorrectness_depositCanOnlyBeCalledWhenManagerIsActive() public {
        // Deactivate vault manager
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLVaultLusd_Inactive()");
        vm.expectRevert(err);

        // Try to deposit
        vm.prank(alice);
        aliceVault.deposit(1e18, 0);
    }

    function testCorrectness_depositCanOnlyBeCalledByTheVaultOwner() public {
        bytes memory err = abi.encodeWithSignature("BLVaultLusd_OnlyOwner()");
        vm.expectRevert(err);

        // Try to deposit
        vm.prank(address(0));
        aliceVault.deposit(1e18, 0);
    }

    // function testCorrectness_depositCorrectlyIncreasesState() public {
    //     // Set limit based on deposit amount
    //     uint256 newLimit = (vaultManager.getOhmTknPrice() * 10e18) / 1e18;
    //     vaultManager.setLimit(newLimit);

    //     // Approve LUSD to alice's vault
    //     vm.startPrank(alice);
    //     lusd.approve(address(aliceVault), type(uint256).max);

    //     // Verify state before
    //     assertEq(vaultManager.deployedOhm(), 0);
    //     assertEq(vaultManager.totalLp(), 0);

    //     // Deposit
    //     aliceVault.deposit(10e18, 0);
    //     vm.stopPrank();

    //     // Verify state after
    //     assertApproxEqRel(vaultManager.deployedOhm(), newLimit, 5e16); // 5% tolerance
    //     assertTrue(vaultManager.totalLp() > 0);
    // }

    // function testCorrectness_depositCorrectlyDeploysLiquidity() public {
    //     // Verify state before
    //     uint256 ohmVaultBalanceBefore = ohm.balanceOf(address(vault));
    //     uint256 lusdVaultBalanceBefore = lusd.balanceOf(address(vault));
    //     uint256 auraBalanceBefore = auraDepositToken.balanceOf(address(auraPool));

    //     // Deposit LUSD
    //     vm.prank(alice);
    //     aliceVault.deposit(10e18, 0);

    //     // Verify state after
    //     uint256 expectedOhmAmount = (10e18 * vaultManager.getOhmTknPrice()) / 1e18;

    //     uint256 ohmVaultBalanceAfter = ohm.balanceOf(address(vault));
    //     uint256 lusdVaultBalanceAfter = lusd.balanceOf(address(vault));
    //     uint256 auraBalanceAfter = auraDepositToken.balanceOf(address(auraPool));

    //     assertApproxEqRel(ohmVaultBalanceAfter - ohmVaultBalanceBefore, expectedOhmAmount, 5e16); // 5% tolerance
    //     assertApproxEqRel(lusdVaultBalanceAfter - lusdVaultBalanceBefore, 10e18, 5e16); // 5% tolerance
    //     assertTrue(auraBalanceAfter > auraBalanceBefore);
    // }

    /// [X]  withdraw
    ///     [X]  can only be called by the vault's owner
    ///     [X]  correctly decreases state values (deployedOhm and totalLp)
    ///     [X]  correctly withdraws liquidity

    function _withdrawSetup() internal {
        // Deposit LUSD
        vm.prank(alice);
        aliceVault.deposit(10e18, 0);

        vm.warp(block.timestamp + 1 minutes);
    }

    // function testCorrectness_withdrawCanOnlyBeCalledByTheVaultOwner() public {
    //     _withdrawSetup();

    //     bytes memory err = abi.encodeWithSignature("BLVaultLusd_OnlyOwner()");
    //     vm.expectRevert(err);

    //     // Try to withdraw
    //     vm.prank(address(0));
    //     aliceVault.withdraw(1e18, minAmountsOut, 0, true);
    // }

    // function testCorrectness_withdrawCorrectlyDecreasesState() public {
    //     _withdrawSetup();

    //     // Get alice vault's Lp balance
    //     uint256 aliceLpBalance = aliceVault.getLpBalance();

    //     // Check state before
    //     uint256 deployedOhmBefore = vaultManager.deployedOhm();

    //     // Withdraw
    //     vm.prank(alice);
    //     aliceVault.withdraw(aliceLpBalance, minAmountsOut, 0, true);

    //     // Check state after
    //     assertTrue(vaultManager.deployedOhm() < deployedOhmBefore);
    //     assertEq(vaultManager.totalLp(), 0);
    // }

    // function testCorrectness_withdrawCorrectlyWithdrawsLiquidity() public {
    //     _withdrawSetup();

    //     // Get alice vault's LP balance
    //     uint256 aliceLpBalance = aliceVault.getLpBalance();

    //     // Check state before
    //     uint256 ohmVaultBalanceBefore = ohm.balanceOf(address(vault));
    //     uint256 lusdVaultBalanceBefore = lusd.balanceOf(address(vault));
    //     uint256 auraBalanceBefore = auraDepositToken.balanceOf(address(auraPool));

    //     // Withdraw
    //     vm.prank(alice);
    //     aliceVault.withdraw(aliceLpBalance, minAmountsOut, 0, true);

    //     // Check state after
    //     uint256 ohmVaultBalanceAfter = ohm.balanceOf(address(vault));
    //     uint256 lusdVaultBalanceAfter = lusd.balanceOf(address(vault));
    //     uint256 auraBalanceAfter = auraDepositToken.balanceOf(address(auraPool));

    //     assertTrue(ohmVaultBalanceBefore > ohmVaultBalanceAfter);
    //     assertTrue(lusdVaultBalanceBefore > lusdVaultBalanceAfter);
    //     assertEq(auraBalanceBefore - auraBalanceAfter, aliceLpBalance);
    // }

    //============================================================================================//
    //                                       REWARDS FUNCTIONS                                    //
    //============================================================================================//

    /// [X]  claimRewards
    ///     [X]  can only be called when the manager is active
    ///     [X]  can only be called by the vault's owner
    ///     [X]  correctly claims rewards from Aura

    function testCorrectness_claimRewardsCanOnlyBeCalledWhenManagerIsActive() public {
        // Deactivate vault manager
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLVaultLusd_Inactive()");
        vm.expectRevert(err);

        // Try to claim rewards
        vm.prank(alice);
        aliceVault.claimRewards();
    }

    function testCorrectness_claimRewardsCanOnlyBeCalledByTheVaultOwner() public {
        bytes memory err = abi.encodeWithSignature("BLVaultLusd_OnlyOwner()");
        vm.expectRevert(err);

        // Try to claim rewards
        vm.prank(address(0));
        aliceVault.claimRewards();
    }

    // function testCorrectness_claimRewardsCorrectlyClaims() public {
    //     // Deposit LUSD
    //     _withdrawSetup();

    //     // Jump forward to accrue rewards
    //     vm.warp(block.timestamp + 30 days);

    //     // Check state before
    //     assertEq(bal.balanceOf(address(alice)), 0);
    //     assertEq(aura.balanceOf(address(alice)), 0);

    //     // Claim rewards
    //     vm.prank(alice);
    //     aliceVault.claimRewards();

    //     // Check state after
    //     // NOTE: These checks are currently failing as rewards are disabled on the live aura pools
    //     assertTrue(bal.balanceOf(address(alice)) > 0);
    //     assertTrue(aura.balanceOf(address(alice)) > 0);
    // }

    //============================================================================================//
    //                                        VIEW FUNCTIONS                                      //
    //============================================================================================//

    /// [X]  getLpBalance
    ///     [X]  returns the correct LP balance

    // function testCorrectness_getLpBalance() public {
    //     // Check state before
    //     assertEq(aliceVault.getLpBalance(), 0);

    //     // Deposit
    //     vm.prank(alice);
    //     aliceVault.deposit(10e18, 0);

    //     // Check state after
    //     assertTrue(aliceVault.getLpBalance() > 0);
    // }

    /// [X]  getUserPairShare
    ///     [X]  returns the correct user LUSD share

    // function testCorrectness_getUserPairShare() public {
    //     // Check state before
    //     assertEq(aliceVault.getUserPairShare(), 0);

    //     // Deposit
    //     vm.prank(alice);
    //     aliceVault.deposit(10e18, 0);

    //     // Check state after
    //     assertTrue(aliceVault.getUserPairShare() > 0);
    // }
}
