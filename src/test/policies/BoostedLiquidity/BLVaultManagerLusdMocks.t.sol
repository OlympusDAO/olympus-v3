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
import {MockAuraBooster, MockAuraRewardPool, MockAuraMiningLib} from "test/mocks/AuraMocks.sol";

import {OlympusERC20Token, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import {IAuraBooster, IAuraRewardPool} from "policies/BoostedLiquidity/interfaces/IAura.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusBoostedLiquidityRegistry} from "modules/BLREG/OlympusBoostedLiquidityRegistry.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {IBLVaultManager, BLVaultManagerLusd} from "policies/BoostedLiquidity/BLVaultManagerLusd.sol";
import {BLVaultLusd} from "policies/BoostedLiquidity/BLVaultLusd.sol";

import {RewardsData} from "policies/BoostedLiquidity/interfaces/IBLVault.sol";

import "src/Kernel.sol";

import {console2} from "forge-std/console2.sol";

// solhint-disable-next-line max-states-count
contract BLVaultManagerLusdTest is Test {
    using FullMath for uint256;
    using larping for *;

    UserFactory public userCreator;
    address internal alice;

    OlympusERC20Token internal ohm;
    MockERC20 internal lusd;
    MockERC20 internal aura;
    MockERC20 internal bal;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;
    MockPriceFeed internal lusdUsdPriceFeed;

    MockVault internal vault;
    MockBalancerPool internal liquidityPool;

    MockAuraBooster internal booster;
    MockAuraRewardPool internal auraPool;
    MockAuraMiningLib internal auraMiningLib;

    IOlympusAuthority internal auth;

    Kernel internal kernel;
    OlympusMinter internal minter;
    OlympusTreasury internal treasury;
    OlympusBoostedLiquidityRegistry internal blreg;
    OlympusRoles internal roles;

    RolesAdmin internal rolesAdmin;
    BLVaultManagerLusd internal vaultManager;
    BLVaultLusd internal vaultImplementation;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Deploy mock users
        {
            userCreator = new UserFactory();
            address[] memory users = userCreator.create(1);
            alice = users[0];
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
            vault = new MockVault(address(liquidityPool), address(ohm), address(lusd));
            vault.setPoolAmounts(100e9, 1000e18);
        }

        // Deploy mock Aura contracts
        {
            auraPool = new MockAuraRewardPool(address(vault.bpt()), address(bal), address(aura));
            booster = new MockAuraBooster(address(vault.bpt()), address(auraPool));
            auraMiningLib = new MockAuraMiningLib();
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

        // Initialize timestamps on mock price feeds
        {
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            ethUsdPriceFeed.setTimestamp(block.timestamp);
            lusdUsdPriceFeed.setTimestamp(block.timestamp);
        }

        // Mint LUSD to alice
        {
            lusd.mint(alice, 100e18);
        }
    }

    /// Deploys `vault_` and sets up the policies
    function deployPolicies(MockVault vault_) internal {
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
                vault: address(vault_),
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
                address(auraMiningLib),
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
    }

    //============================================================================================//
    //                                         CORE FUNCTIONS                                     //
    //============================================================================================//

    /// [X]  deployVault
    ///     [X]  can only be called when system is active
    ///     [X]  can be called by anyone
    ///     [X]  fails if user already has vault
    ///     [X]  correctly deploys new vault
    ///     [X]  correctly tracks vaults state

    function testCorrectness_deployVaultFailsWhenBLInactive() public {
        deployPolicies(vault);

        // Deactivate contract
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_Inactive()");
        vm.expectRevert(err);

        vaultManager.deployVault();
    }

    function testCorrectness_deployVaultCanBeCalledByAnyone(address user_) public {
        deployPolicies(vault);

        vm.prank(user_);
        vaultManager.deployVault();
    }

    function testCorrectness_deployVaultFailsIfUserAlreadyHasVault() public {
        deployPolicies(vault);

        // Create first vault
        vm.prank(alice);
        vaultManager.deployVault();

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_VaultAlreadyExists()");
        vm.expectRevert(err);

        // Try to create second vault
        vm.prank(alice);
        vaultManager.deployVault();
    }

    function testCorrectness_deployVaultCorrectlyClonesVault() public {
        deployPolicies(vault);

        // Create vault
        vm.prank(alice);
        BLVaultLusd aliceVault = BLVaultLusd(vaultManager.deployVault());

        // Verify vault state
        assertEq(aliceVault.owner(), alice);
        assertEq(address(aliceVault.manager()), address(vaultManager));
        assertEq(aliceVault.TRSRY(), address(treasury));
        assertEq(address(aliceVault.ohm()), address(ohm));
        assertEq(address(aliceVault.lusd()), address(lusd));
        assertEq(address(aliceVault.aura()), address(aura));
        assertEq(address(aliceVault.bal()), address(bal));
        assertEq(address(aliceVault.vault()), address(vault));
        assertEq(address(aliceVault.liquidityPool()), address(liquidityPool));
        assertEq(aliceVault.pid(), 0);
        assertEq(address(aliceVault.auraBooster()), address(booster));
        assertEq(address(aliceVault.auraRewardPool()), address(auraPool));
        assertEq(aliceVault.fee(), 0);
    }

    function testCorrectness_deployVaultCorrectlyTracksVaultState(address user_) public {
        deployPolicies(vault);

        vm.prank(user_);
        BLVaultLusd userVault = BLVaultLusd(vaultManager.deployVault());

        // Verify manager state
        assertEq(vaultManager.vaultOwners(userVault), user_);
        assertEq(address(vaultManager.userVaults(user_)), address(userVault));
    }

    /// [X]  mintOhmToVault
    ///     [X]  can only be called when system is active
    ///     [X]  can only be called by an approved vault
    ///     [X]  cannot mint beyond the limit
    ///     [X]  increases deployedOhm value
    ///     [X]  mints OHM to correct address

    function _createVault() internal returns (address) {
        vm.prank(alice);
        address aliceVault = vaultManager.deployVault();

        return aliceVault;
    }

    function testCorrectness_mintOhmToVaultFailsWhenBLInactive() public {
        deployPolicies(vault);

        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_Inactive()");
        vm.expectRevert(err);

        vaultManager.mintOhmToVault(1e9);
    }

    function testCorrectness_mintOhmToVaultCanOnlyBeCalledByApprovedVault(
        address attacker_
    ) public {
        deployPolicies(vault);

        address validVault = _createVault();

        vm.prank(validVault);
        vaultManager.mintOhmToVault(1e9);

        if (attacker_ != validVault) {
            bytes memory err = abi.encodeWithSignature("BLManagerLusd_InvalidVault()");
            vm.expectRevert(err);

            vm.prank(attacker_);
            vaultManager.mintOhmToVault(1e9);
        }
    }

    function testCorrectness_mintOhmToVaultCannotMintBeyondLimit(uint256 amount_) public {
        vm.assume(amount_ != 0);

        deployPolicies(vault);

        address validVault = _createVault();

        if (amount_ <= vaultManager.ohmLimit()) {
            vm.prank(validVault);
            vaultManager.mintOhmToVault(amount_);
        } else {
            bytes memory err = abi.encodeWithSignature("BLManagerLusd_LimitViolation()");
            vm.expectRevert(err);

            vm.prank(validVault);
            vaultManager.mintOhmToVault(amount_);
        }
    }

    function testCorrectness_mintOhmToVaultIncreasesDeployedOhmValue(uint256 amount_) public {
        deployPolicies(vault);

        vm.assume(amount_ != 0 && amount_ <= vaultManager.ohmLimit());

        address validVault = _createVault();

        // Check state before
        assertEq(vaultManager.deployedOhm(), 0);

        // Mint OHM
        vm.prank(validVault);
        vaultManager.mintOhmToVault(amount_);

        // Check state after
        assertEq(vaultManager.deployedOhm(), amount_);
    }

    function testCorrectness_mintOhmToVaultMintsToCorrectAddress() public {
        deployPolicies(vault);

        address validVault = _createVault();

        // Check balance before
        assertEq(ohm.balanceOf(validVault), 0);

        // Mint OHM
        vm.prank(validVault);
        vaultManager.mintOhmToVault(1e9);

        // Check balance after
        assertEq(ohm.balanceOf(validVault), 1e9);
    }

    /// [X]  burnOhmFromVault
    ///     [X]  can only be called when system is active
    ///     [X]  can only be called by an approved vault
    ///     [X]  correctly updates deployedOhm and circulatingOhmBurned
    ///     [X]  burns OHM from correct address

    function testCorrectness_burnOhmFromVaultFailsWhenBLInactive() public {
        deployPolicies(vault);

        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_Inactive()");
        vm.expectRevert(err);

        vaultManager.burnOhmFromVault(1e9);
    }

    function testCorrectness_burnOhmFromVaultCanOnlyBeCalledByAnApprovedVault(
        address attacker_
    ) public {
        deployPolicies(vault);

        // Setup
        address validVault = _createVault();
        vm.prank(validVault);
        vaultManager.mintOhmToVault(1e9);

        // If address is valid
        vm.startPrank(validVault);
        ohm.increaseAllowance(address(minter), 1e9);
        vaultManager.burnOhmFromVault(1e9);
        vm.stopPrank();

        if (attacker_ != validVault) {
            bytes memory err = abi.encodeWithSignature("BLManagerLusd_InvalidVault()");
            vm.expectRevert(err);

            vm.prank(attacker_);
            vaultManager.burnOhmFromVault(1e9);
        }
    }

    function testCorrectness_burnOhmFromVaultCorrectlyUpdatesState(uint256 amount_) public {
        vm.assume(amount_ != 0 && amount_ <= 100_000_000e9);

        deployPolicies(vault);

        // Setup
        address validVault = _createVault();
        vaultManager.setLimit(50_000_000e9);

        // Mint base amount
        vm.startPrank(address(vaultManager));
        minter.increaseMintApproval(address(vaultManager), 50_000_000e9);
        minter.mintOhm(validVault, 50_000_000e9);
        vm.stopPrank();

        vm.startPrank(validVault);
        vaultManager.mintOhmToVault(50_000_000e9);
        ohm.increaseAllowance(address(minter), 100_000_000e9);

        // Check state before
        assertEq(vaultManager.deployedOhm(), 50_000_000e9);
        assertEq(vaultManager.circulatingOhmBurned(), 0);

        vaultManager.burnOhmFromVault(amount_);

        // Check state after
        if (amount_ > 50_000_000e9) {
            assertEq(vaultManager.deployedOhm(), 0);
            assertEq(vaultManager.circulatingOhmBurned(), amount_ - 50_000_000e9);
        } else {
            assertEq(vaultManager.deployedOhm(), 50_000_000e9 - amount_);
            assertEq(vaultManager.circulatingOhmBurned(), 0);
        }

        vm.stopPrank();
    }

    function testCorrectness_burnOhmFromVaultBurnsFromCorrectAddress() public {
        deployPolicies(vault);

        address validVault = _createVault();

        vm.startPrank(validVault);
        vaultManager.mintOhmToVault(1e9);
        ohm.increaseAllowance(address(minter), 1e9);

        // Check balance before
        assertEq(ohm.balanceOf(validVault), 1e9);

        // Burn OHM
        vaultManager.burnOhmFromVault(1e9);

        // Check balance after
        assertEq(ohm.balanceOf(validVault), 0);
        vm.stopPrank();
    }

    /// [X]  increaseTotalLp
    ///     [X]  can only be called when system is active
    ///     [X]  can only be called by an approved vault
    ///     [X]  increases totalLp value

    function testCorrectness_increaseTotalLpFailsWhenInactive() public {
        deployPolicies(vault);

        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_Inactive()");
        vm.expectRevert(err);

        vaultManager.increaseTotalLp(1e18);
    }

    function testCorrectness_increaseTotalLpCanOnlyBeCalledByAnApprovedVault(
        address attacker_
    ) public {
        deployPolicies(vault);

        // Setup
        address validVault = _createVault();

        // If address is valid
        vm.prank(validVault);
        vaultManager.increaseTotalLp(1e18);

        if (attacker_ != validVault) {
            bytes memory err = abi.encodeWithSignature("BLManagerLusd_InvalidVault()");
            vm.expectRevert(err);

            vm.prank(attacker_);
            vaultManager.increaseTotalLp(1e18);
        }
    }

    function testCorrectness_increaseTotalLpCorrectlyIncreasesValue(uint256 amount_) public {
        deployPolicies(vault);

        address validVault = _createVault();

        // Check state before
        assertEq(vaultManager.totalLp(), 0);

        // Increase total LP amount
        vm.prank(validVault);
        vaultManager.increaseTotalLp(amount_);

        // Check state after
        assertEq(vaultManager.totalLp(), amount_);
    }

    /// [X]  decreaseTotalLp
    ///     [X]  can only be called when system is active
    ///     [X]  can only be called by an approved vault
    ///     [X]  decreases totalLp value

    function testCorrectness_decreaseTotalLpFailsWhenBLInactive() public {
        deployPolicies(vault);

        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_Inactive()");
        vm.expectRevert(err);

        vaultManager.decreaseTotalLp(1e18);
    }

    function testCorrectness_decreaseTotalLpCanOnlyBeCalledByAnApprovedVault(
        address attacker_
    ) public {
        deployPolicies(vault);

        // Setup
        address validVault = _createVault();

        // If address is valid
        vm.startPrank(validVault);
        vaultManager.increaseTotalLp(1e18);
        vaultManager.decreaseTotalLp(1e18);
        vm.stopPrank();

        if (attacker_ != validVault) {
            bytes memory err = abi.encodeWithSignature("BLManagerLusd_InvalidVault()");
            vm.expectRevert(err);

            vm.prank(attacker_);
            vaultManager.decreaseTotalLp(1e18);
        }
    }

    function testCorrectness_decreaseTotalLpCorrectlyDecreasesValue(uint256 amount_) public {
        deployPolicies(vault);

        address validVault = _createVault();

        // Increase total LP
        vm.startPrank(validVault);
        vaultManager.increaseTotalLp(amount_);

        // Check state before
        assertEq(vaultManager.totalLp(), amount_);

        // Decrease total LP
        vaultManager.decreaseTotalLp(amount_);

        // Check state after
        assertEq(vaultManager.totalLp(), 0);
        vm.stopPrank();
    }

    //============================================================================================//
    //                                         VIEW FUNCTIONS                                     //
    //============================================================================================//

    /// [X]  getLpBalance
    ///     [X]  returns the correct LP value

    function testCorrectness_getLpBalance(uint256 ohmIndex_) public {
        // Set up the vault based on the fuzzing
        uint256 ohmIndex = bound(ohmIndex_, 0, 1);
        vault = new MockVault(
            address(liquidityPool),
            ohmIndex == 0 ? address(ohm) : address(lusd),
            ohmIndex == 0 ? address(lusd) : address(ohm)
        );
        vault.setPoolAmounts(ohmIndex == 0 ? 1e9 : 10e18, ohmIndex == 0 ? 10e18 : 1e9);

        deployPolicies(vault);

        address aliceVault = _createVault();

        // Check state before
        assertEq(vaultManager.getLpBalance(alice), 0);

        // Deposit LUSD
        vm.startPrank(alice);
        lusd.approve(aliceVault, type(uint256).max);
        BLVaultLusd(aliceVault).deposit(1e18, 0);
        vm.stopPrank();

        // Check state after
        assertEq(vaultManager.getLpBalance(alice), 1e18);
    }

    /// [X]  getUserPairShare
    ///     [X]  returns correct user LUSD share

    function testCorrectness_getUserPairShare(uint256 ohmIndex_) public {
        // Set up the vault based on the fuzzing
        uint256 ohmIndex = bound(ohmIndex_, 0, 1);
        vault = new MockVault(
            address(liquidityPool),
            ohmIndex == 0 ? address(ohm) : address(lusd),
            ohmIndex == 0 ? address(lusd) : address(ohm)
        );
        vault.setPoolAmounts(ohmIndex == 0 ? 1e9 : 10e18, ohmIndex == 0 ? 10e18 : 1e9);

        deployPolicies(vault);

        address aliceVault = _createVault();

        // Check state before
        assertEq(vaultManager.getUserPairShare(alice), 0);

        // Deposit LUSD
        vm.startPrank(alice);
        lusd.approve(aliceVault, type(uint256).max);
        BLVaultLusd(aliceVault).deposit(1e18, 0);
        vm.stopPrank();

        // Set pool amounts to current balance
        uint256 vaultLusdBalance = lusd.balanceOf(address(vault));
        vault.setPoolAmounts(100e9, vaultLusdBalance);

        // Check state after
        assertEq(vaultManager.getUserPairShare(alice), 1e18);
    }

    /// [X]  getOutstandingRewards
    ///     [X]  returns correct outstanding rewards

    function testCorrectness_getOutstandingRewards(uint256 ohmIndex_) public {
        // Set up the vault based on the fuzzing
        uint256 ohmIndex = bound(ohmIndex_, 0, 1);
        vault = new MockVault(
            address(liquidityPool),
            ohmIndex == 0 ? address(ohm) : address(lusd),
            ohmIndex == 0 ? address(lusd) : address(ohm)
        );
        vault.setPoolAmounts(ohmIndex == 0 ? 1e9 : 10e18, ohmIndex == 0 ? 10e18 : 1e9);

        deployPolicies(vault);

        address aliceVault = _createVault();

        // Deposit LUSD
        vm.startPrank(alice);
        lusd.approve(aliceVault, type(uint256).max);
        BLVaultLusd(aliceVault).deposit(1e18, 0);
        vm.stopPrank();

        // Check state after
        RewardsData[] memory rewards = vaultManager.getOutstandingRewards(alice);
        assertEq(rewards.length, 2);
        assertEq(rewards[0].rewardToken, address(bal));
        assertEq(rewards[0].outstandingRewards, 1e18);
        assertEq(rewards[1].rewardToken, address(aura));
        assertEq(rewards[1].outstandingRewards, 1e18);
    }

    /// [X]  getMaxDeposit
    ///     [X]  returns correct LUSD deposit amount

    function testCorrectness_getMaxDeposit(uint256 ohmIndex_) public {
        // Set up the vault based on the fuzzing
        uint256 ohmIndex = bound(ohmIndex_, 0, 1);
        vault = new MockVault(
            address(liquidityPool),
            ohmIndex == 0 ? address(ohm) : address(lusd),
            ohmIndex == 0 ? address(lusd) : address(ohm)
        );
        vault.setPoolAmounts(ohmIndex == 0 ? 1e9 : 10e18, ohmIndex == 0 ? 10e18 : 1e9);

        deployPolicies(vault);

        address aliceVault = _createVault();

        // Check state before
        assertEq(vaultManager.getMaxDeposit(), 1_000_000e18);

        // Increase OHM minted
        vm.prank(aliceVault);
        vaultManager.mintOhmToVault(99_900e9);

        // Check state after
        assertEq(vaultManager.getMaxDeposit(), 1000e18);
    }

    /// [X]  getRewardTokens
    ///     [X]  returns correct reward token array

    function testCorrectness_getRewardTokens() public {
        deployPolicies(vault);

        address[] memory tokens = vaultManager.getRewardTokens();

        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(aura));
        assertEq(tokens[1], address(bal));
    }

    /// [X]  getRewardRate
    ///     [X]  returns correct reward rate for Bal

    function testCorrectness_getRewardRate() public {
        deployPolicies(vault);

        uint256 rate = vaultManager.getRewardRate(address(bal));

        assertEq(rate, 1e18);
    }

    /// [X]  getPoolOhmShare
    ///     [X]  returns correct pool OHM share
    ///     [X]  0 total supply

    function testCorrectness_getPoolOhmShare(uint256 ohmIndex_) public {
        // Set up the vault based on the fuzzing
        uint256 ohmIndex = bound(ohmIndex_, 0, 1);
        vault = new MockVault(
            address(liquidityPool),
            ohmIndex == 0 ? address(ohm) : address(lusd),
            ohmIndex == 0 ? address(lusd) : address(ohm)
        );
        vault.setPoolAmounts(ohmIndex == 0 ? 1e9 : 10e18, ohmIndex == 0 ? 10e18 : 1e9);

        deployPolicies(vault);

        // Test base case
        uint256 poolOhmShare = vaultManager.getPoolOhmShare();
        assertEq(poolOhmShare, 0);

        // Deposit
        address validVault = _createVault();

        vm.startPrank(alice);
        lusd.approve(validVault, type(uint256).max);
        BLVaultLusd(validVault).deposit(10e18, 0);
        vm.stopPrank();

        // Set pool amounts to current balance
        uint256 vaultOhmBalance = ohm.balanceOf(address(vault));
        vault.setPoolAmounts(vaultOhmBalance, 1000e18);

        // Check state after
        poolOhmShare = vaultManager.getPoolOhmShare();
        assertEq(poolOhmShare, 1e9);
    }

    function testCorrectness_getPoolOhmShare_zeroTotalSupply(uint256 ohmIndex_) public {
        // Set up the vault based on the fuzzing
        uint256 ohmIndex = bound(ohmIndex_, 0, 1);
        vault = new MockVault(
            address(liquidityPool),
            ohmIndex == 0 ? address(ohm) : address(lusd),
            ohmIndex == 0 ? address(lusd) : address(ohm)
        );
        vault.setPoolAmounts(ohmIndex == 0 ? 1e9 : 10e18, ohmIndex == 0 ? 10e18 : 1e9);

        deployPolicies(vault);

        // Test base case
        uint256 poolOhmShare = vaultManager.getPoolOhmShare();
        assertEq(poolOhmShare, 0);

        // Deposit
        address validVault = _createVault();

        vm.startPrank(alice);
        lusd.approve(validVault, type(uint256).max);
        BLVaultLusd(validVault).deposit(10e18, 0);
        vm.stopPrank();

        // Set pool amounts to current balance
        uint256 vaultOhmBalance = ohm.balanceOf(address(vault));
        vault.setPoolAmounts(vaultOhmBalance, 1000e18);

        // Change total supply to 0
        liquidityPool.setTotalSupply(0);

        // Check state after
        poolOhmShare = vaultManager.getPoolOhmShare();
        assertEq(poolOhmShare, 0); // 1e9 if total supply were not 0
    }

    /// [X]  getOhmSupplyChangeData
    ///     [X]  returns correct data

    function testCorrectness_getOhmSupplyChangeData(uint256 ohmIndex_) public {
        // Set up the vault based on the fuzzing
        uint256 ohmIndex = bound(ohmIndex_, 0, 1);
        vault = new MockVault(
            address(liquidityPool),
            ohmIndex == 0 ? address(ohm) : address(lusd),
            ohmIndex == 0 ? address(lusd) : address(ohm)
        );
        vault.setPoolAmounts(ohmIndex == 0 ? 1e9 : 10e18, ohmIndex == 0 ? 10e18 : 1e9);

        deployPolicies(vault);

        // Test base case
        (uint256 poolOhmShare, uint256 ohmMinted, uint256 ohmBurned) = vaultManager
            .getOhmSupplyChangeData();
        assertEq(poolOhmShare, 0);
        assertEq(ohmMinted, 0);
        assertEq(ohmBurned, 0);

        // Test with minted OHM
        address validVault = _createVault();

        vm.prank(validVault);
        vaultManager.mintOhmToVault(1e9);

        (poolOhmShare, ohmMinted, ohmBurned) = vaultManager.getOhmSupplyChangeData();
        assertEq(poolOhmShare, 0);
        assertEq(ohmMinted, 1e9);
        assertEq(ohmBurned, 0);

        // Test with burned OHM
        vm.startPrank(address(vaultManager));
        minter.increaseMintApproval(address(vaultManager), 10e9);
        minter.mintOhm(validVault, 10e9);
        vm.stopPrank();

        vm.startPrank(validVault);
        ohm.increaseAllowance(address(minter), 11e9);
        vaultManager.burnOhmFromVault(11e9);
        vm.stopPrank();

        (poolOhmShare, ohmMinted, ohmBurned) = vaultManager.getOhmSupplyChangeData();
        assertEq(poolOhmShare, 0);
        assertEq(ohmMinted, 0);
        assertEq(ohmBurned, 10e9);

        // Test with proper deposit
        vm.startPrank(alice);
        lusd.approve(validVault, type(uint256).max);
        BLVaultLusd(validVault).deposit(10e18, 0);
        vm.stopPrank();

        // Set pool amounts to current balance
        uint256 vaultOhmBalance = ohm.balanceOf(address(vault));
        vault.setPoolAmounts(vaultOhmBalance, 1000e18);

        (poolOhmShare, ohmMinted, ohmBurned) = vaultManager.getOhmSupplyChangeData();
        assertEq(poolOhmShare, 1e9);
        assertEq(ohmMinted, 1e9);
        assertEq(ohmBurned, 10e9);
    }

    /// [X]  getOhmTknPrice
    ///     [X]  returns correct OHM per LUSD (0.1)

    function testCorrectness_getOhmTknPrice(uint256 ohmIndex_) public {
        // Set up the vault based on the fuzzing
        uint256 ohmIndex = bound(ohmIndex_, 0, 1);
        vault = new MockVault(
            address(liquidityPool),
            ohmIndex == 0 ? address(ohm) : address(lusd),
            ohmIndex == 0 ? address(lusd) : address(ohm)
        );
        vault.setPoolAmounts(ohmIndex == 0 ? 1e9 : 10e18, ohmIndex == 0 ? 10e18 : 1e9);

        deployPolicies(vault);

        // Test base case
        uint256 price = vaultManager.getOhmTknPrice();
        assertEq(price, 1e8);

        // Increase OHM value
        ohmEthPriceFeed.setLatestAnswer(1e17); // 0.1 ETH
        price = vaultManager.getOhmTknPrice();
        assertEq(price, 1e7);
    }

    /// [X]  getTknOhmPrice
    ///     [X]  returns correct LUSD per OHM (10)

    function testCorrectness_getTknOhmPrice(uint256 ohmIndex_) public {
        // Set up the vault based on the fuzzing
        uint256 ohmIndex = bound(ohmIndex_, 0, 1);
        vault = new MockVault(
            address(liquidityPool),
            ohmIndex == 0 ? address(ohm) : address(lusd),
            ohmIndex == 0 ? address(lusd) : address(ohm)
        );
        vault.setPoolAmounts(ohmIndex == 0 ? 1e9 : 10e18, ohmIndex == 0 ? 10e18 : 1e9);

        deployPolicies(vault);

        // Test base case
        uint256 price = vaultManager.getTknOhmPrice();
        assertEq(price, 10e18);

        // Increase OHM value
        ohmEthPriceFeed.setLatestAnswer(1e17); // 0.1 ETH
        price = vaultManager.getTknOhmPrice();
        assertEq(price, 100e18);
    }

    /// [X] getOhmTknPoolPrice
    ///     [X] returns correct OHM per LUSD
    ///     [X] returns 0 if pool is empty

    function testCorrectness_getOhmTknPoolPrice(uint256 ohmIndex_) public {
        // Set up the vault based on the fuzzing
        uint256 ohmIndex = bound(ohmIndex_, 0, 1);
        vault = new MockVault(
            address(liquidityPool),
            ohmIndex == 0 ? address(ohm) : address(lusd),
            ohmIndex == 0 ? address(lusd) : address(ohm)
        );
        vault.setPoolAmounts(ohmIndex == 0 ? 1e9 : 10e18, ohmIndex == 0 ? 10e18 : 1e9);

        deployPolicies(vault);

        // Base case
        uint256 price = vaultManager.getOhmTknPoolPrice();
        // 100e9 * 1e18 / 1000e18 = 0.1e9 = 1e8
        assertEq(price, 1e8);

        // Increase OHM value
        vault.setPoolAmounts(ohmIndex == 0 ? 100e8 : 1000e18, ohmIndex == 0 ? 1000e18 : 100e8); // 0.1 ETH
        price = vaultManager.getOhmTknPoolPrice();
        assertEq(price, 1e7);
    }

    function testCorrectness_getOhmTknPoolPrice_empty(uint256 ohmIndex_) public {
        // Set up the vault based on the fuzzing
        uint256 ohmIndex = bound(ohmIndex_, 0, 1);
        vault = new MockVault(
            address(liquidityPool),
            ohmIndex == 0 ? address(ohm) : address(lusd),
            ohmIndex == 0 ? address(lusd) : address(ohm)
        );
        vault.setPoolAmounts(ohmIndex == 0 ? 100e9 : 0, ohmIndex == 0 ? 0 : 100e9);

        deployPolicies(vault);

        uint256 price = vaultManager.getOhmTknPoolPrice();
        assertEq(price, 0);
    }

    //============================================================================================//
    //                                        ADMIN FUNCTIONS                                     //
    //============================================================================================//

    /// [X]  setLimit
    ///     [X]  can only be called by liquidityvault_admin
    ///     [X]  cannot set the limit below the current deployedOhm value
    ///     [X]  correctly sets ohmLimit
    ///     [X]  correctly takes into consideration burned OHM

    function testCorrectness_setLimitCanOnlyBeCalledByAdmin(address attacker_) public {
        vm.assume(attacker_ != address(this));

        deployPolicies(vault);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(attacker_);
        vaultManager.setLimit(1e18);
    }

    function testCorrectness_setLimitCannotSetLimitBelowCurrentDeployedOhm() public {
        deployPolicies(vault);

        address validVault = _createVault();

        // Mint OHM
        vm.prank(validVault);
        vaultManager.mintOhmToVault(10_000e9);

        // Try to set limit
        bytes memory err = abi.encodeWithSignature("BLManagerLusd_InvalidLimit()");
        vm.expectRevert(err);

        vaultManager.setLimit(1e9);
    }

    function testCorrectness_setLimitCorrectlySetsLimit(uint256 limit_) public {
        deployPolicies(vault);

        // Set limit
        vaultManager.setLimit(limit_);

        // Check state after
        assertEq(vaultManager.ohmLimit(), limit_);
    }

    function testCorrectness_setLimitTakesBurnedOhmIntoConsideration() public {
        deployPolicies(vault);

        address validVault = _createVault();

        // Mint OHM
        vm.startPrank(address(vaultManager));
        minter.increaseMintApproval(address(vaultManager), 10_000e9);
        minter.mintOhm(validVault, 10_000e9);
        vm.stopPrank();

        // Burn OHM
        vm.startPrank(validVault);
        ohm.increaseAllowance(address(minter), 10_000e9);
        vaultManager.burnOhmFromVault(10_000e9);

        // Mint additional OHM
        vaultManager.mintOhmToVault(20_000e9);
        vm.stopPrank();

        // Attempt to set limit
        bytes memory err = abi.encodeWithSignature("BLManagerLusd_InvalidLimit()");
        vm.expectRevert(err);
        vaultManager.setLimit(1e9);
    }

    /// [X]  setFee
    ///     [X]  can only be called by liquidityvault_admin
    ///     [X]  cannot set fee above 100%
    ///     [X]  correctly sets currentFee

    function testCorrectness_setFeeCanOnlyBeCalledByAdmin(address attacker_) public {
        vm.assume(attacker_ != address(this));

        deployPolicies(vault);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(attacker_);
        vaultManager.setFee(10_000);
    }

    function testCorrectness_setFeeCannotSetFeeAbove100(uint64 fee_) public {
        vm.assume(fee_ > 10_000);

        deployPolicies(vault);

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_InvalidFee()");
        vm.expectRevert(err);

        vaultManager.setFee(fee_);
    }

    function testCorrectness_setFeeCorrectlySetsFee(uint64 fee_) public {
        vm.assume(fee_ <= 10_000);

        deployPolicies(vault);

        // Set fee
        vaultManager.setFee(fee_);

        // Check state after
        assertEq(vaultManager.currentFee(), fee_);
    }

    /// [X]  changeUpdateThresholds
    ///     [X]  can only be called by liquidityvault_admin
    ///     [X]  correctly sets price feed update thresholds

    function testCorrectness_changeUpdateThresholdsCanOnlyBeCalledByAdmin(
        address attacker_
    ) public {
        vm.assume(attacker_ != address(this));

        deployPolicies(vault);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(attacker_);
        vaultManager.changeUpdateThresholds(1 days, 1 days, 1 days);
    }

    function testCorrectness_changeUpdateThresholdsCorrectlySetsThresholds(
        uint48 ohmPriceThreshold_,
        uint48 ethPriceThreshold_,
        uint48 lusdPriceThreshold_
    ) public {
        deployPolicies(vault);

        // Set thresholds
        vaultManager.changeUpdateThresholds(
            ohmPriceThreshold_,
            ethPriceThreshold_,
            lusdPriceThreshold_
        );

        // Check state after
        (, uint48 ohmEthUpdateThreshold) = vaultManager.ohmEthPriceFeed();
        (, uint48 ethUsdUpdateThreshold) = vaultManager.ethUsdPriceFeed();
        (, uint48 lusdUsdUpdateThreshold) = vaultManager.lusdUsdPriceFeed();

        assertEq(ohmEthUpdateThreshold, ohmPriceThreshold_);
        assertEq(lusdUsdUpdateThreshold, lusdPriceThreshold_);
    }

    /// [X]  activate
    ///     [X]  can only be called by liquidityvault_admin
    ///     [X]  sets isLusdBLVaultActive to true

    function testCorrectness_activateCanOnlyBeCalledByAdmin(address attacker_) public {
        vm.assume(attacker_ != address(this));

        deployPolicies(vault);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(attacker_);
        vaultManager.activate();
    }

    function testCorrectness_activateCorrectlySetsIsLusdBLVaultActive() public {
        deployPolicies(vault);

        // Setup
        vaultManager.deactivate();

        // Check state before
        assertEq(vaultManager.isLusdBLVaultActive(), false);
        assertEq(blreg.activeVaultCount(), 0);

        // Activate
        vaultManager.activate();

        // Check state after
        assertEq(vaultManager.isLusdBLVaultActive(), true);
        assertEq(blreg.activeVaults(0), address(vaultManager));
    }

    /// [X]  deactivate
    ///     [X]  can only be called by emergency_admin
    ///     [X]  sets isLusdBLVaultActive to false

    function testCorrectness_deactivateCanOnlyBeCalledByAdmin(address attacker_) public {
        vm.assume(attacker_ != address(this));

        deployPolicies(vault);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("emergency_admin")
        );
        vm.expectRevert(err);

        vm.prank(attacker_);
        vaultManager.deactivate();
    }

    function testCorrectness_deactivateCorrectlySetsIsLusdBLVaultActive() public {
        deployPolicies(vault);

        // Check state before
        assertEq(vaultManager.isLusdBLVaultActive(), true);
        assertEq(blreg.activeVaultCount(), 1);
        assertEq(blreg.activeVaults(0), address(vaultManager));

        // Deactivate
        vaultManager.deactivate();

        // Check state after
        assertEq(vaultManager.isLusdBLVaultActive(), false);
    }
}
