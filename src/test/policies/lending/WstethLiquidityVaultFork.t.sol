// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test, stdError} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {FullMath} from "libraries/FullMath.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IVault, IBasePool, IBalancerHelper, IFactory, JoinPoolRequest} from "src/policies/lending/interfaces/IBalancer.sol";
import {MockVault, MockBalancerPool} from "test/mocks/BalancerMocks.sol";
import {MockAuraBooster, MockAuraRewardPool} from "test/mocks/AuraMocks.sol";

import {IAuraBooster, IAuraRewardPool} from "policies/lending/interfaces/IAura.sol";

import {OlympusMinter, OHM} from "modules/MINTR/OlympusMinter.sol";
import {OlympusLiquidityRegistry} from "modules/LQREG/OlympusLiquidityRegistry.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {WstethLiquidityVault} from "policies/lending/WstethLiquidityVault.sol";

import "src/Kernel.sol";

import {console2} from "forge-std/console2.sol";

interface ILDO {
    function generateTokens(address _owner, uint256 _amount) external returns (bool);
}

interface ISteth {
    function submit(address _referral) external payable returns (uint256);
}

interface IWsteth {
    function wrap(uint256 _amount) external returns (uint256);
}

contract MockOhm is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burnFrom(address from, uint256 value) public virtual {
        _burn(from, value);
    }
}

