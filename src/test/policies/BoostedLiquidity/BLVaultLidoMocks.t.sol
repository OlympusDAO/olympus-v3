// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test, stdError} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {larping} from "test/lib/larping.sol";

import {FullMath} from "libraries/FullMath.sol";

import {MockLegacyAuthority} from "test/mocks/MockLegacyAuthority.sol";
import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockVault, MockBalancerPool} from "test/mocks/BalancerMocks.sol";
import {MockAuraBooster, MockAuraRewardPool} from "test/mocks/AuraMocks.sol";

import {OlympusERC20Token, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import {IAuraBooster, IAuraRewardPool} from "policies/BoostedLiquidity/interfaces/IAura.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusBoostedLiquidityRegistry} from "modules/BLREG/OlympusBoostedLiquidityRegistry.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {IBLVaultManagerLido, BLVaultManagerLido} from "policies/BoostedLiquidity/BLVaultManagerLido.sol";
import {BLVaultLido} from "policies/BoostedLiquidity/BLVaultLido.sol";

import "src/Kernel.sol";

import {console2} from "forge-std/console2.sol";

contract MockWsteth is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function mint(address to, uint256 value) public {
        _mint(to, value);
    }

    function burnFrom(address from, uint256 value) public {
        _burn(from, value);
    }

    function stEthPerToken() public pure returns (uint256) {
        return 1e18;
    }
}

