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
import {IAuraBooster, IAuraRewardPool} from "policies/lending/interfaces/IAura.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {IBLEVaultManagerLido, BLEVaultManagerLido} from "policies/lending/BLEVaultManagerLido.sol";
import {BLEVaultLido} from "policies/lending/BLEVaultLido.sol";

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
contract BLEVaultManagerLidoTest is Test {
    using FullMath for uint256;
    using larping for *;

    UserFactory public userCreator;
    address internal alice;

    OlympusERC20Token internal ohm;
    MockWsteth internal wsteth;
    MockERC20 internal aura;
    MockERC20 internal bal;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal stethEthPriceFeed;

    MockVault internal vault;
    MockBalancerPool internal liquidityPool;

    MockAuraBooster internal booster;
    MockAuraRewardPool internal auraPool;

    IOlympusAuthority internal auth;

    Kernel internal kernel;
    OlympusMinter internal minter;
    OlympusTreasury internal treasury;
    OlympusRoles internal roles;

    RolesAdmin internal rolesAdmin;
    BLEVaultManagerLido internal vaultManager;
    BLEVaultLido internal vaultImplementation;

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
            wsteth = new MockWsteth("Wrapped Staked ETH", "wstETH", 18);
            aura = new MockERC20("Aura", "AURA", 18);
            bal = new MockERC20("Balancer", "BAL", 18);
        }

        // Deploy mock price feeds
        {
            ohmEthPriceFeed = new MockPriceFeed();
            stethEthPriceFeed = new MockPriceFeed();

            ohmEthPriceFeed.setDecimals(18);
            stethEthPriceFeed.setDecimals(18);

            ohmEthPriceFeed.setLatestAnswer(1e16); // 0.01 ETH
            stethEthPriceFeed.setLatestAnswer(1e18); // 1 ETH
        }

        // Deploy mock Balancer contracts
        {
            liquidityPool = new MockBalancerPool();
            vault = new MockVault(address(liquidityPool), address(ohm), address(wsteth));
            vault.setPoolAmounts(100e9, 1e18);
        }

        // Deploy mock Aura contracts
        {
            auraPool = new MockAuraRewardPool(address(vault.bpt()), address(bal));
            booster = new MockAuraBooster(address(vault.bpt()), address(auraPool));
        }

        // Deploy kernel
        {
            kernel = new Kernel();
        }

        // Deploy modules
        {
            minter = new OlympusMinter(kernel, address(ohm));
            treasury = new OlympusTreasury(kernel);
            roles = new OlympusRoles(kernel);
        }

        // Set vault in auth to MINTR
        {
            auth.vault.larp(address(minter));
        }

        // Deploy policies
        {
            vaultImplementation = new BLEVaultLido();

            IBLEVaultManagerLido.TokenData memory tokenData = IBLEVaultManagerLido.TokenData({
                ohm: address(ohm),
                pairToken: address(wsteth),
                aura: address(aura),
                bal: address(bal)
            });

            IBLEVaultManagerLido.BalancerData memory balancerData = IBLEVaultManagerLido
                .BalancerData({
                    vault: address(vault),
                    liquidityPool: address(liquidityPool),
                    balancerHelper: address(0)
                });

            IBLEVaultManagerLido.AuraData memory auraData = IBLEVaultManagerLido.AuraData({
                pid: uint256(0),
                auraBooster: address(booster),
                auraRewardPool: address(auraPool)
            });

            IBLEVaultManagerLido.OracleFeed memory ohmEthPriceFeedData = IBLEVaultManagerLido
                .OracleFeed({feed: ohmEthPriceFeed, updateThreshold: uint48(1 days)});

            IBLEVaultManagerLido.OracleFeed memory stethEthPriceFeedData = IBLEVaultManagerLido
                .OracleFeed({feed: stethEthPriceFeed, updateThreshold: uint48(1 days)});

            vaultManager = new BLEVaultManagerLido(
                kernel,
                tokenData,
                balancerData,
                auraData,
                address(0),
                ohmEthPriceFeedData,
                stethEthPriceFeedData,
                address(vaultImplementation),
                100_000e9,
                0
            );
            rolesAdmin = new RolesAdmin(kernel);
        }

        // Initialize system
        {
            // Initialize modules
            kernel.executeAction(Actions.InstallModule, address(minter));
            kernel.executeAction(Actions.InstallModule, address(treasury));
            kernel.executeAction(Actions.InstallModule, address(roles));

            // Activate policies
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ActivatePolicy, address(vaultManager));
        }

        // Set roles
        {
            rolesAdmin.grantRole("liquidityvault_admin", address(this));
        }

        // Activate Vault Manager
        {
            vaultManager.activate();
        }

        // Initialize timestamps on mock price feeds
        {
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            stethEthPriceFeed.setTimestamp(block.timestamp);
        }

        // Mint wstETH to alice
        {
            wsteth.mint(alice, 100e18);
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

    function testCorrectness_deployVaultFailsWhenBLEInactive() public {
        // Deactivate contract
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLEManagerLido_Inactive()");
        vm.expectRevert(err);

        vaultManager.deployVault();
    }

    function testCorrectness_deployVaultCanBeCalledByAnyone(address user_) public {
        vm.prank(user_);
        vaultManager.deployVault();
    }

    function testCorrectness_deployVaultFailsIfUserAlreadyHasVault() public {
        // Create first vault
        vm.prank(alice);
        vaultManager.deployVault();

        bytes memory err = abi.encodeWithSignature("BLEManagerLido_VaultAlreadyExists()");
        vm.expectRevert(err);

        // Try to create second vault
        vm.prank(alice);
        vaultManager.deployVault();
    }

    function testCorrectness_deployVaultCorrectlyClonesVault() public {
        // Create vault
        vm.prank(alice);
        BLEVaultLido aliceVault = BLEVaultLido(vaultManager.deployVault());

        // Verify vault state
        assertEq(aliceVault.owner(), alice);
        assertEq(address(aliceVault.manager()), address(vaultManager));
        assertEq(aliceVault.TRSRY(), address(treasury));
        assertEq(address(aliceVault.ohm()), address(ohm));
        assertEq(address(aliceVault.wsteth()), address(wsteth));
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
        vm.prank(user_);
        BLEVaultLido userVault = BLEVaultLido(vaultManager.deployVault());

        // Verify manager state
        assertEq(vaultManager.vaultOwners(userVault), user_);
        assertEq(address(vaultManager.userVaults(user_)), address(userVault));
    }

    /// [X]  mintOHM
    ///     [X]  can only be called when system is active
    ///     [X]  can only be called by an approved vault
    ///     [X]  cannot mint beyond the limit
    ///     [X]  increases mintedOHM value
    ///     [X]  mints OHM to correct address

    function _createVault() internal returns (address) {
        vm.prank(alice);
        address aliceVault = vaultManager.deployVault();

        return aliceVault;
    }

    function testCorrectness_mintOHMFailsWhenBLEInactive() public {
        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLEManagerLido_Inactive()");
        vm.expectRevert(err);

        vaultManager.mintOHM(1e9);
    }

    function testCorrectness_mintOHMCanOnlyBeCalledByApprovedVault(address attacker_) public {
        address validVault = _createVault();

        vm.prank(validVault);
        vaultManager.mintOHM(1e9);

        if (attacker_ != validVault) {
            bytes memory err = abi.encodeWithSignature("BLEManagerLido_InvalidVault()");
            vm.expectRevert(err);

            vm.prank(attacker_);
            vaultManager.mintOHM(1e9);
        }
    }

    function testCorrectness_mintOHMCannotMintBeyondLimit(uint256 amount_) public {
        vm.assume(amount_ != 0);

        address validVault = _createVault();

        if (amount_ <= vaultManager.ohmLimit()) {
            vm.prank(validVault);
            vaultManager.mintOHM(amount_);
        } else {
            bytes memory err = abi.encodeWithSignature("BLEManagerLido_LimitViolation()");
            vm.expectRevert(err);

            vm.prank(validVault);
            vaultManager.mintOHM(amount_);
        }
    }

    function testCorrectness_mintOHMIncreasesMintedOHMValue(uint256 amount_) public {
        vm.assume(amount_ != 0 && amount_ <= vaultManager.ohmLimit());

        address validVault = _createVault();

        // Check state before
        assertEq(vaultManager.mintedOHM(), 0);

        // Mint OHM
        vm.prank(validVault);
        vaultManager.mintOHM(amount_);

        // Check state after
        assertEq(vaultManager.mintedOHM(), amount_);
    }

    function testCorrectness_mintOHMMintsToCorrectAddress() public {
        address validVault = _createVault();

        // Check balance before
        assertEq(ohm.balanceOf(validVault), 0);

        // Mint OHM
        vm.prank(validVault);
        vaultManager.mintOHM(1e9);

        // Check balance after
        assertEq(ohm.balanceOf(validVault), 1e9);
    }

    /// [X]  burnOHM
    ///     [X]  can only be called when system is active
    ///     [X]  can only be called by an approved vault
    ///     [X]  correctly updates mintedOHM and netBurnedOHM
    ///     [X]  burns OHM from correct address

    function testCorrectness_burnOHMFailsWhenBLEInactive() public {
        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLEManagerLido_Inactive()");
        vm.expectRevert(err);

        vaultManager.burnOHM(1e9);
    }

    function testCorrectness_burnOHMCanOnlyBeCalledByAnApprovedVault(address attacker_) public {
        // Setup
        address validVault = _createVault();
        vm.prank(validVault);
        vaultManager.mintOHM(1e9);

        // If address is valid
        vm.startPrank(validVault);
        ohm.increaseAllowance(address(minter), 1e9);
        vaultManager.burnOHM(1e9);
        vm.stopPrank();

        if (attacker_ != validVault) {
            bytes memory err = abi.encodeWithSignature("BLEManagerLido_InvalidVault()");
            vm.expectRevert(err);

            vm.prank(attacker_);
            vaultManager.burnOHM(1e9);
        }
    }

    function testCorrectness_burnOHMCorrectlyUpdatesState(uint256 amount_) public {
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
        vaultManager.mintOHM(50_000_000e9);
        ohm.increaseAllowance(address(minter), 100_000_000e9);

        // Check state before
        assertEq(vaultManager.mintedOHM(), 50_000_000e9);
        assertEq(vaultManager.netBurnedOHM(), 0);

        vaultManager.burnOHM(amount_);

        // Check state after
        if (amount_ > 50_000_000e9) {
            assertEq(vaultManager.mintedOHM(), 0);
            assertEq(vaultManager.netBurnedOHM(), amount_ - 50_000_000e9);
        } else {
            assertEq(vaultManager.mintedOHM(), 50_000_000e9 - amount_);
            assertEq(vaultManager.netBurnedOHM(), 0);
        }

        vm.stopPrank();
    }

    function testCorrectness_burnOHMBurnsFromCorrectAddress() public {
        address validVault = _createVault();

        vm.startPrank(validVault);
        vaultManager.mintOHM(1e9);
        ohm.increaseAllowance(address(minter), 1e9);

        // Check balance before
        assertEq(ohm.balanceOf(validVault), 1e9);

        // Burn OHM
        vaultManager.burnOHM(1e9);

        // Check balance after
        assertEq(ohm.balanceOf(validVault), 0);
        vm.stopPrank();
    }

    /// [X]  increaseTotalLP
    ///     [X]  can only be called when system is active
    ///     [X]  can only be called by an approved vault
    ///     [X]  increases totalLP value

    function testCorrectness_increaseTotalLPFailsWhenBLEInactive() public {
        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLEManagerLido_Inactive()");
        vm.expectRevert(err);

        vaultManager.increaseTotalLP(1e18);
    }

    function testCorrectness_increaseTotalLPCanOnlyBeCalledByAnApprovedVault(
        address attacker_
    ) public {
        // Setup
        address validVault = _createVault();

        // If address is valid
        vm.prank(validVault);
        vaultManager.increaseTotalLP(1e18);

        if (attacker_ != validVault) {
            bytes memory err = abi.encodeWithSignature("BLEManagerLido_InvalidVault()");
            vm.expectRevert(err);

            vm.prank(attacker_);
            vaultManager.increaseTotalLP(1e18);
        }
    }

    function testCorrectness_increaseTotalLPCorrectlyIncreasesValue(uint256 amount_) public {
        address validVault = _createVault();

        // Check state before
        assertEq(vaultManager.totalLP(), 0);

        // Increase total LP amount
        vm.prank(validVault);
        vaultManager.increaseTotalLP(amount_);

        // Check state after
        assertEq(vaultManager.totalLP(), amount_);
    }

    /// [X]  decreaseTotalLP
    ///     [X]  can only be called when system is active
    ///     [X]  can only be called by an approved vault
    ///     [X]  decreases totalLP value

    function testCorrectness_decreaseTotalLPFailsWhenBLEInactive() public {
        // Deactive system
        vaultManager.deactivate();

        bytes memory err = abi.encodeWithSignature("BLEManagerLido_Inactive()");
        vm.expectRevert(err);

        vaultManager.decreaseTotalLP(1e18);
    }

    function testCorrectness_decreaseTotalLPCanOnlyBeCalledByAnApprovedVault(
        address attacker_
    ) public {
        // Setup
        address validVault = _createVault();

        // If address is valid
        vm.startPrank(validVault);
        vaultManager.increaseTotalLP(1e18);
        vaultManager.decreaseTotalLP(1e18);
        vm.stopPrank();

        if (attacker_ != validVault) {
            bytes memory err = abi.encodeWithSignature("BLEManagerLido_InvalidVault()");
            vm.expectRevert(err);

            vm.prank(attacker_);
            vaultManager.decreaseTotalLP(1e18);
        }
    }

    function testCorrectness_decreaseTotalLPCorrectlyDecreasesValue(uint256 amount_) public {
        address validVault = _createVault();

        // Increase total LP
        vm.startPrank(validVault);
        vaultManager.increaseTotalLP(amount_);

        // Check state before
        assertEq(vaultManager.totalLP(), amount_);

        // Decrease total LP
        vaultManager.decreaseTotalLP(amount_);

        // Check state after
        assertEq(vaultManager.totalLP(), 0);
        vm.stopPrank();
    }

    //============================================================================================//
    //                                         VIEW FUNCTIONS                                     //
    //============================================================================================//

    /// []  getLPBalance
    ///     []  returns the correct LP value

    // function testCorrectness_getLPBalance() public {
    //     address aliceVault = _createVault();

    //     // Check state before
    //     assertEq(vaultManager.getLPBalance(alice), 0);

    //     // Deposit wstETH
    //     vm.startPrank(alice);
    //     wsteth.approve(aliceVault, type(uint256).max);
    //     BLEVaultLido(aliceVault).deposit(1e18, 0);
    //     vm.stopPrank();

    //     // Check state after
    //     assertTrue(vaultManager.getLPBalance(alice) > 0);
    // }

    /// []  getUserPairShare
    ///     []  returns correct user wstETH share

    // function testCorrectness_getUserPairShare() public {
    //     address aliceVault = _createVault();

    //     // Check state before
    //     assertEq(vaultManager.getUserPairShare(alice), 0);

    //     // Deposit wstETH
    //     vm.startPrank(alice);
    //     wsteth.approve(aliceVault, type(uint256).max);
    //     BLEVaultLido(aliceVault).deposit(1e18, 0);
    //     vm.stopPrank();

    //     // Check state after
    //     assertTrue(vaultManager.getUserPairShare(alice) > 0);
    // }

    /// [X]  getMaxDeposit
    ///     [X]  returns correct wstETH deposit amount

    function testCorrectness_getMaxDeposit() public {
        address aliceVault = _createVault();

        // Check state before
        assertEq(vaultManager.getMaxDeposit(), 1_000e18);

        // Increase OHM minted
        vm.prank(aliceVault);
        vaultManager.mintOHM(99_900e9);

        // Check state after
        assertEq(vaultManager.getMaxDeposit(), 1e18);
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
        uint256 rate = vaultManager.getRewardRate(address(bal));

        assertEq(rate, 1e18);
    }

    /// [X]  getOhmTknPrice
    ///     [X]  returns correct OHM per wstETH (100)

    function testCorrectness_getOhmTknPrice() public {
        uint256 price = vaultManager.getOhmTknPrice();

        assertEq(price, 100e9);
    }

    /// [X]  getTknOhmPrice
    ///     [X]  returns correct wstETH per OHM (0.01)

    function testCorrectness_getTknOhmPrice() public {
        uint256 price = vaultManager.getTknOhmPrice();

        assertEq(price, 1e16);
    }

    //============================================================================================//
    //                                        ADMIN FUNCTIONS                                     //
    //============================================================================================//

    /// [X]  setLimit
    ///     [X]  can only be called by liquidityvault_admin
    ///     [X]  cannot set the limit below the current mintedOHM value
    ///     [X]  correctly sets ohmLimit

    function testCorrectness_setLimitCanOnlyBeCalledByAdmin(address attacker_) public {
        vm.assume(attacker_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(attacker_);
        vaultManager.setLimit(1e18);
    }

    function testCorrectness_setLimitCannotSetLimitBelowCurrentMintedOHM() public {
        address validVault = _createVault();

        // Mint OHM
        vm.prank(validVault);
        vaultManager.mintOHM(10_000e9);

        // Try to set limit
        bytes memory err = abi.encodeWithSignature("BLEManagerLido_InvalidLimit()");
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

    function testCorrectness_setFeeCanOnlyBeCalledByAdmin(address attacker_) public {
        vm.assume(attacker_ != address(this));

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

        bytes memory err = abi.encodeWithSignature("BLEManagerLido_InvalidFee()");
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

    function testCorrectness_changeUpdateThresholdsCanOnlyBeCalledByAdmin(
        address attacker_
    ) public {
        vm.assume(attacker_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(attacker_);
        vaultManager.changeUpdateThresholds(1 days, 1 days);
    }

    function testCorrectness_changeUpdateThresholdsCorrectlySetsThresholds(
        uint48 ohmPriceThreshold_,
        uint48 stethPriceThreshold_
    ) public {
        // Set thresholds
        vaultManager.changeUpdateThresholds(ohmPriceThreshold_, stethPriceThreshold_);

        // Check state after
        (, uint48 ohmEthUpdateThreshold) = vaultManager.ohmEthPriceFeed();
        (, uint48 stethEthUpdateThreshold) = vaultManager.stethEthPriceFeed();

        assertEq(ohmEthUpdateThreshold, ohmPriceThreshold_);
        assertEq(stethEthUpdateThreshold, stethPriceThreshold_);
    }

    /// [X]  activate
    ///     [X]  can only be called by liquidityvault_admin
    ///     [X]  sets isLidoBLEActive to true

    function testCorrectness_activateCanOnlyBeCalledByAdmin(address attacker_) public {
        vm.assume(attacker_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(attacker_);
        vaultManager.activate();
    }

    function testCorrectness_activateCorrectlySetsIsLidoBLEActive() public {
        // Activate
        vaultManager.activate();

        // Check state after
        assertEq(vaultManager.isLidoBLEActive(), true);
    }

    /// [X]  deactivate
    ///     [X]  can only be called by liquidityvault_admin
    ///     [X]  sets isLidoBLEActive to false

    function testCorrectness_deactivateCanOnlyBeCalledByAdmin(address attacker_) public {
        vm.assume(attacker_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(attacker_);
        vaultManager.deactivate();
    }

    function testCorrectness_deactivateCorrectlySetsIsLidoBLEActive() public {
        // Deactivate
        vaultManager.deactivate();

        // Check state after
        assertEq(vaultManager.isLidoBLEActive(), false);
    }
}
