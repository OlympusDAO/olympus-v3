// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockMultiplePoolBalancerVault} from "test/mocks/MockBalancerVault.sol";

import {FullMath} from "libraries/FullMath.sol";
import {Math as OZMath} from "@openzeppelin/contracts/utils/math/Math.sol";

import "src/modules/SPPLY/OlympusSupply.sol";
import {AuraBalancerSupply} from "src/modules/SPPLY/submodules/AuraBalancerSupply.sol";
import {IAuraRewardPool} from "src/external/aura/interfaces/IAuraRewardPool.sol";
import {IBalancerPool} from "src/external/balancer/interfaces/IBalancerPool.sol";

import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";

contract MockBalancerPool is IBalancerPool {
    bytes32 internal immutable _poolId;
    uint256 internal _totalSupply;
    uint256 internal _balance;

    constructor(bytes32 poolId_) {
        _poolId = poolId_;
    }

    function getPoolId() external view returns (bytes32) {
        return _poolId;
    }

    function setTotalSupply(uint256 totalSupply_) external {
        _totalSupply = totalSupply_;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function setBalance(uint256 balance_) external {
        _balance = balance_;
    }

    function balanceOf(address) external view override returns (uint256) {
        return _balance;
    }
}

contract MockAuraPool is IAuraRewardPool {
    address internal immutable _balancerPool;
    uint256 internal _balance;

    constructor(address balancerPool_) {
        _balancerPool = balancerPool_;
    }

    function setBalance(uint256 balance_) external {
        _balance = balance_;
    }

    function balanceOf(address account_) external view override returns (uint256) {
        return _balance;
    }

    function asset() external view override returns (address) {
        return _balancerPool;
    }
}

contract AuraBalancerSupplyTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockGohm internal gOhm;

    Kernel internal kernel;

    OlympusSupply internal moduleSupply;

    AuraBalancerSupply internal submoduleAuraBalancerSupply;

    address internal writer;
    address internal polManager;

    bytes32 internal constant BALANCER_POOL_ID = "hello";
    uint256 internal constant BALANCER_POOL_OHM_BALANCE = 100e9; // 100 OHM
    uint256 internal constant BALANCER_POOL_DAI_BALANCE = 10e18; // 10 DAI
    uint256 internal constant BALANCER_POOL_TOTAL_SUPPLY = 10e18; // 10 BPT

    MockERC20 internal dai;
    MockERC20 internal bal;
    MockERC20 internal aura;

    MockMultiplePoolBalancerVault internal balancerVault;
    MockBalancerPool internal balancerPool;
    MockAuraPool internal auraPool;

    UserFactory public userFactory;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 0; // 0 OHM

    event PoolAdded(address balancerPool, address auraPool);
    event PoolRemoved(address balancerPool, address auraPool);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            ohm = new MockERC20("OHM", "OHM", 9);
            gOhm = new MockGohm(GOHM_INDEX);
        }

        // Locations
        {
            userFactory = new UserFactory();
            address[] memory users = userFactory.create(1);
            polManager = users[0];
        }

        // Bophades
        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy SPPLY module
            address[2] memory tokens = [address(ohm), address(gOhm)];
            moduleSupply = new OlympusSupply(kernel, tokens, INITIAL_CROSS_CHAIN_SUPPLY);

            // Deploy mock module writer
            writer = moduleSupply.generateGodmodeFixture(type(OlympusSupply).name);
        }

        // Deploy Aura-Balancer submodule
        {
            dai = new MockERC20("DAI", "DAI", 18);
            aura = new MockERC20("Aura", "AURA", 18);
            bal = new MockERC20("Balancer", "BAL", 18);

            balancerVault = new MockMultiplePoolBalancerVault();

            address[] memory balancerPoolTokens = new address[](2);
            balancerPoolTokens[0] = address(dai);
            balancerPoolTokens[1] = address(ohm);
            balancerVault.setTokens(BALANCER_POOL_ID, balancerPoolTokens);

            uint256[] memory balancerPoolBalances = new uint256[](2);
            balancerPoolBalances[0] = BALANCER_POOL_DAI_BALANCE;
            balancerPoolBalances[1] = BALANCER_POOL_OHM_BALANCE;
            balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

            balancerPool = new MockBalancerPool(BALANCER_POOL_ID);
            balancerPool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);

            auraPool = new MockAuraPool(address(balancerPool));

            AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
            pools[0] = AuraBalancerSupply.Pool(
                IBalancerPool(balancerPool),
                IAuraRewardPool(auraPool)
            );
            submoduleAuraBalancerSupply = new AuraBalancerSupply(
                moduleSupply,
                polManager,
                address(balancerVault),
                pools
            );
        }

        // Initialize
        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(moduleSupply));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));

            // Install submodules on SPPLY module
            vm.startPrank(writer);
            moduleSupply.installSubmodule(submoduleAuraBalancerSupply);
            vm.stopPrank();
        }
    }

    // Test checklist
    // [X] Constructor
    //  [X] not module
    //  [X] not SPPLY
    //  [X] 0 pools
    //  [X] 1 pool
    //  [X] 1+ pools
    //  [X] 0 address Aura pool - OK
    //  [X] 0 address Balancer pool - NOT OK
    //  [X] duplicate pools
    //  [X] Balancer - Aura pool asset mismatch
    // [X] Submodule
    //  [X] Subkeycode
    //  [X] Version
    // [X] getCollateralizedOhm
    // [X] getProtocolOwnedBorrowableOhm
    // [X] getProtocolOwnedLiquidityOhm
    //  [X] BPT 0 total supply
    //  [X] No aura pool defined
    //  [X] Aura pool/Balancer pool BPT balances + pool OHM balance
    //  [X] multiple pools
    // [X] getProtocolOwnedTreasuryOhm
    // [X] addPool
    //  [X] 0 address Balancer pool
    //  [X] 0 address Aura pool
    //  [X] Aura pool/Balancer pool asset mismatch
    //  [X] Pool already added
    //  [X] success
    //  [X] not parent
    // [X] removePool
    //  [X] 0 address Balancer pool
    //  [X] Not added
    //  [X] success
    //  [X] not parent

    // =========  TESTS ========= //

    // =========  Module Information ========= //

    function test_submodule_version() public {
        uint8 major;
        uint8 minor;
        (major, minor) = submoduleAuraBalancerSupply.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_submodule_parent() public {
        assertEq(fromKeycode(submoduleAuraBalancerSupply.PARENT()), "SPPLY");
    }

    function test_submodule_subkeycode() public {
        assertEq(fromSubKeycode(submoduleAuraBalancerSupply.SUBKEYCODE()), "SPPLY.AURABALANCER");
    }

    // =========  Constructor ========= //

    function test_constructor_parent_notModule_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // There's no error message, so just check that a revert happens when attempting to call the module
        vm.expectRevert();

        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
        pools[0] = AuraBalancerSupply.Pool(IBalancerPool(balancerPool), IAuraRewardPool(auraPool));

        new AuraBalancerSupply(Module(newLocations[0]), polManager, address(balancerVault), pools);
    }

    function test_constructor_parent_notSpply_reverts() public {
        // Pass the PRICEv2 module as the parent
        OlympusPricev2 modulePrice = new OlympusPricev2(kernel, 18, 8 hours);

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
        pools[0] = AuraBalancerSupply.Pool(IBalancerPool(balancerPool), IAuraRewardPool(auraPool));

        new AuraBalancerSupply(modulePrice, polManager, address(balancerVault), pools);
    }

    function test_constructor_emitsEvent() public {
        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
        pools[0] = AuraBalancerSupply.Pool(IBalancerPool(balancerPool), IAuraRewardPool(auraPool));

        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit PoolAdded(address(balancerPool), address(auraPool));

        // Create a new submodule
        vm.startPrank(writer);
        new AuraBalancerSupply(moduleSupply, polManager, address(balancerVault), pools);
        vm.stopPrank();

        assertEq(submoduleAuraBalancerSupply.getSourceCount(), 1);
    }

    function test_constructor_polManagerZero_reverts() public {
        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
        pools[0] = AuraBalancerSupply.Pool(IBalancerPool(balancerPool), IAuraRewardPool(auraPool));

        // Expect revert
        bytes memory err = abi.encodeWithSignature("AuraBalSupply_InvalidParams()");
        vm.expectRevert(err);

        // Create a new submodule
        vm.startPrank(writer);
        new AuraBalancerSupply(moduleSupply, address(0), address(balancerVault), pools);
        vm.stopPrank();
    }

    function test_constructor_balancerVaultZero_reverts() public {
        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
        pools[0] = AuraBalancerSupply.Pool(IBalancerPool(balancerPool), IAuraRewardPool(auraPool));

        // Expect revert
        bytes memory err = abi.encodeWithSignature("AuraBalSupply_InvalidParams()");
        vm.expectRevert(err);

        // Create a new submodule
        vm.startPrank(writer);
        new AuraBalancerSupply(moduleSupply, polManager, address(0), pools);
        vm.stopPrank();
    }

    function test_constructor_duplicate_reverts() public {
        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](2);
        pools[0] = AuraBalancerSupply.Pool(IBalancerPool(balancerPool), IAuraRewardPool(auraPool));
        pools[1] = AuraBalancerSupply.Pool(IBalancerPool(balancerPool), IAuraRewardPool(auraPool));

        // Expect revert
        bytes memory err = abi.encodeWithSignature(
            "AuraBalSupply_PoolAlreadyAdded(address,address)",
            address(balancerPool),
            address(auraPool)
        );
        vm.expectRevert(err);

        // Create a new submodule
        vm.startPrank(writer);
        new AuraBalancerSupply(moduleSupply, polManager, address(balancerVault), pools);
        vm.stopPrank();
    }

    function test_constructor_balancerPool_zero_reverts() public {
        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
        pools[0] = AuraBalancerSupply.Pool(IBalancerPool(address(0)), IAuraRewardPool(auraPool));

        // Expect revert
        bytes memory err = abi.encodeWithSignature("AuraBalSupply_InvalidParams()");
        vm.expectRevert(err);

        // Create a new submodule
        vm.startPrank(writer);
        new AuraBalancerSupply(moduleSupply, polManager, address(balancerVault), pools);
        vm.stopPrank();
    }

    function test_constructor_auraPool_zero() public {
        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
        pools[0] = AuraBalancerSupply.Pool(
            IBalancerPool(balancerPool),
            IAuraRewardPool(address(0))
        );

        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit PoolAdded(address(balancerPool), address(0));

        // Create a new submodule
        vm.startPrank(writer);
        new AuraBalancerSupply(moduleSupply, polManager, address(balancerVault), pools);
        vm.stopPrank();

        assertEq(submoduleAuraBalancerSupply.getSourceCount(), 1);
    }

    function test_constructor_balancerPool_zero_auraPool_zero_reverts() public {
        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
        pools[0] = AuraBalancerSupply.Pool(IBalancerPool(address(0)), IAuraRewardPool(address(0)));

        // Expect revert
        bytes memory err = abi.encodeWithSignature("AuraBalSupply_InvalidParams()");
        vm.expectRevert(err);

        // Create a new submodule
        vm.startPrank(writer);
        new AuraBalancerSupply(moduleSupply, polManager, address(balancerVault), pools);
        vm.stopPrank();
    }

    function test_constructor_no_pools() public {
        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](0);

        // Create a new submodule
        vm.startPrank(writer);
        submoduleAuraBalancerSupply = new AuraBalancerSupply(
            moduleSupply,
            polManager,
            address(balancerVault),
            pools
        );
        vm.stopPrank();

        // Should not be any pools
        AuraBalancerSupply.Pool[] memory poolsActual = submoduleAuraBalancerSupply.getPools();
        assertEq(poolsActual.length, 0);

        assertEq(submoduleAuraBalancerSupply.getSourceCount(), 0);
    }

    function test_constructor_multiple_pools() public {
        // Set up a second Balancer pool
        MockBalancerPool poolTwo = new MockBalancerPool("poolTwo");

        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](2);
        pools[0] = AuraBalancerSupply.Pool(IBalancerPool(balancerPool), IAuraRewardPool(auraPool));
        pools[1] = AuraBalancerSupply.Pool(IBalancerPool(poolTwo), IAuraRewardPool(address(0)));

        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit PoolAdded(address(balancerPool), address(auraPool));
        emit PoolAdded(address(poolTwo), address(0));

        // Create a new submodule
        vm.startPrank(writer);
        submoduleAuraBalancerSupply = new AuraBalancerSupply(
            moduleSupply,
            polManager,
            address(balancerVault),
            pools
        );
        vm.stopPrank();

        assertEq(submoduleAuraBalancerSupply.getSourceCount(), 2);
    }

    function test_constructor_assetMismatch() public {
        // Set up a second Balancer pool
        MockBalancerPool poolTwo = new MockBalancerPool("poolTwo");

        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](1);
        // auraPool.asset() is balancerPool, not poolTwo
        pools[0] = AuraBalancerSupply.Pool(IBalancerPool(poolTwo), IAuraRewardPool(auraPool));

        // Expect revert
        bytes memory err = abi.encodeWithSignature("AuraBalSupply_PoolMismatch()");
        vm.expectRevert(err);

        // Create a new submodule
        vm.startPrank(writer);
        new AuraBalancerSupply(moduleSupply, polManager, address(balancerVault), pools);
        vm.stopPrank();
    }

    // =========  getCollateralizedOhm ========= //

    function test_getCollateralizedOhm(
        uint256 polManagerBptBalance_,
        uint256 poolOhmBalance_
    ) public {
        uint256 bptTotalSupply = BALANCER_POOL_TOTAL_SUPPLY;
        uint256 polManagerBptBalance = bound(polManagerBptBalance_, 0, bptTotalSupply);
        uint256 polManagerAuraBptBalance = 0;
        uint256 poolOhmBalance = bound(poolOhmBalance_, 0, 1e9);
        uint256 poolDaiBalance = 1e18;

        // Set up the balances
        balancerPool.setTotalSupply(bptTotalSupply);
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance);

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolDaiBalance;
        balancerPoolBalances[1] = poolOhmBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        uint256 actual = submoduleAuraBalancerSupply.getCollateralizedOhm();

        assertEq(actual, 0);
    }

    // =========  getProtocolOwnedBorrowableOhm ========= //

    function test_getProtocolOwnedBorrowableOhm(
        uint256 polManagerBptBalance_,
        uint256 poolOhmBalance_
    ) public {
        uint256 bptTotalSupply = BALANCER_POOL_TOTAL_SUPPLY;
        uint256 polManagerBptBalance = bound(polManagerBptBalance_, 0, bptTotalSupply);
        uint256 polManagerAuraBptBalance = 0;
        uint256 poolOhmBalance = bound(poolOhmBalance_, 0, 10e9);
        uint256 poolDaiBalance = 1e18;

        // Set up the balances
        balancerPool.setTotalSupply(bptTotalSupply);
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance);

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolDaiBalance;
        balancerPoolBalances[1] = poolOhmBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        uint256 actual = submoduleAuraBalancerSupply.getProtocolOwnedBorrowableOhm();

        assertEq(actual, 0);
    }

    // =========  getProtocolOwnedLiquidityOhm ========= //

    function test_getProtocolOwnedLiquidityOhm(
        uint256 polManagerBptBalance_,
        uint256 poolOhmBalance_
    ) public {
        uint256 bptTotalSupply = BALANCER_POOL_TOTAL_SUPPLY;
        uint256 polManagerBptBalance = bound(polManagerBptBalance_, 0, bptTotalSupply);
        uint256 polManagerAuraBptBalance = 0;
        uint256 poolOhmBalance = bound(poolOhmBalance_, 0, 1e9);
        uint256 poolDaiBalance = 1e18;

        // Set up the balances
        balancerPool.setTotalSupply(bptTotalSupply);
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance);

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolDaiBalance;
        balancerPoolBalances[1] = poolOhmBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        uint256 expected = (polManagerBptBalance + polManagerAuraBptBalance).mulDiv(
            poolOhmBalance,
            bptTotalSupply
        );

        uint256 actual = submoduleAuraBalancerSupply.getProtocolOwnedLiquidityOhm();

        assertEq(actual, expected);
    }

    function test_getProtocolOwnedLiquidityOhm_poolTokenOrder(uint8 poolTokenOrder_) public {
        uint256 bptTotalSupply = BALANCER_POOL_TOTAL_SUPPLY;
        uint256 polManagerBptBalance = 1e18;
        uint256 polManagerAuraBptBalance = 0;
        uint256 poolOhmBalance = 1e9;
        uint256 poolDaiBalance = 1e18;
        uint8 poolTokenOrder = uint8(bound(poolTokenOrder_, 0, 1));

        // Set up the user balances
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance);

        // Set the balancer pool
        balancerPool.setTotalSupply(bptTotalSupply);

        address[] memory balancerPoolTokens = new address[](2);
        balancerPoolTokens[0] = poolTokenOrder == 0 ? address(dai) : address(ohm);
        balancerPoolTokens[1] = poolTokenOrder == 0 ? address(ohm) : address(dai);
        balancerVault.setTokens(BALANCER_POOL_ID, balancerPoolTokens);

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolTokenOrder == 0 ? poolDaiBalance : poolOhmBalance;
        balancerPoolBalances[1] = poolTokenOrder == 0 ? poolOhmBalance : poolDaiBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        uint256 expected = (polManagerBptBalance + polManagerAuraBptBalance).mulDiv(
            poolOhmBalance,
            bptTotalSupply
        );

        uint256 actual = submoduleAuraBalancerSupply.getProtocolOwnedLiquidityOhm();

        assertEq(actual, expected);
    }

    function test_getProtocolOwnedLiquidityOhm_auraPoolBalance(
        uint256 polManagerAuraBptBalance_,
        uint256 poolOhmBalance_
    ) public {
        uint256 bptTotalSupply = BALANCER_POOL_TOTAL_SUPPLY;
        uint256 polManagerBptBalance = 1e18;
        uint256 polManagerAuraBptBalance = bound(
            polManagerAuraBptBalance_,
            0,
            bptTotalSupply - polManagerBptBalance
        );
        uint256 poolOhmBalance = bound(poolOhmBalance_, 0, 1e9);
        uint256 poolDaiBalance = 1e18;

        // Set up the balances
        balancerPool.setTotalSupply(bptTotalSupply);
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance);

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolDaiBalance;
        balancerPoolBalances[1] = poolOhmBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        uint256 expected = (polManagerBptBalance + polManagerAuraBptBalance).mulDiv(
            poolOhmBalance,
            bptTotalSupply
        );

        uint256 actual = submoduleAuraBalancerSupply.getProtocolOwnedLiquidityOhm();

        assertEq(actual, expected);
    }

    function test_getProtocolOwnedLiquidityOhm_bptTotalSupplyZero() public {
        uint256 polManagerBptBalance = 1e18;
        uint256 polManagerAuraBptBalance = 0;
        uint256 poolOhmBalance = 10e9;
        uint256 poolDaiBalance = 1e18;

        // Set up the balances
        balancerPool.setTotalSupply(0);
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance);

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolDaiBalance;
        balancerPoolBalances[1] = poolOhmBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        uint256 expected = 0;

        uint256 actual = submoduleAuraBalancerSupply.getProtocolOwnedLiquidityOhm();

        assertEq(actual, expected);
    }

    function test_getProtocolOwnedLiquidityOhm_auraPoolZero() public {
        uint256 bptTotalSupply = BALANCER_POOL_TOTAL_SUPPLY;
        uint256 polManagerBptBalance = 1e18;
        uint256 polManagerAuraBptBalance = 2e18;
        uint256 poolOhmBalance = 10e9;
        uint256 poolDaiBalance = 1e18;

        // Remove the pool configuration
        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.removePool(address(balancerPool));
        vm.stopPrank();

        // Add it back without aura
        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.addPool(address(balancerPool), address(0));
        vm.stopPrank();

        // Set up the balances
        balancerPool.setTotalSupply(bptTotalSupply);
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance); // Leave this as a non-zero balance would be noticed if included

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolDaiBalance;
        balancerPoolBalances[1] = poolOhmBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        uint256 expected = (polManagerBptBalance).mulDiv(poolOhmBalance, bptTotalSupply);

        uint256 actual = submoduleAuraBalancerSupply.getProtocolOwnedLiquidityOhm();

        assertEq(actual, expected);
    }

    function test_getProtocolOwnedLiquidityOhm_multiplePools() public {
        // Pool one
        uint256 expectedOne;
        {
            uint256 bptTotalSupplyOne = BALANCER_POOL_TOTAL_SUPPLY;
            uint256 polManagerBptBalanceOne = 1e18;
            uint256 polManagerAuraBptBalanceOne = 0;
            uint256 poolOhmBalanceOne = 10e9;
            uint256 poolDaiBalanceOne = 1e18;

            // Set up the balances for pool one
            balancerPool.setTotalSupply(bptTotalSupplyOne);
            balancerPool.setBalance(polManagerBptBalanceOne);
            auraPool.setBalance(polManagerAuraBptBalanceOne);

            uint256[] memory balancerPoolBalancesOne = new uint256[](2);
            balancerPoolBalancesOne[0] = poolDaiBalanceOne;
            balancerPoolBalancesOne[1] = poolOhmBalanceOne;
            balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalancesOne);

            expectedOne = (polManagerBptBalanceOne + polManagerAuraBptBalanceOne).mulDiv(
                poolOhmBalanceOne,
                bptTotalSupplyOne
            );
        }

        // Pool two
        uint256 expectedTwo;
        {
            uint256 bptTotalSupplyTwo = 2e18;
            uint256 polManagerBptBalanceTwo = 1e18;
            uint256 polManagerAuraBptBalanceTwo = 0;
            uint256 poolOhmBalanceTwo = 10e9;
            uint256 poolDaiBalanceTwo = 2e18;

            // Set up the balances for pool two
            MockBalancerPool balancerPoolTwo = new MockBalancerPool("poolTwo");
            MockAuraPool auraPoolTwo = new MockAuraPool(address(balancerPoolTwo));
            balancerPoolTwo.setTotalSupply(bptTotalSupplyTwo);
            balancerPoolTwo.setBalance(polManagerBptBalanceTwo);
            auraPoolTwo.setBalance(polManagerAuraBptBalanceTwo);

            uint256[] memory balancerPoolBalancesTwo = new uint256[](2);
            balancerPoolBalancesTwo[0] = poolDaiBalanceTwo;
            balancerPoolBalancesTwo[1] = poolOhmBalanceTwo;
            balancerVault.setBalances("poolTwo", balancerPoolBalancesTwo);

            address[] memory balancerPoolTokensTwo = new address[](2);
            balancerPoolTokensTwo[0] = address(dai);
            balancerPoolTokensTwo[1] = address(ohm);
            balancerVault.setTokens("poolTwo", balancerPoolTokensTwo);

            // Add the second pool
            vm.startPrank(address(moduleSupply));
            submoduleAuraBalancerSupply.addPool(address(balancerPoolTwo), address(auraPoolTwo));
            vm.stopPrank();

            expectedTwo = (polManagerBptBalanceTwo + polManagerAuraBptBalanceTwo).mulDiv(
                poolOhmBalanceTwo,
                bptTotalSupplyTwo
            );
        }

        uint256 actual = submoduleAuraBalancerSupply.getProtocolOwnedLiquidityOhm();

        assertEq(actual, expectedOne + expectedTwo);
    }

    function test_getProtocolOwnedLiquidityOhm_multiplePools_bptTotalSupplyZero() public {
        // Pool one
        uint256 expectedOne;
        {
            uint256 bptTotalSupplyOne = 0;
            uint256 polManagerBptBalanceOne = 1e18;
            uint256 polManagerAuraBptBalanceOne = 0;
            uint256 poolOhmBalanceOne = 10e9;
            uint256 poolDaiBalanceOne = 1e18;

            // Set up the balances for pool one
            balancerPool.setTotalSupply(bptTotalSupplyOne);
            balancerPool.setBalance(polManagerBptBalanceOne);
            auraPool.setBalance(polManagerAuraBptBalanceOne);

            uint256[] memory balancerPoolBalancesOne = new uint256[](2);
            balancerPoolBalancesOne[0] = poolDaiBalanceOne;
            balancerPoolBalancesOne[1] = poolOhmBalanceOne;
            balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalancesOne);

            // 0 total supply of pool one means that the pool is not included in the calculation
            expectedOne = 0;
        }

        // Pool two
        uint256 expectedTwo;
        {
            uint256 bptTotalSupplyTwo = 2e18;
            uint256 polManagerBptBalanceTwo = 1e18;
            uint256 polManagerAuraBptBalanceTwo = 0;
            uint256 poolOhmBalanceTwo = 10e9;
            uint256 poolDaiBalanceTwo = 2e18;

            // Set up the balances for pool two
            MockBalancerPool balancerPoolTwo = new MockBalancerPool("poolTwo");
            MockAuraPool auraPoolTwo = new MockAuraPool(address(balancerPoolTwo));
            balancerPoolTwo.setTotalSupply(bptTotalSupplyTwo);
            balancerPoolTwo.setBalance(polManagerBptBalanceTwo);
            auraPoolTwo.setBalance(polManagerAuraBptBalanceTwo);

            uint256[] memory balancerPoolBalancesTwo = new uint256[](2);
            balancerPoolBalancesTwo[0] = poolDaiBalanceTwo;
            balancerPoolBalancesTwo[1] = poolOhmBalanceTwo;
            balancerVault.setBalances("poolTwo", balancerPoolBalancesTwo);

            address[] memory balancerPoolTokensTwo = new address[](2);
            balancerPoolTokensTwo[0] = address(dai);
            balancerPoolTokensTwo[1] = address(ohm);
            balancerVault.setTokens("poolTwo", balancerPoolTokensTwo);

            // Add the second pool
            vm.startPrank(address(moduleSupply));
            submoduleAuraBalancerSupply.addPool(address(balancerPoolTwo), address(auraPoolTwo));
            vm.stopPrank();

            expectedTwo = (polManagerBptBalanceTwo + polManagerAuraBptBalanceTwo).mulDiv(
                poolOhmBalanceTwo,
                bptTotalSupplyTwo
            );
        }

        uint256 actual = submoduleAuraBalancerSupply.getProtocolOwnedLiquidityOhm();

        assertEq(actual, expectedOne + expectedTwo);
    }

    function test_getProtocolOwnedLiquidityReserves(
        uint256 polManagerBptBalance_,
        uint256 poolOhmBalance_
    ) public {
        uint256 bptTotalSupply = BALANCER_POOL_TOTAL_SUPPLY;
        uint256 polManagerBptBalance = bound(polManagerBptBalance_, 0, bptTotalSupply);
        uint256 polManagerAuraBptBalance = 0;
        uint256 poolOhmBalance = bound(poolOhmBalance_, 0, 1e9);
        uint256 poolDaiBalance = 1e18;

        // Set up the balances
        balancerPool.setTotalSupply(bptTotalSupply);
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance);

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolDaiBalance;
        balancerPoolBalances[1] = poolOhmBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        uint256 expectedOhmBalance = (polManagerBptBalance + polManagerAuraBptBalance).mulDiv(
            poolOhmBalance,
            bptTotalSupply
        );
        uint256 expectedDaiBalance = (polManagerBptBalance + polManagerAuraBptBalance).mulDiv(
            poolDaiBalance,
            bptTotalSupply
        );

        SPPLYv1.Reserves[] memory reserves = submoduleAuraBalancerSupply
            .getProtocolOwnedLiquidityReserves();
        assertEq(reserves.length, 1);
        assertEq(reserves[0].source, address(balancerPool));
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], address(dai));
        assertEq(reserves[0].tokens[1], address(ohm));
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], expectedDaiBalance);
        assertEq(reserves[0].balances[1], expectedOhmBalance);
    }

    function test_getProtocolOwnedLiquidityReserves_auraPoolBalance(
        uint256 polManagerAuraBptBalance_,
        uint256 poolOhmBalance_
    ) public {
        uint256 bptTotalSupply = BALANCER_POOL_TOTAL_SUPPLY;
        uint256 polManagerBptBalance = 1e18;
        uint256 polManagerAuraBptBalance = bound(
            polManagerAuraBptBalance_,
            0,
            bptTotalSupply - polManagerBptBalance
        );
        uint256 poolOhmBalance = bound(poolOhmBalance_, 0, 1e9);
        uint256 poolDaiBalance = 1e18;

        // Set up the balances
        balancerPool.setTotalSupply(bptTotalSupply);
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance);

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolDaiBalance;
        balancerPoolBalances[1] = poolOhmBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        uint256 expectedOhmBalance = (polManagerBptBalance + polManagerAuraBptBalance).mulDiv(
            poolOhmBalance,
            bptTotalSupply
        );
        uint256 expectedDaiBalance = (polManagerBptBalance + polManagerAuraBptBalance).mulDiv(
            poolDaiBalance,
            bptTotalSupply
        );

        SPPLYv1.Reserves[] memory reserves = submoduleAuraBalancerSupply
            .getProtocolOwnedLiquidityReserves();
        assertEq(reserves.length, 1);
        assertEq(reserves[0].source, address(balancerPool));
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], address(dai));
        assertEq(reserves[0].tokens[1], address(ohm));
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], expectedDaiBalance);
        assertEq(reserves[0].balances[1], expectedOhmBalance);
    }

    function test_getProtocolOwnedLiquidityReserves_bptTotalSupplyZero() public {
        uint256 polManagerBptBalance = 1e18;
        uint256 polManagerAuraBptBalance = 0;
        uint256 poolOhmBalance = 10e9;
        uint256 poolDaiBalance = 1e18;

        // Set up the balances
        balancerPool.setTotalSupply(0);
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance);

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolDaiBalance;
        balancerPoolBalances[1] = poolOhmBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        SPPLYv1.Reserves[] memory reserves = submoduleAuraBalancerSupply
            .getProtocolOwnedLiquidityReserves();
        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, address(balancerPool));
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], address(dai));
        assertEq(reserves[0].tokens[1], address(ohm));
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], 0);
        assertEq(reserves[0].balances[1], 0);
    }

    function test_getProtocolOwnedLiquidityReserves_auraPoolZero() public {
        uint256 bptTotalSupply = BALANCER_POOL_TOTAL_SUPPLY;
        uint256 polManagerBptBalance = 1e18;
        uint256 polManagerAuraBptBalance = 2e18;
        uint256 poolOhmBalance = 10e9;
        uint256 poolDaiBalance = 1e18;

        // Remove the pool configuration
        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.removePool(address(balancerPool));
        vm.stopPrank();

        // Add it back without aura
        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.addPool(address(balancerPool), address(0));
        vm.stopPrank();

        // Set up the balances
        balancerPool.setTotalSupply(bptTotalSupply);
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance); // Leave this as a non-zero balance would be noticed if included

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolDaiBalance;
        balancerPoolBalances[1] = poolOhmBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        uint256 expectedOhmBalance = (polManagerBptBalance + 0).mulDiv(
            poolOhmBalance,
            bptTotalSupply
        );
        uint256 expectedDaiBalance = (polManagerBptBalance + 0).mulDiv(
            poolDaiBalance,
            bptTotalSupply
        );

        SPPLYv1.Reserves[] memory reserves = submoduleAuraBalancerSupply
            .getProtocolOwnedLiquidityReserves();
        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, address(balancerPool));
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], address(dai));
        assertEq(reserves[0].tokens[1], address(ohm));
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], expectedDaiBalance);
        assertEq(reserves[0].balances[1], expectedOhmBalance);
    }

    function test_getProtocolOwnedLiquidityReserves_multiplePools() public {
        // Pool one
        uint256 expectedPoolOneDaiBalance;
        uint256 expectedPoolOneOhmBalance;
        {
            uint256 bptTotalSupplyOne = BALANCER_POOL_TOTAL_SUPPLY;
            uint256 polManagerBptBalanceOne = 1e18;
            uint256 polManagerAuraBptBalanceOne = 0;
            uint256 poolOhmBalance = 10e9;
            uint256 poolDaiBalance = 1e18;

            // Set up the balances for pool one
            balancerPool.setTotalSupply(bptTotalSupplyOne);
            balancerPool.setBalance(polManagerBptBalanceOne);
            auraPool.setBalance(polManagerAuraBptBalanceOne);

            uint256[] memory balancerPoolBalancesOne = new uint256[](2);
            balancerPoolBalancesOne[0] = poolDaiBalance;
            balancerPoolBalancesOne[1] = poolOhmBalance;
            balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalancesOne);

            expectedPoolOneDaiBalance = poolDaiBalance.mulDiv(
                polManagerBptBalanceOne + polManagerAuraBptBalanceOne,
                bptTotalSupplyOne
            );
            expectedPoolOneOhmBalance = poolOhmBalance.mulDiv(
                polManagerBptBalanceOne + polManagerAuraBptBalanceOne,
                bptTotalSupplyOne
            );
        }

        // Pool two
        uint256 expectedPoolTwoOhmBalance;
        uint256 expectedPoolTwoDaiBalance;
        address poolTwo;
        {
            uint256 bptTotalSupplyTwo = 2e18;
            uint256 polManagerBptBalanceTwo = 1e18;
            uint256 polManagerAuraBptBalanceTwo = 0;
            uint256 poolOhmBalance = 10e9;
            uint256 poolDaiBalance = 2e18;

            // Set up the balances for pool two
            MockBalancerPool balancerPoolTwo = new MockBalancerPool("poolTwo");
            MockAuraPool auraPoolTwo = new MockAuraPool(address(balancerPoolTwo));
            balancerPoolTwo.setTotalSupply(bptTotalSupplyTwo);
            balancerPoolTwo.setBalance(polManagerBptBalanceTwo);
            auraPoolTwo.setBalance(polManagerAuraBptBalanceTwo);

            uint256[] memory balancerPoolBalancesTwo = new uint256[](2);
            balancerPoolBalancesTwo[0] = poolDaiBalance;
            balancerPoolBalancesTwo[1] = poolOhmBalance;
            balancerVault.setBalances("poolTwo", balancerPoolBalancesTwo);

            address[] memory balancerPoolTokensTwo = new address[](2);
            balancerPoolTokensTwo[0] = address(dai);
            balancerPoolTokensTwo[1] = address(ohm);
            balancerVault.setTokens("poolTwo", balancerPoolTokensTwo);

            // Add the second pool
            vm.startPrank(address(moduleSupply));
            submoduleAuraBalancerSupply.addPool(address(balancerPoolTwo), address(auraPoolTwo));
            vm.stopPrank();

            poolTwo = address(balancerPoolTwo);

            expectedPoolTwoDaiBalance = poolDaiBalance.mulDiv(
                polManagerBptBalanceTwo + polManagerAuraBptBalanceTwo,
                bptTotalSupplyTwo
            );
            expectedPoolTwoOhmBalance = poolOhmBalance.mulDiv(
                polManagerBptBalanceTwo + polManagerAuraBptBalanceTwo,
                bptTotalSupplyTwo
            );
        }

        SPPLYv1.Reserves[] memory reserves = submoduleAuraBalancerSupply
            .getProtocolOwnedLiquidityReserves();
        assertEq(reserves.length, 2);
        assertEq(reserves[0].source, address(balancerPool));
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], address(dai));
        assertEq(reserves[0].tokens[1], address(ohm));
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], expectedPoolOneDaiBalance);
        assertEq(reserves[0].balances[1], expectedPoolOneOhmBalance);

        assertEq(reserves[1].source, address(poolTwo));
        assertEq(reserves[1].tokens.length, 2);
        assertEq(reserves[1].tokens[0], address(dai));
        assertEq(reserves[1].tokens[1], address(ohm));
        assertEq(reserves[1].balances.length, 2);
        assertEq(reserves[1].balances[0], expectedPoolTwoDaiBalance);
        assertEq(reserves[1].balances[1], expectedPoolTwoOhmBalance);
    }

    // =========  getProtocolOwnedTreasuryOhm  ========= //

    function test_getProtocolOwnedTreasuryOhm(
        uint256 polManagerBptBalance_,
        uint256 poolOhmBalance_
    ) public {
        uint256 bptTotalSupply = BALANCER_POOL_TOTAL_SUPPLY;
        uint256 polManagerBptBalance = bound(polManagerBptBalance_, 0, bptTotalSupply);
        uint256 polManagerAuraBptBalance = 0;
        uint256 poolOhmBalance = bound(poolOhmBalance_, 0, 10e9);
        uint256 poolDaiBalance = 1e18;

        // Set up the balances
        balancerPool.setTotalSupply(bptTotalSupply);
        balancerPool.setBalance(polManagerBptBalance);
        auraPool.setBalance(polManagerAuraBptBalance);

        uint256[] memory balancerPoolBalances = new uint256[](2);
        balancerPoolBalances[0] = poolDaiBalance;
        balancerPoolBalances[1] = poolOhmBalance;
        balancerVault.setBalances(BALANCER_POOL_ID, balancerPoolBalances);

        uint256 actual = submoduleAuraBalancerSupply.getProtocolOwnedTreasuryOhm();

        assertEq(actual, 0);
    }

    // =========  addPool ========= //

    function test_addPool() public {
        // Set up a second Balancer pool
        MockBalancerPool balancerPoolTwo = new MockBalancerPool("poolTwo");
        MockAuraPool auraPoolTwo = new MockAuraPool(address(balancerPoolTwo));

        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit PoolAdded(address(balancerPoolTwo), address(auraPoolTwo));

        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.addPool(address(balancerPoolTwo), address(auraPoolTwo));
        vm.stopPrank();

        // Check that the pool was added
        (IBalancerPool balancerPool_, IAuraRewardPool auraPool_) = submoduleAuraBalancerSupply
            .pools(1);
        assertEq(address(balancerPool_), address(balancerPoolTwo));
        assertEq(address(auraPool_), address(auraPoolTwo));

        AuraBalancerSupply.Pool[] memory pools = submoduleAuraBalancerSupply.getPools();
        assertEq(pools.length, 2);

        assertEq(submoduleAuraBalancerSupply.getSourceCount(), 2);
    }

    function test_addPool_duplicate_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSignature(
            "AuraBalSupply_PoolAlreadyAdded(address,address)",
            address(balancerPool),
            address(auraPool)
        );
        vm.expectRevert(err);

        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.addPool(address(balancerPool), address(auraPool));
        vm.stopPrank();
    }

    function test_addPool_balancerPool_zero_reverts() public {
        // Set up a second Balancer pool
        MockBalancerPool balancerPoolTwo = new MockBalancerPool("poolTwo");
        MockAuraPool auraPoolTwo = new MockAuraPool(address(balancerPoolTwo));

        // Expect revert
        bytes memory err = abi.encodeWithSignature("AuraBalSupply_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.addPool(address(0), address(auraPoolTwo));
        vm.stopPrank();
    }

    function test_addPool_auraPool_zero() public {
        // Set up a second Balancer pool
        MockBalancerPool balancerPoolTwo = new MockBalancerPool("poolTwo");

        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit PoolAdded(address(balancerPoolTwo), address(0));

        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.addPool(address(balancerPoolTwo), address(0));
        vm.stopPrank();

        // Check that the pool was added
        (IBalancerPool balancerPool_, IAuraRewardPool auraPool_) = submoduleAuraBalancerSupply
            .pools(1);
        assertEq(address(balancerPool_), address(balancerPoolTwo));
        assertEq(address(auraPool_), address(0));

        AuraBalancerSupply.Pool[] memory pools = submoduleAuraBalancerSupply.getPools();
        assertEq(pools.length, 2);

        assertEq(submoduleAuraBalancerSupply.getSourceCount(), 2);
    }

    function test_addPool_balancerPool_zero_auraPool_zero_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSignature("AuraBalSupply_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.addPool(address(0), address(0));
        vm.stopPrank();
    }

    function test_addPool_assetMismatch() public {
        // Set up a second Balancer pool
        MockBalancerPool balancerPoolTwo = new MockBalancerPool("poolTwo");

        // Expect revert
        bytes memory err = abi.encodeWithSignature("AuraBalSupply_PoolMismatch()");
        vm.expectRevert(err);

        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.addPool(address(balancerPoolTwo), address(auraPool));
        vm.stopPrank();
    }

    function test_addPool_notParent_reverts() public {
        // Set up a second Balancer pool
        MockBalancerPool balancerPoolTwo = new MockBalancerPool("poolTwo");
        MockAuraPool auraPoolTwo = new MockAuraPool(address(balancerPoolTwo));

        // Expect revert
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", writer);
        vm.expectRevert(err);

        vm.startPrank(writer);
        submoduleAuraBalancerSupply.addPool(address(balancerPoolTwo), address(auraPoolTwo));
        vm.stopPrank();
    }

    // =========  removePool ========= //

    function test_removePool() public {
        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit PoolRemoved(address(balancerPool), address(auraPool));

        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.removePool(address(balancerPool));
        vm.stopPrank();

        // Check that the pool was removed
        AuraBalancerSupply.Pool[] memory pools = submoduleAuraBalancerSupply.getPools();
        assertEq(pools.length, 0);

        assertEq(submoduleAuraBalancerSupply.getSourceCount(), 0);
    }

    function test_removePool_balancerPool_zero() public {
        // Expect revert
        bytes memory err = abi.encodeWithSignature("AuraBalSupply_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.removePool(address(0));
        vm.stopPrank();
    }

    function test_removePool_notAdded_reverts() public {
        // Set up a second Balancer pool
        MockBalancerPool balancerPoolTwo = new MockBalancerPool("poolTwo");

        // Expect revert
        bytes memory err = abi.encodeWithSignature("AuraBalSupply_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(address(moduleSupply));
        submoduleAuraBalancerSupply.removePool(address(balancerPoolTwo));
        vm.stopPrank();
    }

    function test_removePool_notParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", writer);
        vm.expectRevert(err);

        vm.startPrank(writer);
        submoduleAuraBalancerSupply.removePool(address(balancerPool));
        vm.stopPrank();
    }
}
