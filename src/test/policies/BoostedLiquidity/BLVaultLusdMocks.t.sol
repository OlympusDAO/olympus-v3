// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test, stdError} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {larping} from "test/lib/larping.sol";

import {FullMath} from "libraries/FullMath.sol";

import {MockLegacyAuthority} from "test/mocks/MockLegacyAuthority.sol";
import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockBalancerVault, MockBalancerPool} from "test/mocks/BalancerMocks.sol";
import {MockAuraBooster, MockAuraRewardPool, MockAuraStashToken, MockAuraVirtualRewardPool} from "test/mocks/AuraMocks.sol";

import {OlympusERC20Token, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import {IAuraBooster, IAuraRewardPool} from "policies/BoostedLiquidity/interfaces/IAura.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusBoostedLiquidityRegistry} from "modules/BLREG/OlympusBoostedLiquidityRegistry.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {IBLVaultManager, BLVaultManagerLusd} from "policies/BoostedLiquidity/BLVaultManagerLusd.sol";
import {BLVaultLusd} from "policies/BoostedLiquidity/BLVaultLusd.sol";

import "src/Kernel.sol";

import {console2} from "forge-std/console2.sol";

// solhint-disable-next-line max-states-count
contract BLVaultLusdTest is Test {
    using FullMath for uint256;
    using larping for *;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;

    OlympusERC20Token internal ohm;
    MockERC20 internal lusd;
    MockERC20 internal aura;
    MockERC20 internal bal;
    MockERC20 internal ldo;
    MockAuraStashToken internal ldoStash;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;
    MockPriceFeed internal lusdUsdPriceFeed;

    MockBalancerVault internal vault;
    MockBalancerPool internal liquidityPool;

    MockAuraBooster internal booster;
    MockAuraRewardPool internal auraPool;

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

    uint256 internal constant BPT_MULTIPLIER = 2;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Deploy mock users
        {
            userCreator = new UserFactory();
            address[] memory users = userCreator.create(2);
            alice = users[0];
            bob = users[1];
        }

        // Deploy auth
        {
            auth = new MockLegacyAuthority(address(0x0));
        }

        // Deploy mock tokens
        {
            ohm = new OlympusERC20Token(address(auth));
            lusd = new MockERC20("LUSD", "LUSD", 18);
            aura = new MockERC20("Aura", "AURA", 18);
            bal = new MockERC20("Balancer", "BAL", 18);
            ldo = new MockERC20("Lido", "LDO", 18);
            ldoStash = new MockAuraStashToken("Lido-Stash", "LDOSTASH", 18, address(ldo));
        }

        // Deploy mock price feeds
        {
            ohmEthPriceFeed = new MockPriceFeed();
            ethUsdPriceFeed = new MockPriceFeed();
            lusdUsdPriceFeed = new MockPriceFeed();

            ohmEthPriceFeed.setDecimals(18);
            ethUsdPriceFeed.setDecimals(8);
            lusdUsdPriceFeed.setDecimals(8);

            ohmEthPriceFeed.setLatestAnswer(1e16); // 0.01 ETH
            ethUsdPriceFeed.setLatestAnswer(1000e8); // 1000 USD
            lusdUsdPriceFeed.setLatestAnswer(1e8); // 1 USD
        }

        // Deploy mock Balancer contracts
        {
            liquidityPool = new MockBalancerPool();
            vault = new MockBalancerVault(
                address(liquidityPool),
                address(lusd),
                address(ohm),
                BPT_MULTIPLIER
            );
            vault.setPoolAmounts(10e18, 1e9);
        }

        // Deploy mock Aura contracts
        {
            auraPool = new MockAuraRewardPool(address(vault.bpt()), address(bal), address(aura));
            booster = new MockAuraBooster(address(auraPool));
        }

        // Deploy kernel
        {
            kernel = new Kernel();
        }

        // Deploy modules
        {
            minter = new OlympusMinter(kernel, address(ohm));
            treasury = new OlympusTreasury(kernel);
            blreg = new OlympusBoostedLiquidityRegistry(kernel);
            roles = new OlympusRoles(kernel);
        }

        // Set vault in auth to MINTR
        {
            auth.vault.larp(address(minter));
        }

        // Deploy policies
        {
            vaultImplementation = new BLVaultLusd();

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
                pid: uint256(0),
                auraBooster: address(booster),
                auraRewardPool: address(auraPool)
            });

            IBLVaultManager.OracleFeed memory ohmEthPriceFeedData = IBLVaultManager.OracleFeed({
                feed: ohmEthPriceFeed,
                updateThreshold: uint48(1 days)
            });

            IBLVaultManager.OracleFeed memory ethUsdPriceFeedData = IBLVaultManager.OracleFeed({
                feed: ethUsdPriceFeed,
                updateThreshold: uint48(1 days)
            });

            IBLVaultManager.OracleFeed memory lusdUsdPriceFeedData = IBLVaultManager.OracleFeed({
                feed: lusdUsdPriceFeed,
                updateThreshold: uint48(1 days)
            });

            vaultManager = new BLVaultManagerLusd(
                kernel,
                tokenData,
                balancerData,
                auraData,
                address(0),
                ohmEthPriceFeedData,
                ethUsdPriceFeedData,
                lusdUsdPriceFeedData,
                address(vaultImplementation),
                100_000e9,
                0,
                1 days
            );
            rolesAdmin = new RolesAdmin(kernel);
        }

        // Initialize system
        {
            // Initialize modules
            kernel.executeAction(Actions.InstallModule, address(minter));
            kernel.executeAction(Actions.InstallModule, address(treasury));
            kernel.executeAction(Actions.InstallModule, address(blreg));
            kernel.executeAction(Actions.InstallModule, address(roles));

            // Activate policies
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ActivatePolicy, address(vaultManager));
        }

        // Set roles
        {
            rolesAdmin.grantRole("liquidityvault_admin", address(this));
            rolesAdmin.grantRole("emergency_admin", address(this));
        }

        // Activate Vault Manager
        {
            vaultManager.activate();
        }

        // Initialize timestamps on mock price feeds
        {
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            ethUsdPriceFeed.setTimestamp(block.timestamp);
            lusdUsdPriceFeed.setTimestamp(block.timestamp);
        }

        // Prepare alice's account
        {
            // Mint LUSD to alice
            lusd.mint(alice, 1_000e18);

            // Create alice's vault
            vm.startPrank(alice);
            aliceVault = BLVaultLusd(vaultManager.deployVault());

            // Approve LUSD to alice's vault
            lusd.approve(address(aliceVault), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _calculateBptOut(
        uint256 lusdAmount_,
        uint256 ohmAmount_
    ) internal pure returns (uint256) {
        return (lusdAmount_ * BPT_MULTIPLIER) + (ohmAmount_ * BPT_MULTIPLIER);
    }

    //============================================================================================//
    //                                      LIQUIDITY FUNCTIONS                                   //
    //============================================================================================//

    /// [X]  deposit
    ///     [X]  can only be called when the manager is active
    ///     [X]  can only be called by the vault's owner
    ///     [X]  correctly increases state values (deployedOhm and totalLp)
    ///     [X]  correctly deploys liquidity
    ///     [X]  correctly deploys liquidity when oracle price < pool price
    ///     [X]  correctly deploys liquidity when oracle price > pool price

    function testCorrectness_depositCanOnlyBeCalledWhenManagerIsActive() public {
        // Deactivate vault manager
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLVaultLusd_Inactive()");
        vm.expectRevert(err);

        // Try to deposit
        vm.prank(alice);
        aliceVault.deposit(1e18, 0);
    }

    function testCorrectness_depositCanOnlyBeCalledByTheVaultOwner(address attacker_) public {
        if (attacker_ == alice) {
            vm.prank(alice);
            aliceVault.deposit(1e18, 0);
        } else {
            bytes memory err = abi.encodeWithSignature("BLVaultLusd_OnlyOwner()");
            vm.expectRevert(err);

            // Try to deposit
            vm.prank(attacker_);
            aliceVault.deposit(1e18, 0);
        }
    }

    function testCorrectness_depositCorrectlyIncreasesState(uint256 depositAmount_) public {
        vm.assume(depositAmount_ > 1e16 && depositAmount_ < 1_000_000_000_000e18);

        // Set limit based on deposit amount
        uint256 newLimit = (vaultManager.getOhmTknPrice() * depositAmount_) / 1e18;
        vaultManager.setLimit(newLimit);

        // Mint more LUSD to alice
        lusd.mint(alice, depositAmount_);

        // Approve LUSD to alice's vault
        vm.startPrank(alice);
        lusd.approve(address(aliceVault), type(uint256).max);

        // Verify state before
        assertEq(vaultManager.deployedOhm(), 0);
        assertEq(vaultManager.totalLp(), 0);

        // Deposit
        aliceVault.deposit(depositAmount_, 0);
        vm.stopPrank();

        // Verify state after
        assertEq(vaultManager.deployedOhm(), newLimit);
        assertEq(vaultManager.totalLp(), _calculateBptOut(depositAmount_, newLimit));
    }

    function testCorrectness_depositCorrectlyDeploysLiquidity() public {
        // Verify state before
        assertEq(ohm.balanceOf(address(vault)), 0);
        assertEq(lusd.balanceOf(address(vault)), 0);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 0);

        // Deposit LUSD
        vm.prank(alice);
        aliceVault.deposit(100e18, 0);

        // Verify state after
        uint256 expectedOhmAmount = (100e18 * vaultManager.getOhmTknPrice()) / 1e18;
        assertEq(ohm.balanceOf(address(vault)), expectedOhmAmount);
        assertEq(lusd.balanceOf(address(vault)), 100e18);

        assertEq(
            ERC20(vault.bpt()).balanceOf(address(auraPool)),
            _calculateBptOut(100e18, expectedOhmAmount)
        );
    }

    function testCorrectness_depositCorrectlyDeploysLiquidityOracleValueLow() public {
        // Set oracle price to 0.5
        ohmEthPriceFeed.setLatestAnswer(0.5e18);

        // Verify state before
        assertEq(ohm.balanceOf(address(vault)), 0);
        assertEq(lusd.balanceOf(address(vault)), 0);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 0);

        // Deposit LUSD
        vm.prank(alice);
        aliceVault.deposit(100e18, 0);

        // Verify state after
        uint256 expectedOhmAmount = (100e18 * vaultManager.getOhmTknPrice()) / 1e18;
        assertEq(ohm.balanceOf(address(vault)), expectedOhmAmount);
        assertEq(lusd.balanceOf(address(vault)), 100e18);

        assertEq(
            ERC20(vault.bpt()).balanceOf(address(auraPool)),
            _calculateBptOut(100e18, expectedOhmAmount)
        );
    }

    function testCorrectness_depositCorrectlyDeploysLiquidityOracleValueHigh() public {
        // Set oracle price to 0.001
        ohmEthPriceFeed.setLatestAnswer(1e15);

        // Verify state before
        assertEq(ohm.balanceOf(address(vault)), 0);
        assertEq(lusd.balanceOf(address(vault)), 0);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 0);

        // Deposit LUSD
        vm.prank(alice);
        aliceVault.deposit(100e18, 0);

        // Verify state after
        // 100 LUSD = 10 OHM, so the result is 10e9
        assertEq(ohm.balanceOf(address(vault)), 10e9);
        assertEq(lusd.balanceOf(address(vault)), 100e18);

        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), _calculateBptOut(100e18, 10e9));
    }

    /// [X]  withdraw
    ///     [X]  can only be called when the manager is active
    ///     [X]  can only be called by the vault's owner
    ///     [X]  fails if not enough LUSD will be sent
    ///     [X]  fails if the cooldown period has not passed
    ///     [X]  correctly decreases state values (deployedOhm and totalLp)
    ///     [X]  correctly withdraws liquidity
    ///     [X]  correctly withdraws liquidity when oracle price differs from pool price

    function _withdrawSetup() internal {
        // Deposit LUSD
        vm.prank(alice);
        aliceVault.deposit(100e18, 0);

        // Wait 1 day to pass the cooldown period
        vm.warp(block.timestamp + 1 days);
    }

    function testCorrectness_withdrawFailsIfCooldownPeriodHasNotPassed() public {
        // Deposit LUSD
        vm.prank(alice);
        aliceVault.deposit(100e18, 0);

        bytes memory err = abi.encodeWithSignature("BLVaultLusd_WithdrawalDelay()");
        vm.expectRevert(err);

        // Try to withdraw
        vm.prank(alice);
        aliceVault.withdraw(1e18, minAmountsOut, 0, true);
    }

    function testCorrectness_withdrawCanOnlyBeCalledByTheVaultOwner(address attacker_) public {
        _withdrawSetup();

        if (attacker_ == alice) {
            vm.prank(alice);
            aliceVault.withdraw(1e18, minAmountsOut, 0, true);
        } else {
            bytes memory err = abi.encodeWithSignature("BLVaultLusd_OnlyOwner()");
            vm.expectRevert(err);

            // Try to withdraw
            vm.prank(attacker_);
            aliceVault.withdraw(1e18, minAmountsOut, 0, true);
        }
    }

    function testCorrectness_withdrawFailsIfNotEnoughLusdWillBeSent() public {
        _withdrawSetup();

        // Set price to 0.001
        ohmEthPriceFeed.setLatestAnswer(1e15);

        bytes memory err = abi.encodeWithSignature("BLVaultLusd_WithdrawFailedPriceImbalance()");
        vm.expectRevert(err);

        // Try to withdraw
        vm.prank(alice);
        aliceVault.withdraw(1e18, minAmountsOut, 900e18, true);
    }

    function testCorrectness_withdrawCorrectlyDecreasesState(uint256 withdrawAmount_) public {
        _withdrawSetup();

        // Get alice vault's Lp balance
        uint256 aliceLpBalance = aliceVault.getLpBalance();
        vm.assume(withdrawAmount_ <= aliceLpBalance);

        // Check state before
        assertEq(vaultManager.deployedOhm(), 10e9);
        assertEq(vaultManager.totalLp(), aliceLpBalance);

        // Withdraw
        vm.prank(alice);
        aliceVault.withdraw(withdrawAmount_, minAmountsOut, 0, true);

        // Check state after
        assertTrue(vaultManager.deployedOhm() < 10e9);
        assertEq(vaultManager.totalLp(), aliceLpBalance - withdrawAmount_);
    }

    function testCorrectness_withdrawCorrectlyWithdrawsLiquidity() public {
        _withdrawSetup();

        // Get alice vault's LP balance
        uint256 aliceLpBalance = aliceVault.getLpBalance();

        // Check state before
        assertEq(ohm.balanceOf(address(vault)), 10e9);
        assertEq(lusd.balanceOf(address(vault)), 100e18);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), aliceLpBalance);

        // Withdraw
        vm.prank(alice);
        aliceVault.withdraw(aliceLpBalance, minAmountsOut, 0, true);

        // Check state after
        assertEq(ohm.balanceOf(address(vault)), 0);
        assertEq(lusd.balanceOf(address(vault)), 0);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 0);
    }

    function testCorrectness_withdrawCorrectlyWithdrawsLiquidityPriceDiff() public {
        _withdrawSetup();

        // Set oracle price to 0.001
        ohmEthPriceFeed.setLatestAnswer(1e15);

        // Get alice's LUSD balance before
        uint256 aliceLusdBalanceBefore = lusd.balanceOf(address(alice));

        // Get alice vault's LP balance
        uint256 aliceLpBalance = aliceVault.getLpBalance();

        // Check state before
        assertEq(ohm.balanceOf(address(vault)), 10e9);
        assertEq(lusd.balanceOf(address(vault)), 100e18);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), aliceLpBalance);

        // Withdraw
        vm.prank(alice);
        aliceVault.withdraw(aliceLpBalance, minAmountsOut, 0, true);

        // Check state after
        assertEq(ohm.balanceOf(address(vault)), 0);
        assertEq(lusd.balanceOf(address(vault)), 0);
        assertEq(lusd.balanceOf(address(alice)) - aliceLusdBalanceBefore, 10e18);
        assertEq(lusd.balanceOf(address(treasury)), 90e18);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 0);
    }

    //============================================================================================//
    //                                       REWARDS FUNCTIONS                                    //
    //============================================================================================//

    /// [X]  claimRewards
    ///     [X]  can only be called when the manager is active
    ///     [X]  can only be called by the vault's owner
    ///     [X]  correctly claims rewards from Aura
    ///     [X]  sends fee on BAL rewards to the treasury
    ///     [X]  sends fee on AURA rewards to the treasury
    ///     [ ]  sends fee on extra rewards to the treasury

    function testCorrectness_claimRewardsCanOnlyBeCalledWhenManagerIsActive() public {
        // Deactivate vault manager
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLVaultLusd_Inactive()");
        vm.expectRevert(err);

        // Try to claim rewards
        vm.prank(alice);
        aliceVault.claimRewards();
    }

    function testCorrectness_claimRewardsCanOnlyBeCalledByTheVaultOwner(address attacker_) public {
        if (attacker_ == alice) {
            vm.prank(alice);
            aliceVault.claimRewards();
        } else {
            bytes memory err = abi.encodeWithSignature("BLVaultLusd_OnlyOwner()");
            vm.expectRevert(err);

            // Try to claim rewards
            vm.prank(attacker_);
            aliceVault.claimRewards();
        }
    }

    function testCorrectness_claimRewardsCorrectlyClaims() public {
        // Deposit LUSD
        _withdrawSetup();

        // Check state before
        assertEq(bal.balanceOf(address(alice)), 0);

        // Claim rewards
        vm.prank(alice);
        aliceVault.claimRewards();

        // Check state after
        assertEq(bal.balanceOf(address(alice)), 1e18);
    }

    function testCorrectness_claimRewardsFee() public {
        // Configure the vault manager with the fee
        vaultManager.setFee(500); // 500 / 1e4 = 5%

        // Create a new user
        address newUser = userCreator.create(1)[0];

        // Mint LUSD to the new user
        lusd.mint(newUser, 1_000e18);

        // Deploy a new vault (since the fee won't be applied to earlier ones)
        vm.startPrank(newUser);
        BLVaultLusd newVault = BLVaultLusd(vaultManager.deployVault());
        lusd.approve(address(newVault), type(uint256).max);

        // Deposit LUSD to the vault
        newVault.deposit(100e18, 0);
        vm.stopPrank();

        // Check state of rewards before
        assertEq(bal.balanceOf(address(newUser)), 0);
        assertEq(bal.balanceOf(address(treasury)), 0);
        assertEq(aura.balanceOf(address(newUser)), 0);
        assertEq(aura.balanceOf(address(treasury)), 0);

        // Claim rewards
        vm.prank(newUser);
        newVault.claimRewards();

        // Check state of rewards after
        assertEq(bal.balanceOf(address(newUser)), 1e18 * 0.95);
        assertEq(bal.balanceOf(address(treasury)), 1e18 * 0.05);
        assertEq(aura.balanceOf(address(newUser)), 1e18 * 0.95);
        assertEq(aura.balanceOf(address(treasury)), 1e18 * 0.05);
    }

    function testCorrectness_claimRewardsFee_extraRewards() public {
        // Configure the vault manager with the fee
        vaultManager.setFee(500); // 500 / 1e4 = 5%

        // Add the extra reward pool to Aura
        MockAuraVirtualRewardPool extraPool = new MockAuraVirtualRewardPool(
            address(liquidityPool),
            address(ldoStash)
        );
        auraPool.addExtraReward(address(extraPool));

        // Create a new user
        address newUser = userCreator.create(1)[0];

        // Mint LUSD to the new user
        lusd.mint(newUser, 1_000e18);

        // Deploy a new vault (since the fee won't be applied to earlier ones)
        vm.startPrank(newUser);
        BLVaultLusd newVault = BLVaultLusd(vaultManager.deployVault());
        lusd.approve(address(newVault), type(uint256).max);

        // Deposit LUSD to the vault
        newVault.deposit(100e18, 0);
        vm.stopPrank();

        // Check state of rewards before
        assertEq(bal.balanceOf(address(newUser)), 0);
        assertEq(bal.balanceOf(address(treasury)), 0);
        assertEq(aura.balanceOf(address(newUser)), 0);
        assertEq(aura.balanceOf(address(treasury)), 0);
        assertEq(ldo.balanceOf(address(newUser)), 0);
        assertEq(ldo.balanceOf(address(treasury)), 0);

        // Claim rewards
        vm.prank(newUser);
        newVault.claimRewards();

        // Check state of rewards after
        assertEq(bal.balanceOf(address(newUser)), 1e18 * 0.95);
        assertEq(bal.balanceOf(address(treasury)), 1e18 * 0.05);
        assertEq(aura.balanceOf(address(newUser)), 1e18 * 0.95);
        assertEq(aura.balanceOf(address(treasury)), 1e18 * 0.05);
        assertEq(ldo.balanceOf(address(newUser)), 1e18 * 0.95);
        assertEq(ldo.balanceOf(address(treasury)), 1e18 * 0.05);
    }

    //============================================================================================//
    //                                        VIEW FUNCTIONS                                      //
    //============================================================================================//

    /// [X]  getLpBalance
    ///     [X]  returns the correct LP balance

    function testCorrectness_getLpBalance(uint256 depositAmount_) public {
        vm.assume(depositAmount_ > 1e15 && depositAmount_ < 1_000_000_000_000e18);

        // Set limit based on deposit amount
        uint256 newLimit = (vaultManager.getOhmTknPrice() * depositAmount_) / 1e18;
        vaultManager.setLimit(newLimit);

        // Mint more LUSD to alice
        lusd.mint(alice, depositAmount_);

        // Approve LUSD to alice's vault
        vm.startPrank(alice);
        lusd.approve(address(aliceVault), type(uint256).max);

        // Check state before
        assertEq(aliceVault.getLpBalance(), 0);

        // Deposit
        aliceVault.deposit(depositAmount_, 0);
        vm.stopPrank();

        // Check state after
        assertEq(aliceVault.getLpBalance(), _calculateBptOut(depositAmount_, newLimit));
    }

    /// [X]  getUserPairShare
    ///     [X]  returns the correct user LUSD share

    function testCorrectness_getUserPairShare(uint256 depositAmount_) public {
        vm.assume(depositAmount_ > 1e15 && depositAmount_ < 1_000_000_000_000e18);

        // Set limit based on deposit amount
        uint256 newLimit = (vaultManager.getOhmTknPrice() * depositAmount_) / 1e18;
        vaultManager.setLimit(newLimit);

        // Mint more LUSD to alice
        lusd.mint(alice, depositAmount_);

        // Approve LUSD to alice's vault
        vm.startPrank(alice);
        lusd.approve(address(aliceVault), type(uint256).max);

        // Check state before
        assertEq(aliceVault.getUserPairShare(), 0);

        // Deposit
        aliceVault.deposit(depositAmount_, 0);
        vm.stopPrank();

        // Set pool amounts to true balances
        vault.setPoolAmounts(lusd.balanceOf(address(vault)), ohm.balanceOf(address(vault)));

        uint256 lpBalance = aliceVault.getLpBalance();

        // Calculate expected share
        uint256 tknOhmPrice = vaultManager.getTknOhmPrice();
        uint256 userOhmShare = (lpBalance * ohm.balanceOf(address(vault))) /
            liquidityPool.totalSupply();
        uint256 expectedLusdShare = (userOhmShare * tknOhmPrice) / 1e9;
        uint256 expectedShare = depositAmount_ > expectedLusdShare
            ? expectedLusdShare
            : depositAmount_;

        // Check state after
        assertEq(aliceVault.getUserPairShare(), expectedShare);
    }
}