// solhint-disable-next-line max-states-count
contract WstethLiquidityVaultTest is Test {
    using FullMath for uint256;

    address internal alice;
    address internal bob;
    address internal guardian;
    address internal ldoController;
    address public godmode;

    ERC20 internal ohm;
    ERC20 internal wsteth;
    ERC20 internal ldo;
    MockERC20 internal reward2;
    MockERC20 internal externalReward;

    AggregatorV2V3Interface internal ohmEthPriceFeed;
    AggregatorV2V3Interface internal ethUsdPriceFeed;
    AggregatorV2V3Interface internal stethUsdPriceFeed;

    IVault internal vault;
    IFactory internal weightedPoolFactory;
    IBasePool internal liquidityPool;
    IBalancerHelper internal balancerHelper;

    MockAuraBooster internal booster;
    MockAuraRewardPool internal auraPool;

    Kernel internal kernel;
    OlympusMinter internal minter;
    OlympusLiquidityRegistry internal lqreg;
    OlympusRoles internal roles;

    RolesAdmin internal rolesAdmin;
    WstethLiquidityVault internal liquidityVault;

    uint256 internal constant WSTETH_AMOUNT = 1e18;
    uint256[] internal minTokenAmounts_ = [1, 1];

    uint256 forkId;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        {
            // Set up mainnet fork
            forkId = vm.createSelectFork("https://rpc.ankr.com/eth");
        }

        {
            // Set up users
            alice = payable(address(uint160(uint256(keccak256(abi.encodePacked("alice"))))));
            bob = payable(address(uint160(uint256(keccak256(abi.encodePacked("bob"))))));
            guardian = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
            ldoController = 0xf73a1260d222f447210581DDf212D915c09a3249;

            // Give ETH to alice
            vm.deal(alice, 100 ether);
            vm.deal(bob, 100 ether);

            // Label addresses
            vm.label(alice, "alice");
            vm.label(bob, "bob");
            vm.label(guardian, "guardian");
            vm.label(ldoController, "ldoController");
        }

        {
            // Get tokens
            ohm = ERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
            wsteth = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
            ldo = ERC20(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32);
            reward2 = new MockERC20("Reward Token 2", "REWARD2", 18);
            externalReward = new MockERC20("External Reward Token", "EXTREWARD", 18);

            // Label tokens
            vm.label(address(ohm), "ohm");
            vm.label(address(wsteth), "wsteth");
            vm.label(address(ldo), "ldo");
            vm.label(address(reward2), "reward2");
            vm.label(address(externalReward), "externalReward");
        }

        {
            // Get price feeds
            ohmEthPriceFeed = AggregatorV2V3Interface(0x9a72298ae3886221820B1c878d12D872087D3a23);
            ethUsdPriceFeed = AggregatorV2V3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
            stethUsdPriceFeed = AggregatorV2V3Interface(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8);

            // Label price feeds
            vm.label(address(ohmEthPriceFeed), "ohmEthPriceFeed");
            vm.label(address(ethUsdPriceFeed), "ethUsdPriceFeed");
            vm.label(address(stethUsdPriceFeed), "stethUsdPriceFeed");
        }

        {
            // Balancer setup
            vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
            weightedPoolFactory = IFactory(0x8E9aa87E45e92bad84D5F8DD1bff34Fb92637dE9);
            balancerHelper = IBalancerHelper(0x5aDDCCa35b7A0D07C74063c48700C8590E87864E);

            // Deploy Balancer pool
            ERC20[] memory tokens = new ERC20[](2);
            tokens[0] = ohm;
            tokens[1] = wsteth;

            uint256[] memory weights = new uint256[](2);
            weights[0] = 500000000000000000;
            weights[1] = 500000000000000000;

            liquidityPool = IBasePool(
                weightedPoolFactory.create(
                    "50 OHM - 50 wstETH",
                    "OHM/wstETH",
                    tokens,
                    weights,
                    3000000000000000,
                    guardian
                )
            );

            // Label Balancer contracts
            vm.label(address(vault), "vault");
            vm.label(address(weightedPoolFactory), "weightedPoolFactory");
            vm.label(address(balancerHelper), "balancerHelper");
            vm.label(address(liquidityPool), "liquidityPool");
        }

        {
            // Deploy mock Aura contracts
            auraPool = new MockAuraRewardPool(address(liquidityPool), address(externalReward));
            booster = new MockAuraBooster(address(liquidityPool), address(auraPool));

            // Label Aura contracts
            vm.label(address(auraPool), "auraPool");
            vm.label(address(booster), "booster");
        }

        {
            // Deploy kernel
            kernel = Kernel(0x2286d7f9639e8158FaD1169e76d1FbC38247f54b);

            // Deploy modules
            minter = OlympusMinter(0xa90bFe53217da78D900749eb6Ef513ee5b6a491e);
            roles = OlympusRoles(0x6CAfd730Dc199Df73C16420C4fCAb18E3afbfA59);
            lqreg = new OlympusLiquidityRegistry(kernel);

            // Label modules
            vm.label(address(kernel), "kernel");
            vm.label(address(minter), "minter");
            vm.label(address(roles), "roles");
            vm.label(address(lqreg), "lqreg");
        }

        {
            // Deploy roles admin
            rolesAdmin = RolesAdmin(0xb216d714d91eeC4F7120a732c11428857C659eC8);

            WstethLiquidityVault.OracleFeed memory ohmEthFeedStruct = WstethLiquidityVault
                .OracleFeed({feed: ohmEthPriceFeed, updateThreshold: 1 days});
            WstethLiquidityVault.OracleFeed memory ethUsdFeedStruct = WstethLiquidityVault
                .OracleFeed({feed: ethUsdPriceFeed, updateThreshold: 1 days});
            WstethLiquidityVault.OracleFeed memory stethUsdFeedStruct = WstethLiquidityVault
                .OracleFeed({feed: stethUsdPriceFeed, updateThreshold: 1 days});

            WstethLiquidityVault.AuraPool memory auraPoolStruct = WstethLiquidityVault.AuraPool({
                pid: 0,
                booster: IAuraBooster(booster),
                rewardsPool: IAuraRewardPool(auraPool)
            });

            // Deploy wstETH Single Sided Liquidity Vault
            liquidityVault = new WstethLiquidityVault(
                kernel,
                address(ohm),
                address(wsteth),
                address(vault),
                address(balancerHelper),
                address(liquidityPool),
                ohmEthFeedStruct,
                ethUsdFeedStruct,
                stethUsdFeedStruct,
                auraPoolStruct
            );

            // Label policies
            vm.label(address(rolesAdmin), "rolesAdmin");
            vm.label(address(liquidityVault), "liquidityVault");
        }

        {
            // Initialize system and kernel
            vm.startPrank(guardian);

            // Initialize modules
            kernel.executeAction(Actions.InstallModule, address(lqreg));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(liquidityVault));

            vm.stopPrank();
        }

        {
            // Set roles
            vm.prank(guardian);
            rolesAdmin.grantRole("liquidityvault_admin", guardian);
        }

        {
            vm.startPrank(guardian);

            // Set limit
            liquidityVault.setLimit(1000e9); // 1000 OHM

            // Set price variation threshold to 1%
            liquidityVault.setThreshold(10);

            // Add reward token
            liquidityVault.addInternalRewardToken(address(ldo), 1e18, block.timestamp); // 1 REWARD token per second
            liquidityVault.addExternalRewardToken(address(externalReward));

            // Activate vault
            liquidityVault.activate();

            vm.stopPrank();

            vm.prank(ldoController);
            ILDO(address(ldo)).generateTokens(address(liquidityVault), 1e23);
        }

        {
            vm.startPrank(alice);

            // Deposit ETH to stETH
            ISteth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).submit{value: 75 ether}(address(0));

            // Wrap stETH to wstETH
            uint256 stethBalance = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).balanceOf(
                alice
            );
            ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).approve(
                address(wsteth),
                stethBalance
            );
            IWsteth(address(wsteth)).wrap(stethBalance);

            // Approve vault to spend alice's wstETH
            uint256 wstethBalance = wsteth.balanceOf(alice);
            wsteth.approve(address(liquidityVault), wstethBalance);

            vm.stopPrank();
        }

        {
            vm.startPrank(bob);

            // Deposit ETH to stETH
            ISteth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).submit{value: 75 ether}(address(0));

            // Wrap stETH to wstETH
            uint256 stethBalance = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).balanceOf(bob);
            ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).approve(
                address(wsteth),
                stethBalance
            );
            IWsteth(address(wsteth)).wrap(stethBalance);

            // Approve vault to spend bob's wstETH
            uint256 wstethBalance = wsteth.balanceOf(bob);
            wsteth.approve(address(liquidityVault), wstethBalance);

            vm.stopPrank();
        }

        {
            vm.deal(guardian, 100 ether);

            vm.startPrank(guardian);

            // Deposit ETH to stETH
            ISteth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).submit{value: 75 ether}(address(0));

            // Wrap stETH to wstETH
            uint256 stethBalance = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).balanceOf(
                guardian
            );
            ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).approve(
                address(wsteth),
                stethBalance
            );
            IWsteth(address(wsteth)).wrap(stethBalance);

            vm.stopPrank();
        }

        {
            // Initialize Balancer pool
            uint256 ohmDeposit = liquidityVault._valueCollateral(1e18);

            address[] memory assets = new address[](2);
            assets[0] = address(ohm);
            assets[1] = address(wsteth);

            uint256[] memory balances = new uint256[](2);
            balances[0] = ohmDeposit;
            balances[1] = 1e18;

            JoinPoolRequest memory joinPoolRequest = JoinPoolRequest({
                assets: assets,
                maxAmountsIn: balances,
                userData: abi.encode(0, balances),
                fromInternalBalance: false
            });

            vm.startPrank(guardian);
            ohm.approve(address(vault), ohmDeposit);
            wsteth.approve(address(vault), 1e18);
            vault.joinPool(liquidityPool.getPoolId(), guardian, guardian, joinPoolRequest);
            vm.stopPrank();
        }
    }

    // ========= UTILS ========= //

    function _mintWsteth(address user_) internal {
        vm.deal(user_, 100 ether);

        vm.startPrank(user_);

        // Deposit ETH to stETH
        ISteth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).submit{value: 75 ether}(address(0));

        // Wrap stETH to wstETH
        uint256 stethBalance = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).balanceOf(user_);
        ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).approve(address(wsteth), stethBalance);
        IWsteth(address(wsteth)).wrap(stethBalance);

        // Approve vault to spend alice's wstETH
        wsteth.approve(address(liquidityVault), WSTETH_AMOUNT);

        vm.stopPrank();
    }

    function _joinBalancerPool(uint256 ohmAmount_, uint256 wstethAmount_) internal {
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(wsteth);

        uint256[] memory balances = new uint256[](2);
        balances[0] = ohmAmount_;
        balances[1] = wstethAmount_;

        JoinPoolRequest memory joinPoolRequest = JoinPoolRequest({
            assets: assets,
            maxAmountsIn: balances,
            userData: abi.encode(1, balances, 0),
            fromInternalBalance: false
        });

        vm.startPrank(guardian);
        ohm.approve(address(vault), ohmAmount_);
        wsteth.approve(address(vault), wstethAmount_);
        vault.joinPool(liquidityPool.getPoolId(), guardian, guardian, joinPoolRequest);
        vm.stopPrank();
    }

    /// [X]  deposit
    ///     [X]  Deposit doesn't fail
    ///     [X]  Fails if pool is imbalanced
    ///     [X]  Cannot be called beyond limit
    ///     [X]  Increases user's wstETH deposit
    ///     [X]  Correctly values wstETH in terms of OHM
    ///     [X]  Transfers wstETH from user
    ///     [X]  Deposits wstETH and OHM into Balancer LP
    ///     [X]  Deposits Balancer LP into Aura
    ///     [X]  Updates user's tracked LP position
    ///     [X]  Updates tracked total LP amount

    function testCorrectness_depositDoesntFail() public {
        vm.prank(alice);
        liquidityVault.deposit(1e18, 0);
    }

    function testCorrectness_depositCannotBeCalledBeyondLimit() public {
        vm.startPrank(alice);
        liquidityVault.deposit(1e18, 0);

        bytes memory err = abi.encodeWithSignature("LiquidityVault_LimitViolation()");
        vm.expectRevert(err);

        liquidityVault.deposit(1e20, 0); // Should try to push mint beyond limit
        vm.stopPrank();
    }

    function testCorrectness_depositFailsIfPricesDiffer() public {
        // Set pool price
        _joinBalancerPool(0, 10e18);

        bytes memory err = abi.encodeWithSignature("LiquidityVault_PoolImbalanced()");
        vm.expectRevert(err);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.deposit(1e18, 1e18);

        // Set pool price
        _joinBalancerPool(1_000_000e9, 0);

        // Expect revert again
        vm.expectRevert(err);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.deposit(1e18, 1e18);
    }

    function testCorrectness_depositIncreasesUserWstethDeposit() public {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 0);

        assertEq(liquidityVault.pairTokenDeposits(alice), WSTETH_AMOUNT);
    }

    function testCorrectness_depositCorrectlyValuesWsteth() public {
        // Get initial state
        uint256 initialOhmBalance = ohm.balanceOf(address(vault));

        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 0);

        uint256 expectedOhmAmount = liquidityVault._valueCollateral(WSTETH_AMOUNT);

        assertEq(ohm.balanceOf(address(vault)), initialOhmBalance + expectedOhmAmount);
    }

    function testCorrectness_depositTransfersWstethFromUser() public {
        // Get initial state
        uint256 initialWstethBalance = wsteth.balanceOf(alice);

        // Deposit
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 0);

        // Check final state
        assertEq(wsteth.balanceOf(alice), initialWstethBalance - WSTETH_AMOUNT);
    }

    function testCorrectness_depositDepositsWstethAndOhmToVault() public {
        // Get initial state
        uint256 initialWstethBalance = wsteth.balanceOf(address(vault));
        uint256 initialOhmBalance = ohm.balanceOf(address(vault));

        // Deposit
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 0);

        // Check final state
        uint256 expectedOhmAmount = liquidityVault._valueCollateral(WSTETH_AMOUNT);
        assertEq(wsteth.balanceOf(address(vault)), initialWstethBalance + WSTETH_AMOUNT);
        assertEq(ohm.balanceOf(address(vault)), initialOhmBalance + expectedOhmAmount);
    }

    function testCorrectness_depositDepositsBptToAura() public {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 0);

        assertEq(liquidityPool.balanceOf(address(liquidityVault)), 0);
        assertTrue(liquidityPool.balanceOf(address(auraPool)) > 0);
    }

    function testCorrectness_depositUpdatesUserTrackedLpPosition() public {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 0);

        assertTrue(liquidityVault.lpPositions(alice) > 0);
    }

    function testCorrectness_depositUpdatesTrackedTotalLPAmount() public {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 1e18);

        assertTrue(liquidityVault.totalLP() > 0);
    }

    /// [X]  withdraw (no time has passed)
    ///     [X]  Withdraw doesn't fail
    ///     [X]  Fails if pool and oracle prices differ substantially
    ///     [X]  Rewards are 0
    ///     [X]  Fails if user has no LP positions
    ///     [X]  Removes wstETH and OHM from Balancer LP
    ///     [X]  Decreases user's wstETH deposit value
    ///     [X]  Burns received OHM
    ///     [X]  Transfers wstETH to user

    function _withdrawSetUp() internal {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 0);
    }

    function testCorrectness__withdrawDoesntFail_noTimeChange() public {
        _withdrawSetUp();

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);
    }

    function testCorrectness_withdrawFailsIfPricesDiffer_noTimeChange() public {
        // Setup
        _withdrawSetUp();

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Set pool price
        _joinBalancerPool(0, 10e18);

        bytes memory err = abi.encodeWithSignature("LiquidityVault_PoolImbalanced()");
        vm.expectRevert(err);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Set pool price
        _joinBalancerPool(1_000_000e9, 0);

        // Expect revert again
        vm.expectRevert(err);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);
    }

    function testCorrectness_withdrawHasNoRewards_noTimeChange() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        assertEq(ldo.balanceOf(alice), 0);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Verify end state
        assertEq(ldo.balanceOf(alice), 0);
    }

    function testCorrectness_withdrawFailsIfUserHasNoLpPosition_noTimeChange() public {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, false);
    }

    function testCorrectness_withdrawRemovesWstethAndOhmFromVault_noTimeChange() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        uint256 initialWstethBalance = wsteth.balanceOf(address(vault));
        uint256 initialOhmBalance = ohm.balanceOf(address(vault));
        assertTrue(initialWstethBalance > 0);
        assertTrue(initialOhmBalance > 0);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, false);

        // Verify end state
        assertTrue((initialWstethBalance - wsteth.balanceOf(address(vault))) > 0);
        assertTrue((initialOhmBalance - ohm.balanceOf(address(vault))) > 0);
    }

    function testCorrectness_withdrawDecreasesUserWstethDeposit_noTimeChange() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        uint256 initialDeposit = liquidityVault.pairTokenDeposits(alice);
        assertEq(initialDeposit, WSTETH_AMOUNT);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, false);

        // Verify end state
        assertTrue((initialDeposit - liquidityVault.pairTokenDeposits(alice)) > 0);
    }

    function testCorrectness_withdrawBurnsOhm_noTimeChange() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        assertTrue(ohm.balanceOf(address(vault)) > 0);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, false);

        // Verify end state
        assertEq(ohm.balanceOf(address(liquidityVault)), 0);
    }

    function testCorrectness_withdrawTransfersWstethToUser_noTimeChange() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        uint256 initialWstethBalance = wsteth.balanceOf(alice);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, false);

        // Verify end state
        assertTrue((wsteth.balanceOf(alice) - initialWstethBalance) > 0);
    }

    /// [X]  withdraw (time has passed)
    ///     [X]  Withdraw doesn't fail
    ///     [X]  Fails if pool and oracle prices differ substantially
    ///     [X]  Foregoes rewards if called with claim as false
    ///     [X]  Claims rewards
    ///     [X]  Claims external rewards
    ///     [X]  Returns correct rewards with multiple users
    ///     [X]  Returns correct external rewards with multiple users
    ///     [X]  Fails if user has no LP positions
    ///     [X]  Removes wstETH and OHM from Balancer LP
    ///     [X]  Decreases user's wstETH deposit value
    ///     [X]  Updates user's reward debts for reward tokens
    ///     [X]  Burns received OHM
    ///     [X]  Transfers wstETH to user

    function _withdrawTimeSetUp() internal {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 0);
        vm.warp(block.timestamp + 10); // Increase time 10 seconds so there are rewards
    }

    function testCorrectness__withdrawDoesntFail_timeChange() public {
        _withdrawTimeSetUp();

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);
    }

    function testCorrectness_withdrawFailsIfPricesDiffer_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Set pool price
        _joinBalancerPool(0, 10e18);

        bytes memory err = abi.encodeWithSignature("LiquidityVault_PoolImbalanced()");
        vm.expectRevert(err);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Set pool price
        _joinBalancerPool(1_000_000e9, 0);

        // Expect revert again
        vm.expectRevert(err);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);
    }

    function testCorrectness_withdrawForegoesRewardsIfCalledWithoutClaim_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        assertEq(ldo.balanceOf(alice), 0);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, false);

        // Verify end state
        assertEq(ldo.balanceOf(alice), 0);
    }

    function testCorrectness_withdrawClaimsRewards_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        assertEq(ldo.balanceOf(alice), 0);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Verify end state
        assertTrue(ldo.balanceOf(alice) > 0);
    }

    function testCorrectness_withdrawClaimsExternalRewards_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        assertEq(externalReward.balanceOf(alice), 0);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Verify end state
        assertTrue(externalReward.balanceOf(alice) > 0);
    }

    function testCorrectness_withdrawReturnsCorrectRewardsMultiUser_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Add second depositor
        vm.prank(bob);
        liquidityVault.deposit(1e18, 0);
        vm.warp(block.timestamp + 10); // Increase time by 10 seconds

        // Alice's rewards should be 15 REWARD tokens
        // 10 for the first 10 blocks and 5 for the second 10 blocks
        // Verify initial state
        assertEq(ldo.balanceOf(alice), 0);

        // Get alice and bob lp positions
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Verify end state
        assertApproxEqRel(ldo.balanceOf(alice), 15e18, 1e16); // 1e16 = 1%
    }

    function testCorrectness_withdrawReturnsCorrectExternalRewardsMultiUser_timeChange(
        address user_
    ) public {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawTimeSetUp();

        // Add second depositor
        vm.prank(bob);
        liquidityVault.deposit(1e18, 0);
        vm.warp(block.timestamp + 10); // Increase time by 10 seconds

        // Alice's rewards should be 1.5 EXTERNAL_REWARD tokens
        // 1 for the first 10 blocks and 0.5 for the second 10 blocks
        // Verify initial state
        assertEq(externalReward.balanceOf(alice), 0);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertApproxEqRel(externalReward.balanceOf(alice), 15e17, 1e16); // 1e16 = 1%
    }

    function testCorrectness_withdrawFailsIfUserHasNoLpPosition_timeChange() public {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);
    }

    function testCorrectness_withdrawRemovesWstethAndOhmFromVault_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        uint256 initialWstethBalance = wsteth.balanceOf(address(vault));
        uint256 initialOhmBalance = ohm.balanceOf(address(vault));
        assertTrue(initialWstethBalance > 0);
        assertTrue(initialOhmBalance > 0);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Verify end state
        assertTrue((initialWstethBalance - wsteth.balanceOf(address(vault))) > 0);
        assertTrue((initialOhmBalance - ohm.balanceOf(address(vault))) > 0);
    }

    function testCorrectness_withdrawDecreasesUserWstethDeposit_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        uint256 initialDeposit = liquidityVault.pairTokenDeposits(alice);
        assertEq(initialDeposit, WSTETH_AMOUNT);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Verify end state
        assertTrue((initialDeposit - liquidityVault.pairTokenDeposits(alice)) > 0);
    }

    function testCorrectness_withdrawUpdatesRewardDebt_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Verify end state
        assertEq(liquidityVault.userRewardDebts(alice, address(ldo)), 0);
    }

    function testCorrectness_withdrawBurnsOhm_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        assertTrue(ohm.balanceOf(address(vault)) > 0);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Verify end state
        assertEq(ohm.balanceOf(address(liquidityVault)), 0);
    }

    function testCorrectness_withdrawTransfersWstethToUser_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        uint256 initialWstethBalance = wsteth.balanceOf(alice);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Verify end state
        assertTrue((wsteth.balanceOf(alice) - initialWstethBalance) > 0);
    }

    /// [X]  claimRewards
    ///     [X]  Doesn't fail
    ///     [X]  Returns correct amount of rewards for one token and one user
    ///     [X]  Returns correct amount of rewards for one token and multiple users
    ///     [X]  Returns correct amount of rewards for multiple tokens and multiple users

    function _claimRewardsAddToken() internal {
        // Add reward token
        vm.prank(guardian);
        liquidityVault.addInternalRewardToken(address(reward2), 1e18, block.timestamp); // 1 REWARD2 token per second
        reward2.mint(address(liquidityVault), 1e23);
    }

    function testCorrectness_claimRewardsDoesntFail() public {
        // Setup
        _withdrawTimeSetUp();

        // Claim rewards
        vm.prank(alice);
        liquidityVault.claimRewards();
    }

    function testCorrectness_claimRewardsOneTokenOneUser() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        assertEq(ldo.balanceOf(alice), 0);

        // Claim rewards
        vm.prank(alice);
        liquidityVault.claimRewards();

        // Verify end state
        assertApproxEqRel(ldo.balanceOf(alice), 10e18, 1e16); // 1e16 = 1%
    }

    function testCorrectness_claimRewardsOneTokenMultipleUsers() public {
        // Setup
        _withdrawTimeSetUp();

        // Add second depositor
        vm.prank(bob);
        liquidityVault.deposit(1e18, 0);
        vm.warp(block.timestamp + 10); // Increase time by 10 seconds

        // Alice's rewards should be 15 REWARD tokens
        // 10 for the first 10 blocks and 5 for the second 10 blocks
        // Bob's rewards should be 5 REWARD tokens
        // Verify initial state
        assertEq(ldo.balanceOf(alice), 0);
        assertEq(ldo.balanceOf(bob), 0);

        // Claim Alice's rewards
        vm.prank(alice);
        liquidityVault.claimRewards();

        // Verify end state
        assertApproxEqRel(ldo.balanceOf(alice), 15e18, 1e16); // 1e16 = 1%
        assertApproxEqRel(liquidityVault.internalRewardsForToken(0, bob), 5e18, 1e16); // 1e16 = 1%
    }

    function testCorrectness_claimRewardsMultipleTokensMultipleUsers() public {
        // Setup
        _withdrawTimeSetUp();
        _claimRewardsAddToken();

        // Add second depositor
        vm.prank(bob);
        liquidityVault.deposit(1e18, 0);
        vm.warp(block.timestamp + 10); // Increase time by 10 seconds

        // Alice's rewards should be 15 REWARD tokens and 5 REWARD2 token
        // Bob's rewards should be 5 REWARD tokens and 5 REWARD2 tokens
        // Verify initial state
        assertEq(ldo.balanceOf(alice), 0);
        assertEq(reward2.balanceOf(alice), 0);
        assertEq(ldo.balanceOf(bob), 0);
        assertEq(reward2.balanceOf(bob), 0);

        // Claim Alice's rewards
        vm.prank(alice);
        liquidityVault.claimRewards();

        // Verify end state
        assertApproxEqRel(ldo.balanceOf(alice), 15e18, 1e16); // 1e16 = 1%
        assertApproxEqRel(reward2.balanceOf(alice), 5e18, 1e16); // 1e16 = 1%
        assertApproxEqRel(liquidityVault.internalRewardsForToken(0, bob), 5e18, 1e16); // 1e16 = 1%
        assertApproxEqRel(liquidityVault.internalRewardsForToken(1, bob), 5e18, 1e16); // 1e16 = 1%
    }

    /// [X]  getExpectedLPAmount
    ///     [X]  Returns correct amount of LP tokens for a deposit of 1 ETH
    ///     [X]  Always reverts

    function testCorrectness_getExpectedLPAmountReturnsCorrectAmount() public {
        // Cache initial balances
        uint256 initialLpBalance = ERC20(liquidityVault.liquidityPool()).balanceOf(
            address(liquidityVault)
        );
        uint256 initialWstethBalance = wsteth.balanceOf(address(liquidityVault));
        uint256 initialOhmBalance = ohm.balanceOf(address(liquidityVault));

        // Calculate expected LP amount
        assertTrue(liquidityVault.getExpectedLPAmount(1e18) > 0);
        console2.log(liquidityVault.getExpectedLPAmount(1e18) / 1e18);

        // No state should change
        assertEq(
            ERC20(liquidityVault.liquidityPool()).balanceOf(address(liquidityVault)),
            initialLpBalance
        );
        assertEq(wsteth.balanceOf(address(liquidityVault)), initialWstethBalance);
        assertEq(ohm.balanceOf(address(liquidityVault)), initialOhmBalance);
    }
}