// solhint-disable-next-line max-states-count
contract BLVaultLidoTest is Test {
    using FullMath for uint256;
    using larping for *;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;

    OlympusERC20Token internal ohm;
    MockWsteth internal wsteth;
    MockERC20 internal aura;
    MockERC20 internal bal;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;
    MockPriceFeed internal stethUsdPriceFeed;

    MockVault internal vault;
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
    BLVaultManagerLido internal vaultManager;
    BLVaultLido internal vaultImplementation;

    BLVaultLido internal aliceVault;

    uint256[] internal minAmountsOut = [0, 0];

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
            wsteth = new MockWsteth("Wrapped Staked ETH", "wstETH", 18);
            aura = new MockERC20("Aura", "AURA", 18);
            bal = new MockERC20("Balancer", "BAL", 18);
        }

        // Deploy mock price feeds
        {
            ohmEthPriceFeed = new MockPriceFeed();
            ethUsdPriceFeed = new MockPriceFeed();
            stethUsdPriceFeed = new MockPriceFeed();

            ohmEthPriceFeed.setDecimals(18);
            ethUsdPriceFeed.setDecimals(8);
            stethUsdPriceFeed.setDecimals(8);

            ohmEthPriceFeed.setLatestAnswer(1e16); // 0.01 ETH
            ethUsdPriceFeed.setLatestAnswer(1000e8); // 1000 USD
            stethUsdPriceFeed.setLatestAnswer(1000e8); // 1000 USD
        }

        // Deploy mock Balancer contracts
        {
            liquidityPool = new MockBalancerPool();
            vault = new MockVault(address(liquidityPool), address(ohm), address(wsteth));
            vault.setPoolAmounts(100e9, 1e18);
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
            vaultImplementation = new BLVaultLido();

            IBLVaultManagerLido.TokenData memory tokenData = IBLVaultManagerLido.TokenData({
                ohm: address(ohm),
                pairToken: address(wsteth),
                aura: address(aura),
                bal: address(bal)
            });

            IBLVaultManagerLido.BalancerData memory balancerData = IBLVaultManagerLido
                .BalancerData({
                    vault: address(vault),
                    liquidityPool: address(liquidityPool),
                    balancerHelper: address(0)
                });

            IBLVaultManagerLido.AuraData memory auraData = IBLVaultManagerLido.AuraData({
                pid: uint256(0),
                auraBooster: address(booster),
                auraRewardPool: address(auraPool)
            });

            IBLVaultManagerLido.OracleFeed memory ohmEthPriceFeedData = IBLVaultManagerLido
                .OracleFeed({feed: ohmEthPriceFeed, updateThreshold: uint48(1 days)});

            IBLVaultManagerLido.OracleFeed memory ethUsdPriceFeedData = IBLVaultManagerLido
                .OracleFeed({feed: ethUsdPriceFeed, updateThreshold: uint48(1 days)});

            IBLVaultManagerLido.OracleFeed memory stethUsdPriceFeedData = IBLVaultManagerLido
                .OracleFeed({feed: stethUsdPriceFeed, updateThreshold: uint48(1 days)});

            vaultManager = new BLVaultManagerLido(
                kernel,
                tokenData,
                balancerData,
                auraData,
                address(0),
                ohmEthPriceFeedData,
                ethUsdPriceFeedData,
                stethUsdPriceFeedData,
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
            stethUsdPriceFeed.setTimestamp(block.timestamp);
        }

        // Prepare alice's account
        {
            // Mint OHM to alice
            wsteth.mint(alice, 100e18);

            // Create alice's vault
            vm.startPrank(alice);
            aliceVault = BLVaultLido(vaultManager.deployVault());

            // Approve wstETH to alice's vault
            wsteth.approve(address(aliceVault), type(uint256).max);
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
    ///     [X]  correctly deploys liquidity when oracle price < pool price
    ///     [X]  correctly deploys liquidity when oracle price > pool price

    function testCorrectness_depositCanOnlyBeCalledWhenManagerIsActive() public {
        // Deactivate vault manager
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLVaultLido_Inactive()");
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
            bytes memory err = abi.encodeWithSignature("BLVaultLido_OnlyOwner()");
            vm.expectRevert(err);

            // Try to deposit
            vm.prank(attacker_);
            aliceVault.deposit(1e18, 0);
        }
    }

    function testCorrectness_depositCorrectlyIncreasesState(uint256 depositAmount_) public {
        vm.assume(depositAmount_ > 1e9 && depositAmount_ < 1_000_000_000_000e18);

        // Set limit based on deposit amount
        uint256 newLimit = (vaultManager.getOhmTknPrice() * depositAmount_) / 1e18;
        vaultManager.setLimit(newLimit);

        // Mint more wstETH to alice
        wsteth.mint(alice, depositAmount_);

        // Approve wstETH to alice's vault
        vm.startPrank(alice);
        wsteth.approve(address(aliceVault), type(uint256).max);

        // Verify state before
        assertEq(vaultManager.deployedOhm(), 0);
        assertEq(vaultManager.totalLp(), 0);

        // Deposit
        aliceVault.deposit(depositAmount_, 0);
        vm.stopPrank();

        // Verify state after
        assertEq(vaultManager.deployedOhm(), newLimit);
        assertEq(vaultManager.totalLp(), depositAmount_);
    }

    function testCorrectness_depositCorrectlyDeploysLiquidity() public {
        // Verify state before
        assertEq(ohm.balanceOf(address(vault)), 0);
        assertEq(wsteth.balanceOf(address(vault)), 0);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 0);

        // Deposit wstETH
        vm.prank(alice);
        aliceVault.deposit(100e18, 0);

        // Verify state after
        uint256 expectedOhmAmount = (100e18 * vaultManager.getOhmTknPrice()) / 1e18;
        assertEq(ohm.balanceOf(address(vault)), expectedOhmAmount);
        assertEq(wsteth.balanceOf(address(vault)), 100e18);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 100e18);
    }

    function testCorrectness_depositCorrectlyDeploysLiquidityOracleValueLow() public {
        // Set oracle price to 0.5
        ohmEthPriceFeed.setLatestAnswer(0.5e18);

        // Verify state before
        assertEq(ohm.balanceOf(address(vault)), 0);
        assertEq(wsteth.balanceOf(address(vault)), 0);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 0);

        // Deposit wstETH
        vm.prank(alice);
        aliceVault.deposit(100e18, 0);

        // Verify state after
        uint256 expectedOhmAmount = (100e18 * vaultManager.getOhmTknPrice()) / 1e18;
        assertEq(ohm.balanceOf(address(vault)), expectedOhmAmount);
        assertEq(wsteth.balanceOf(address(vault)), 100e18);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 100e18);
    }

    function testCorrectness_depositCorrectlyDeploysLiquidityOracleValueHigh() public {
        // Set oracle price to 0.001
        ohmEthPriceFeed.setLatestAnswer(1e15);

        // Verify state before
        assertEq(ohm.balanceOf(address(vault)), 0);
        assertEq(wsteth.balanceOf(address(vault)), 0);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 0);

        // Deposit wstETH
        vm.prank(alice);
        aliceVault.deposit(100e18, 0);

        // Verify state after
        // TODO change 100e9 to ohmWstethPoolPrice
        uint256 expectedOhmAmount = (100e18 * 100e9) / 1e18;
        assertEq(ohm.balanceOf(address(vault)), expectedOhmAmount);
        assertEq(wsteth.balanceOf(address(vault)), 100e18);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 100e18);
    }

    /// [X]  withdraw
    ///     [X]  can only be called when the manager is active
    ///     [X]  can only be called by the vault's owner
    ///     [X]  fails if not enough wstETH will be sent
    ///     [X]  fails if the cooldown period has not passed
    ///     [X]  correctly decreases state values (deployedOhm and totalLp)
    ///     [X]  correctly withdraws liquidity
    ///     [X]  correctly withdraws liquidity when oracle price differs from pool price

    function _withdrawSetup() internal {
        // Deposit wstETH
        vm.prank(alice);
        aliceVault.deposit(100e18, 0);

        // Wait 1 day to pass the cooldown period
        vm.warp(block.timestamp + 1 days);
    }

    function testCorrectness_withdrawFailsIfCooldownPeriodHasNotPassed() public {
        // Deposit wstETH
        vm.prank(alice);
        aliceVault.deposit(100e18, 0);

        bytes memory err = abi.encodeWithSignature("BLVaultLido_WithdrawalDelay()");
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
            bytes memory err = abi.encodeWithSignature("BLVaultLido_OnlyOwner()");
            vm.expectRevert(err);

            // Try to withdraw
            vm.prank(attacker_);
            aliceVault.withdraw(1e18, minAmountsOut, 0, true);
        }
    }

    function testCorrectness_withdrawFailsIfNotEnoughWstethWillBeSent() public {
        _withdrawSetup();

        // Set price to 0.001
        ohmEthPriceFeed.setLatestAnswer(1e15);

        bytes memory err = abi.encodeWithSignature("BLVaultLido_WithdrawFailedPriceImbalance()");
        vm.expectRevert(err);

        // Try to withdraw
        vm.prank(alice);
        aliceVault.withdraw(1e18, minAmountsOut, 90e18, true);
    }

    function testCorrectness_withdrawCorrectlyDecreasesState(uint256 withdrawAmount_) public {
        _withdrawSetup();

        // Get alice vault's Lp balance
        uint256 aliceLpBalance = aliceVault.getLpBalance();
        vm.assume(withdrawAmount_ <= aliceLpBalance);

        // Check state before
        assertEq(vaultManager.deployedOhm(), 10_000e9);
        assertEq(vaultManager.totalLp(), aliceLpBalance);

        // Withdraw
        vm.prank(alice);
        aliceVault.withdraw(withdrawAmount_, minAmountsOut, 0, true);

        // Check state after
        assertTrue(vaultManager.deployedOhm() < 10_000e9);
        assertEq(vaultManager.totalLp(), aliceLpBalance - withdrawAmount_);
    }

    function testCorrectness_withdrawCorrectlyWithdrawsLiquidity() public {
        _withdrawSetup();

        // Get alice vault's LP balance
        uint256 aliceLpBalance = aliceVault.getLpBalance();

        // Check state before
        assertEq(ohm.balanceOf(address(vault)), 10_000e9);
        assertEq(wsteth.balanceOf(address(vault)), aliceLpBalance);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), aliceLpBalance);

        // Withdraw
        vm.prank(alice);
        aliceVault.withdraw(aliceLpBalance, minAmountsOut, 0, true);

        // Check state after
        assertEq(ohm.balanceOf(address(vault)), 0);
        assertEq(wsteth.balanceOf(address(vault)), 0);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 0);
    }

    function testCorrectness_withdrawCorrectlyWithdrawsLiquidityPriceDiff() public {
        _withdrawSetup();

        // Set oracle price to 0.001
        ohmEthPriceFeed.setLatestAnswer(1e15);

        // Get alice vault's LP balance
        uint256 aliceLpBalance = aliceVault.getLpBalance();

        // Check state before
        assertEq(ohm.balanceOf(address(vault)), 10_000e9);
        assertEq(wsteth.balanceOf(address(vault)), aliceLpBalance);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), aliceLpBalance);

        // Withdraw
        vm.prank(alice);
        aliceVault.withdraw(aliceLpBalance, minAmountsOut, 0, true);

        // Check state after
        assertEq(ohm.balanceOf(address(vault)), 0);
        assertEq(wsteth.balanceOf(address(vault)), 0);
        assertEq(wsteth.balanceOf(address(alice)), 10e18);
        assertEq(wsteth.balanceOf(address(treasury)), 90e18);
        assertEq(ERC20(vault.bpt()).balanceOf(address(auraPool)), 0);
    }

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

        bytes memory err = abi.encodeWithSignature("BLVaultLido_Inactive()");
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
            bytes memory err = abi.encodeWithSignature("BLVaultLido_OnlyOwner()");
            vm.expectRevert(err);

            // Try to claim rewards
            vm.prank(attacker_);
            aliceVault.claimRewards();
        }
    }

    function testCorrectness_claimRewardsCorrectlyClaims() public {
        // Deposit wstETH
        _withdrawSetup();

        // Check state before
        assertEq(bal.balanceOf(address(alice)), 0);

        // Claim rewards
        vm.prank(alice);
        aliceVault.claimRewards();

        // Check state after
        assertEq(bal.balanceOf(address(alice)), 1e18);
    }

    //============================================================================================//
    //                                        VIEW FUNCTIONS                                      //
    //============================================================================================//

    /// [X]  getLpBalance
    ///     [X]  returns the correct LP balance

    function testCorrectness_getLpBalance(uint256 depositAmount_) public {
        vm.assume(depositAmount_ > 1e9 && depositAmount_ < 1_000_000_000_000e18);

        // Set limit based on deposit amount
        uint256 newLimit = (vaultManager.getOhmTknPrice() * depositAmount_) / 1e18;
        vaultManager.setLimit(newLimit);

        // Mint more wstETH to alice
        wsteth.mint(alice, depositAmount_);

        // Approve wstETH to alice's vault
        vm.startPrank(alice);
        wsteth.approve(address(aliceVault), type(uint256).max);

        // Check state before
        assertEq(aliceVault.getLpBalance(), 0);

        // Deposit
        aliceVault.deposit(depositAmount_, 0);
        vm.stopPrank();

        // Check state after
        assertEq(aliceVault.getLpBalance(), depositAmount_);
    }

    /// [X]  getUserPairShare
    ///     [X]  returns the correct user wstETH share

    function testCorrectness_getUserPairShare(uint256 depositAmount_) public {
        vm.assume(depositAmount_ > 1e9 && depositAmount_ < 1_000_000_000_000e18);

        // Set limit based on deposit amount
        uint256 newLimit = (vaultManager.getOhmTknPrice() * depositAmount_) / 1e18;
        vaultManager.setLimit(newLimit);

        // Mint more wstETH to alice
        wsteth.mint(alice, depositAmount_);

        // Approve wstETH to alice's vault
        vm.startPrank(alice);
        wsteth.approve(address(aliceVault), type(uint256).max);

        // Check state before
        assertEq(aliceVault.getUserPairShare(), 0);

        // Deposit
        aliceVault.deposit(depositAmount_, 0);
        vm.stopPrank();

        // Set pool amounts to true balances
        vault.setPoolAmounts(ohm.balanceOf(address(vault)), wsteth.balanceOf(address(vault)));

        // Calculate expected share
        uint256 tknOhmPrice = vaultManager.getTknOhmPrice();
        uint256 userOhmShare = (depositAmount_ * ohm.balanceOf(address(vault))) /
            liquidityPool.totalSupply();
        uint256 expectedWstethShare = (userOhmShare * tknOhmPrice) / 1e9;
        uint256 expectedShare = depositAmount_ > expectedWstethShare
            ? expectedWstethShare
            : depositAmount_;

        // Check state after
        assertEq(aliceVault.getUserPairShare(), expectedShare);
    }
}
