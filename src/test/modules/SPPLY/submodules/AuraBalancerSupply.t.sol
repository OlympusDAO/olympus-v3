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
import {AuraBalancerSupply,IAuraPool,IBalancerPool} from "src/modules/SPPLY/submodules/AuraBalancerSupply.sol";

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

    function balanceOf(address account_) external view override returns (uint256) {
        return _balance;
    }
}

contract MockAuraPool is IAuraPool {
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
    uint256 internal constant BALANCER_POOL_TOTAL_SUPPLY = 100e18; // 100 BPT

    MockERC20 internal dai;
    MockERC20 internal bal;
    MockERC20 internal aura;

    MockMultiplePoolBalancerVault internal balancerVault;
    MockBalancerPool internal balancerPool;
    MockAuraPool internal auraPool;

    UserFactory public userFactory;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 0; // 0 OHM

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
            pools[0] = AuraBalancerSupply.Pool(IBalancerPool(balancerPool), IAuraPool(auraPool));
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
}