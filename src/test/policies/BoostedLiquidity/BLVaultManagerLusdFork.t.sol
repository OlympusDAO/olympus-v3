// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test, stdError} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {larping} from "test/lib/larping.sol";

import {FullMath} from "libraries/FullMath.sol";

import {MockLegacyAuthority} from "test/mocks/MockLegacyAuthority.sol";
import {ERC20, MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

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
contract BLVaultManagerLusdTestFork is Test {
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

    IOlympusAuthority internal auth;

    Kernel internal kernel;
    OlympusMinter internal minter;
    OlympusTreasury internal treasury;
    OlympusBoostedLiquidityRegistry internal blreg;
    OlympusRoles internal roles;

    RolesAdmin internal rolesAdmin;
    BLVaultManagerLusd internal vaultManager;
    BLVaultLusd internal vaultImplementation;

    uint256 internal constant OHM_LIMIT = 233_645e9; // $2.5m = 233,645 OHM

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
            auraPool = IAuraRewardPool(0x636024F9Ddef77e625161b2cCF3A2adfbfAd3615);
            auraMiningLib = IAuraMiningLib(0x744Be650cea753de1e69BF6BAd3c98490A855f52);

            // determine by calling poolInfo(127) on booster
            auraPool = IAuraRewardPool(0x3b395A27F77C3450393047fF564E893243aC29fF);

            // Label Aura contracts
            vm.label(address(booster), "booster");
            vm.label(address(auraPool), "auraPool");
            vm.label(address(auraMiningLib), "auraMiningLib");
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
                OHM_LIMIT,
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
        // Deactivate contract
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_Inactive()");
        vm.expectRevert(err);

        vaultManager.deployVault();
    }

    function testCorrectness_deployVaultCanBeCalledByAnyone() public {
        vm.prank(address(0));
        vaultManager.deployVault();

        vm.prank(address(1));
        vaultManager.deployVault();

        vm.prank(alice);
        vaultManager.deployVault();

        vm.prank(bob);
        vaultManager.deployVault();
    }

    function testCorrectness_deployVaultFailsIfUserAlreadyHasVault() public {
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
        assertEq(aliceVault.pid(), 127);
        assertEq(address(aliceVault.auraBooster()), address(booster));
        assertEq(address(aliceVault.auraRewardPool()), address(auraPool));
        assertEq(aliceVault.fee(), 0);
    }

    function testCorrectness_deployVaultCorrectlyTracksVaultState() public {
        vm.prank(alice);
        BLVaultLusd userVault = BLVaultLusd(vaultManager.deployVault());

        // Verify manager state
        assertEq(vaultManager.vaultOwners(userVault), alice);
        assertEq(address(vaultManager.userVaults(alice)), address(userVault));
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
        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_Inactive()");
        vm.expectRevert(err);

        vaultManager.mintOhmToVault(1e9);
    }

    function testCorrectness_mintOhmToVaultCanOnlyBeCalledByApprovedVault(
        address attacker_
    ) public {
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
        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_Inactive()");
        vm.expectRevert(err);

        vaultManager.burnOhmFromVault(1e9);
    }

    function testCorrectness_burnOhmFromVaultCanOnlyBeCalledByAnApprovedVault(
        address attacker_
    ) public {
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
        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_Inactive()");
        vm.expectRevert(err);

        vaultManager.increaseTotalLp(1e18);
    }

    function testCorrectness_increaseTotalLpCanOnlyBeCalledByAnApprovedVault(
        address attacker_
    ) public {
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
        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_Inactive()");
        vm.expectRevert(err);

        vaultManager.decreaseTotalLp(1e18);
    }

    function testCorrectness_decreaseTotalLpCanOnlyBeCalledByAnApprovedVault(
        address attacker_
    ) public {
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

    // function testCorrectness_getLpBalance() public {
    //     address aliceVault = _createVault();

    //     // Check state before
    //     assertEq(vaultManager.getLpBalance(alice), 0);

    //     // Deposit LUSD
    //     vm.startPrank(alice);
    //     lusd.approve(aliceVault, type(uint256).max);
    //     BLVaultLusd(aliceVault).deposit(1e18, 0);
    //     vm.stopPrank();

    //     // Check state after
    //     assertTrue(vaultManager.getLpBalance(alice) > 0);
    // }

    /// [X]  getUserPairShare
    ///     [X]  returns correct user LUSD share

    // function testCorrectness_getUserPairShare() public {
    //     address aliceVault = _createVault();

    //     // Check state before
    //     assertEq(vaultManager.getUserPairShare(alice), 0);

    //     // Deposit LUSD
    //     vm.startPrank(alice);
    //     lusd.approve(aliceVault, type(uint256).max);
    //     BLVaultLusd(aliceVault).deposit(1e18, 0);
    //     vm.stopPrank();

    //     // Check state after
    //     assertTrue(vaultManager.getUserPairShare(alice) > 0);
    // }

    /// [X]  getMaxDeposit
    ///     [X]  returns correct LUSD deposit amount

    function testCorrectness_getMaxDeposit() public {
        address aliceVault = _createVault();

        uint256 ohmTknPrice = vaultManager.getOhmTknPrice();

        // Check state before
        assertEq(vaultManager.getMaxDeposit(), (OHM_LIMIT * 1e18) / ohmTknPrice);

        // Increase OHM minted
        vm.prank(aliceVault);
        vaultManager.mintOhmToVault(99_900e9);

        // Check state after
        assertEq(vaultManager.getMaxDeposit(), ((OHM_LIMIT - 99_900e9) * 1e18) / ohmTknPrice);
    }

    /// [X]  getRewardTokens
    ///     [X]  returns correct reward token array

    function testCorrectness_getRewardTokens() public {
        address[] memory tokens = vaultManager.getRewardTokens();

        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(aura));
        assertEq(tokens[1], address(bal));
    }

    /// [X]  getRewardRate
    ///     [X]  returns correct reward rate for Bal

    function testCorrectness_getRewardRate() public {
        uint256 balRate = vaultManager.getRewardRate(address(bal));
        uint256 auraRate = vaultManager.getRewardRate(address(aura));

        assertTrue(balRate > 0);
        assertTrue(auraRate > 0);
    }

    /// [X]  getPoolOhmShare
    ///     [X]  returns correct OHM share

    // function testCorrectness_getPoolOhmShare() public {
    //     address aliceVault = _createVault();

    //     // Check state before
    //     assertEq(vaultManager.getPoolOhmShare(), 0);

    //     // Deposit LUSD
    //     vm.startPrank(alice);
    //     lusd.approve(aliceVault, type(uint256).max);
    //     BLVaultLusd(aliceVault).deposit(1e18, 0);
    //     vm.stopPrank();

    //     // Check state after
    //     console2.log("Vault OHM share", vaultManager.getPoolOhmShare());
    //     assertTrue(vaultManager.getPoolOhmShare() > 0);
    // }

    /// [X]  getOhmTknPrice
    ///     [X]  returns correct OHM per LUSD (100)

    function testCorrectness_getOhmTknPrice() public {
        uint256 price = vaultManager.getOhmTknPrice();

        assertTrue(price > 0);
    }

    /// [X]  getTknOhmPrice
    ///     [X]  returns correct LUSD per OHM (0.01)

    function testCorrectness_getTknOhmPrice() public {
        uint256 price = vaultManager.getTknOhmPrice();

        assertTrue(price > 0);
    }

    //============================================================================================//
    //                                        ADMIN FUNCTIONS                                     //
    //============================================================================================//

    /// [X]  setLimit
    ///     [X]  can only be called by liquidityvault_admin
    ///     [X]  cannot set the limit below the current deployedOhm value
    ///     [X]  correctly sets ohmLimit

    function testCorrectness_setLimitCanOnlyBeCalledByAdmin() public {
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(address(0));
        vaultManager.setLimit(1e18);
    }

    function testCorrectness_setLimitCannotSetLimitBelowCurrentDeployedOhm() public {
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
        // Set limit
        vaultManager.setLimit(limit_);

        // Check state after
        assertEq(vaultManager.ohmLimit(), limit_);
    }

    /// [X]  setFee
    ///     [X]  can only be called by liquidityvault_admin
    ///     [X]  cannot set fee above 100%
    ///     [X]  correctly sets currentFee

    function testCorrectness_setFeeCanOnlyBeCalledByAdmin() public {
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(address(0));
        vaultManager.setFee(10_000);
    }

    function testCorrectness_setFeeCannotSetFeeAbove100(uint64 fee_) public {
        vm.assume(fee_ > 10_000);

        bytes memory err = abi.encodeWithSignature("BLManagerLusd_InvalidFee()");
        vm.expectRevert(err);

        vaultManager.setFee(fee_);
    }

    function testCorrectness_setFeeCorrectlySetsFee(uint64 fee_) public {
        vm.assume(fee_ <= 10_000);

        // Set fee
        vaultManager.setFee(fee_);

        // Check state after
        assertEq(vaultManager.currentFee(), fee_);
    }

    /// [X]  changeUpdateThresholds
    ///     [X]  can only be called by liquidityvault_admin
    ///     [X]  correctly sets price feed update thresholds

    function testCorrectness_changeUpdateThresholdsCanOnlyBeCalledByAdmin() public {
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(address(0));
        vaultManager.changeUpdateThresholds(1 days, 1 days, 1 days);
    }

    function testCorrectness_changeUpdateThresholdsCorrectlySetsThresholds(
        uint48 ohmPriceThreshold_,
        uint48 ethPriceThreshold_,
        uint48 lusdPriceThreshold_
    ) public {
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
        assertEq(ethUsdUpdateThreshold, ethPriceThreshold_);
        assertEq(lusdUsdUpdateThreshold, lusdPriceThreshold_);
    }

    /// [X]  activate
    ///     [X]  can only be called by liquidityvault_admin
    ///     [X]  sets isLusdBLVaultActive to true

    function testCorrectness_activateCanOnlyBeCalledByAdmin() public {
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(address(0));
        vaultManager.activate();
    }

    function testCorrectness_activateCorrectlySetsIsLusdBLVaultActive() public {
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

    function testCorrectness_deactivateCanOnlyBeCalledByAdmin() public {
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("emergency_admin")
        );
        vm.expectRevert(err);

        vm.prank(address(0));
        vaultManager.deactivate();
    }

    function testCorrectness_deactivateCorrectlySetsIsLusdBLVaultActive() public {
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
