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
import {OlympusLiquidityRegistry} from "modules/LQREG/OlympusLiquidityRegistry.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {WstethLiquidityVault} from "policies/lending/WstethLiquidityVault.sol";

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
contract WstethLiquidityVaultTest is Test {
    using FullMath for uint256;
    using larping for *;

    UserFactory public userCreator;
    address internal alice;
    address public godmode;

    OlympusERC20Token internal ohm;
    MockWsteth internal wsteth;
    MockERC20 internal reward;
    MockERC20 internal reward2;
    MockERC20 internal externalReward;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;
    MockPriceFeed internal stethUsdPriceFeed;

    MockVault internal vault;
    MockBalancerPool internal liquidityPool;

    MockAuraBooster internal booster;
    MockAuraRewardPool internal auraPool;

    Kernel internal kernel;
    OlympusMinter internal minter;
    OlympusLiquidityRegistry internal lqreg;
    OlympusRoles internal roles;

    RolesAdmin internal rolesAdmin;
    WstethLiquidityVault internal liquidityVault;

    IOlympusAuthority internal auth;

    uint256 internal constant WSTETH_AMOUNT = 1e18;
    uint256[] internal minTokenAmounts_ = [100e9, 1e18];

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        {
            // Deploy mock users
            userCreator = new UserFactory();
            address[] memory users = userCreator.create(1);
            alice = users[0];
        }

        {
            // Deploy auth
            auth = new MockLegacyAuthority(address(0x0));
        }

        {
            // Deploy mock tokens
            ohm = new OlympusERC20Token(address(auth));
            wsteth = new MockWsteth("Wrapped Staked ETH", "wstETH", 18);
            reward = new MockERC20("Reward Token", "REWARD", 18);
            reward2 = new MockERC20("Reward Token 2", "REWARD2", 18);
            externalReward = new MockERC20("External Reward Token", "EXTREWARD", 18);
        }

        {
            // Deploy mock price feeds
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

        {
            // Deploy mock Balancer contracts
            liquidityPool = new MockBalancerPool();
            vault = new MockVault(address(liquidityPool), address(ohm), address(wsteth));
            vault.setPoolAmounts(100e9, 1e18);
        }

        {
            // Deploy mock Aura contracts
            auraPool = new MockAuraRewardPool(address(vault.bpt()), address(externalReward));
            booster = new MockAuraBooster(address(vault.bpt()), address(auraPool));
        }

        {
            // Deploy kernel
            kernel = new Kernel();

            // Deploy modules
            minter = new OlympusMinter(kernel, address(ohm));
            lqreg = new OlympusLiquidityRegistry(kernel);
            roles = new OlympusRoles(kernel);

            // Set vault in auth to MINTR
            auth.vault.larp(address(minter));
        }

        {
            // Deploy roles admin
            rolesAdmin = new RolesAdmin(kernel);

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
                address(0), // Balancer helper, not needed in mock tests
                address(liquidityPool),
                ohmEthFeedStruct,
                ethUsdFeedStruct,
                stethUsdFeedStruct,
                auraPoolStruct
            );
        }

        {
            // Initialize system and kernel

            // Initialize modules
            kernel.executeAction(Actions.InstallModule, address(minter));
            kernel.executeAction(Actions.InstallModule, address(lqreg));
            kernel.executeAction(Actions.InstallModule, address(roles));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ActivatePolicy, address(liquidityVault));
        }

        {
            // Set roles
            rolesAdmin.grantRole("liquidityvault_admin", address(this));
        }

        {
            // Set limit
            liquidityVault.setLimit(1000e9); // 1000 OHM

            // Set price variation threshold to 10%
            liquidityVault.setThreshold(100);

            // Add reward token
            liquidityVault.addInternalRewardToken(address(reward), 1e18, block.timestamp); // 1 REWARD token per second
            liquidityVault.addExternalRewardToken(address(externalReward));

            // Activate vault
            liquidityVault.activate();

            reward.mint(address(liquidityVault), 1e23);
        }

        {
            /// Initialize timestamps on mock price feeds
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            ethUsdPriceFeed.setTimestamp(block.timestamp);
            stethUsdPriceFeed.setTimestamp(block.timestamp);
        }

        {
            // Mint wstETH to alice
            wsteth.mint(alice, WSTETH_AMOUNT);

            // Approve vault to spend alice's wstETH
            vm.prank(alice);
            wsteth.approve(address(liquidityVault), WSTETH_AMOUNT);
        }
    }

    /// [X]  deposit
    ///     [X]  Cannot be accessed when inactive
    ///     [X]  Can be accessed by anyone
    ///     [X]  Can handle any amount up to the limit
    ///     [X]  Fails if pool is imbalanced
    ///     [X]  Cannot be called beyond limit
    ///     [X]  Limit persists correctly as price moves
    ///     [X]  Increases user's wstETH deposit
    ///     [X]  Correctly values stETH in terms of OHM
    ///     [X]  Transfers wstETH from user
    ///     [X]  Deposits wstETH and OHM into Balancer LP
    ///     [X]  Deposits Balancer LP into Aura
    ///     [X]  Updates user's tracked LP position
    ///     [X]  Updates tracked total LP amount

    function testCorrectness_depositCannotBeAccessedWhenInactive() public {
        liquidityVault.deactivate();

        // Get error
        bytes memory err = abi.encodeWithSignature("LiquidityVault_Inactive()");
        vm.expectRevert(err);

        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 0);
    }

    function testCorrectness_depositUserAndAmountFuzz(address user_) public {
        vm.assume(user_ != address(0) && user_ != address(liquidityVault));

        wsteth.mint(user_, 1e18);

        vm.startPrank(user_);
        wsteth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);
        vm.stopPrank();
    }

    function testCorrectness_depositCanHandleAnyAmountUpToLimit(uint256 amount_) public {
        vm.assume(amount_ >= 1e7 && amount_ <= 1_000_000_000e18);

        wsteth.mint(alice, amount_);
        liquidityVault.setLimit(type(uint256).max);

        vm.startPrank(alice);
        wsteth.approve(address(liquidityVault), amount_);
        liquidityVault.deposit(amount_, 0);
        vm.stopPrank();
    }

    function testCorrectness_depositCannotBeCalledBeyondLimit() public {
        wsteth.mint(alice, 1e19);

        vm.startPrank(alice);
        wsteth.approve(address(liquidityVault), 2e19);
        liquidityVault.deposit(1e19, 1e18); // Should mint 1000 OHM which is up to the limit

        bytes memory err = abi.encodeWithSignature("LiquidityVault_LimitViolation()");
        vm.expectRevert(err);

        liquidityVault.deposit(1e18, 1e18); // Should try to push mint beyond limit
        vm.stopPrank();
    }

    function testCorrectness_depositLimitPersistsCorrectlyAsPriceMoves() public {
        // Alice deposits up to the limit
        wsteth.mint(alice, 1e19);
        vm.startPrank(alice);
        wsteth.approve(address(liquidityVault), 1e19);
        liquidityVault.deposit(1e19, 1e18); // Should mint 1000 OHM which is up to the limit

        bytes memory err = abi.encodeWithSignature("LiquidityVault_LimitViolation()");
        vm.expectRevert(err);

        // Try to deposit
        liquidityVault.deposit(1e18, 1e18); // Should try to push mint beyond limit

        // Shift pool price to emit OHM to circulating supply
        vault.setPoolAmounts(500e9, 15e18);
        ohmEthPriceFeed.setLatestAnswer(3e16); // 0.03 ETH

        // Try to deposit again
        // System should still consider there to be 1000 OHM since 500 are in the pool
        // and 500 were emitted to the circulating supply
        vm.expectRevert(err);
        liquidityVault.deposit(1e18, 1e18);

        // Shift price to have net removed OHM from circulating supply
        vault.setPoolAmounts(2000e9, 1e18);
        ohmEthPriceFeed.setLatestAnswer(5e14); // 0.0005 ETH

        // Try to deposit again
        // System should till consider there to be 1000 OHM since ohmMinted is 1000 but
        // 500 were removed from the circulating supply
        vm.expectRevert(err);
        liquidityVault.deposit(1e18, 1e18);
    }

    function testCorrectness_depositFailsIfPricesDiffer() public {
        // Set pool price
        vault.setPoolAmounts(1e7, 10e18);

        bytes memory err = abi.encodeWithSignature("LiquidityVault_PoolImbalanced()");
        vm.expectRevert(err);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.deposit(1e18, 1e18);

        // Set pool price
        vault.setPoolAmounts(1000e9, 1e18);

        // Expect revert again
        vm.expectRevert(err);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.deposit(1e18, 1e18);
    }

    function testCorrectness_depositIncreasesUserWstethDeposit() public {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 1e18);

        assertEq(liquidityVault.pairTokenDeposits(alice), WSTETH_AMOUNT);
    }

    function testCorrectness_depositCorrectlyValuesWsteth() public {
        vm.prank(alice);
        liquidityVault.deposit(1e18, 1e18);

        assertEq(ohm.balanceOf(address(vault)), 100e9);
    }

    function testCorrectness_depositTransfersWstethFromUser() public {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 1e18);

        assertEq(wsteth.balanceOf(alice), 0);
    }

    function testCorrectness_depositDepositsWstethAndOhmToVault() public {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 1e18);

        assertEq(wsteth.balanceOf(address(vault)), WSTETH_AMOUNT);
        assertEq(ohm.balanceOf(address(vault)), WSTETH_AMOUNT / 1e7);
    }

    function testCorrectness_depositDepositsBptToAura() public {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 1e18);

        assertEq(liquidityPool.balanceOf(address(liquidityVault)), 0);
        assertEq(liquidityPool.balanceOf(address(auraPool)), 1e18);
    }

    function testCorrectness_depositUpdatesUserTrackedLpPosition() public {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 1e18);

        assertTrue(liquidityVault.lpPositions(alice) > 0);
    }

    function testCorrectness_depositUpdatesTrackedTotalLPAmount() public {
        vm.prank(alice);
        liquidityVault.deposit(WSTETH_AMOUNT, 1e18);

        assertEq(liquidityVault.totalLP(), 1e18);
    }

    /// [X]  withdraw (no time has passed)
    ///     [X]  Cannot be called when inactive
    ///     [X]  Withdraw anyone can deposit
    ///     [X]  Withdraw can be called with any amount up to the limit
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

    function testCorrectness_withdrawCannotBeCalledWhenInactive_noTimeChange() public {
        liquidityVault.deactivate();

        bytes memory err = abi.encodeWithSignature("LiquidityVault_Inactive()");
        vm.expectRevert(err);

        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, false);
    }

    function testCorrectness_withdrawAnyoneCanWithdraw_noTimeChange(address user_) public {
        vm.assume(user_ != address(0) && user_ != address(liquidityVault));

        // Mint wstETH
        wsteth.mint(user_, 1e18);

        // Deposit
        vm.startPrank(user_);
        wsteth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);

        // Get user lp position
        uint256 userLpPosition = liquidityVault.lpPositions(user_);

        // Withdraw and claim
        liquidityVault.withdraw(userLpPosition, minTokenAmounts_, false);
        vm.stopPrank();
    }

    function testCorrectness_withdrawCanBeCalledWithAnyAmountUpToTheLimit_noTimeChange(
        uint256 amount_
    ) public {
        vm.assume(amount_ >= 1e7 && amount_ <= 1_000_000_000e18);

        // Mint wstETH
        wsteth.mint(alice, amount_);
        liquidityVault.setLimit(type(uint256).max);

        // Deposit
        vm.startPrank(alice);
        wsteth.approve(address(liquidityVault), amount_);
        liquidityVault.deposit(amount_, 0);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, false);
        vm.stopPrank();
    }

    function testCorrectness_withdrawFailsIfPricesDiffer_noTimeChange() public {
        // Setup
        _withdrawSetUp();

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Set pool price
        vault.setPoolAmounts(1e7, 10e18);

        bytes memory err = abi.encodeWithSignature("LiquidityVault_PoolImbalanced()");
        vm.expectRevert(err);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, false);

        // Set pool price
        vault.setPoolAmounts(1000e9, 1e18);

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
        assertEq(reward.balanceOf(alice), 0);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, true);

        // Verify end state
        assertEq(reward.balanceOf(alice), 0);
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
        assertEq(wsteth.balanceOf(address(vault)), WSTETH_AMOUNT);
        assertEq(ohm.balanceOf(address(vault)), WSTETH_AMOUNT / 1e7);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, false);

        // Verify end state
        assertEq(wsteth.balanceOf(address(vault)), 0);
        assertEq(ohm.balanceOf(address(vault)), 0);
    }

    function testCorrectness_withdrawDecreasesUserWstethDeposit_noTimeChange() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        assertEq(liquidityVault.pairTokenDeposits(alice), WSTETH_AMOUNT);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, false);

        // Verify end state
        assertEq(liquidityVault.pairTokenDeposits(alice), 0);
    }

    function testCorrectness_withdrawBurnsOhm_noTimeChange() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        assertEq(ohm.balanceOf(address(vault)), WSTETH_AMOUNT / 1e7);

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

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, false);

        // Verify end state
        assertEq(wsteth.balanceOf(alice), WSTETH_AMOUNT);
    }

    /// [X]  withdraw (time has passed)
    ///     [X]  Cannot be accessed when inactive
    ///     [X]  Can be accessed by anyone
    ///     [X]  Withdraw can be called with any amount up to the limit
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
        liquidityVault.deposit(WSTETH_AMOUNT, 1e18);
        vm.warp(block.timestamp + 10); // Increase time 10 seconds so there are rewards
    }

    function testCorrectness_withdrawCannotBeCalledWhenInactive_timeChange() public {
        liquidityVault.deactivate();

        bytes memory err = abi.encodeWithSignature("LiquidityVault_Inactive()");
        vm.expectRevert(err);

        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, false);
    }

    function testCorrectness_withdrawUserFuzz_timeChange(address user_) public {
        vm.assume(user_ != address(0) && user_ != address(liquidityVault));

        wsteth.mint(user_, 1e18);

        // Setup with deposit
        vm.startPrank(user_);
        wsteth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);

        // Get user lp position
        uint256 userLpPosition = liquidityVault.lpPositions(user_);

        // Withdraw and claim
        liquidityVault.withdraw(userLpPosition, minTokenAmounts_, true);
        vm.stopPrank();
    }

    function testCorrectness_withdrawCanBeCalledWithAnyAmountUpToTheLimit_timeChange(
        uint256 amount_
    ) public {
        vm.assume(amount_ >= 1e7 && amount_ <= 1_000_000_000e18);

        // Mint wstETH
        wsteth.mint(alice, amount_);
        liquidityVault.setLimit(type(uint256).max);

        // Deposit
        vm.startPrank(alice);
        wsteth.approve(address(liquidityVault), amount_);
        liquidityVault.deposit(amount_, 0);

        // Get alice lp position
        uint256 aliceLpPosition = liquidityVault.lpPositions(alice);

        // Withdraw
        liquidityVault.withdraw(aliceLpPosition, minTokenAmounts_, false);
        vm.stopPrank();
    }

    function testCorrectness_withdrawFailsIfPricesDiffer_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Set pool price
        vault.setPoolAmounts(1e7, 10e18);

        bytes memory err = abi.encodeWithSignature("LiquidityVault_PoolImbalanced()");
        vm.expectRevert(err);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Set pool price
        vault.setPoolAmounts(1000e9, 1e18);

        // Expect revert again
        vm.expectRevert(err);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);
    }

    function testCorrectness_withdrawForegoesRewardsIfCalledWithoutClaim_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        assertEq(reward.balanceOf(alice), 0);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, false);

        // Verify end state
        assertEq(reward.balanceOf(alice), 0);
    }

    function testCorrectness_withdrawClaimsRewards_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        assertEq(reward.balanceOf(alice), 0);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(reward.balanceOf(alice), 10e18);
    }

    function testCorrectness_withdrawClaimsExternalRewards_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        assertEq(externalReward.balanceOf(alice), 0);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(externalReward.balanceOf(alice), 1e18);
    }

    function testCorrectness_withdrawReturnsCorrectRewardsMultiUser_timeChange(address user_)
        public
    {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawTimeSetUp();

        // Add second depositor
        vm.startPrank(user_);
        wsteth.mint(user_, 1e18);
        wsteth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);
        vm.stopPrank();
        vm.warp(block.timestamp + 10); // Increase time by 10 seconds

        // Alice's rewards should be 15 REWARD tokens
        // 10 for the first 10 blocks and 5 for the second 10 blocks
        // Verify initial state
        assertEq(reward.balanceOf(alice), 0);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(reward.balanceOf(alice), 15e18);
    }

    function testCorrectness_withdrawReturnsCorrectExternalRewardsMultiUser_timeChange(
        address user_
    ) public {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawTimeSetUp();

        // Add second depositor
        vm.startPrank(user_);
        wsteth.mint(user_, 1e18);
        wsteth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);
        vm.stopPrank();
        vm.warp(block.timestamp + 10); // Increase time by 10 seconds

        // Alice's rewards should be 1.5 EXTERNAL_REWARD tokens
        // 1 for the first 10 blocks and 0.5 for the second 10 blocks
        // Verify initial state
        assertEq(externalReward.balanceOf(alice), 0);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(externalReward.balanceOf(alice), 15e17);
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
        assertEq(wsteth.balanceOf(address(vault)), WSTETH_AMOUNT);
        assertEq(ohm.balanceOf(address(vault)), WSTETH_AMOUNT / 1e7);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(wsteth.balanceOf(address(vault)), 0);
        assertEq(ohm.balanceOf(address(vault)), 0);
    }

    function testCorrectness_withdrawDecreasesUserWstethDeposit_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        assertEq(liquidityVault.pairTokenDeposits(alice), WSTETH_AMOUNT);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(liquidityVault.pairTokenDeposits(alice), 0);
    }

    function testCorrectness_withdrawUpdatesRewardDebt_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(liquidityVault.userRewardDebts(alice, address(reward)), 0);
    }

    function testCorrectness_withdrawBurnsOhm_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        assertEq(ohm.balanceOf(address(vault)), WSTETH_AMOUNT / 1e7);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(ohm.balanceOf(address(liquidityVault)), 0);
    }

    function testCorrectness_withdrawTransfersWstethToUser_timeChange() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        assertEq(wsteth.balanceOf(alice), 0);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(wsteth.balanceOf(alice), 1e18);
    }

    /// [X]  claimRewards
    ///     [X]  Can be accessed by anyone
    ///     [X]  Returns correct amount of rewards for one token and one user
    ///     [X]  Returns correct amount of rewards for one token and multiple users
    ///     [X]  Returns correct amount of rewards for multiple tokens and multiple users

    function _claimRewardsAddToken() internal {
        // Add reward token
        liquidityVault.addInternalRewardToken(address(reward2), 1e18, block.timestamp); // 1 REWARD2 token per second
        reward2.mint(address(liquidityVault), 1e23);
    }

    function testCorrectness_claimRewardsCanBeAccessedByAnyone() public {
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
        assertEq(reward.balanceOf(alice), 0);

        // Claim rewards
        vm.prank(alice);
        liquidityVault.claimRewards();

        // Verify end state
        assertEq(reward.balanceOf(alice), 10e18);
    }

    function testCorrectness_claimRewardsOneTokenMultipleUsers(address user_) public {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawTimeSetUp();

        // Add second depositor
        vm.startPrank(user_);
        wsteth.mint(user_, 1e18);
        wsteth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);
        vm.stopPrank();
        vm.warp(block.timestamp + 10); // Increase time by 10 seconds

        // Alice's rewards should be 15 REWARD tokens
        // 10 for the first 10 blocks and 5 for the second 10 blocks
        // User's rewards should be 5 REWARD tokens
        // Verify initial state
        assertEq(reward.balanceOf(alice), 0);
        assertEq(reward.balanceOf(user_), 0);

        // Claim Alice's rewards
        vm.prank(alice);
        liquidityVault.claimRewards();

        // Verify end state
        assertEq(reward.balanceOf(alice), 15e18);
        assertEq(liquidityVault.internalRewardsForToken(0, user_), 5e18);
    }

    function testCorrectness_claimRewardsMultipleTokensMultipleUsers(address user_) public {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawTimeSetUp();
        _claimRewardsAddToken();

        // Add second depositor
        vm.startPrank(user_);
        wsteth.mint(user_, 1e18);
        wsteth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);
        vm.stopPrank();
        vm.warp(block.timestamp + 10); // Increase time by 10 seconds

        // Alice's rewards should be 15 REWARD tokens and 5 REWARD2 token
        // User's rewards should be 5 REWARD tokens and 5 REWARD2 tokens
        // Verify initial state
        assertEq(reward.balanceOf(alice), 0);
        assertEq(reward2.balanceOf(alice), 0);
        assertEq(reward.balanceOf(user_), 0);
        assertEq(reward2.balanceOf(user_), 0);

        // Claim Alice's rewards
        vm.prank(alice);
        liquidityVault.claimRewards();

        // Verify end state
        assertEq(reward.balanceOf(alice), 15e18);
        assertEq(reward2.balanceOf(alice), 5e18);
        assertEq(liquidityVault.internalRewardsForToken(0, user_), 5e18);
        assertEq(liquidityVault.internalRewardsForToken(1, user_), 5e18);
    }

    /// [X]  Antagnonist tests
    ///     [X]  Cannot get infinite rewards

    function _withdrawSetUpAntagonist() internal {
        liquidityVault.setLimit(1_000_000e9);
        wsteth.mint(alice, 1_000e18);

        vm.startPrank(alice);
        wsteth.approve(address(liquidityVault), WSTETH_AMOUNT * 100);
        liquidityVault.deposit(WSTETH_AMOUNT * 100, 100e18);
        vm.stopPrank();
        vm.warp(block.timestamp + 10); // Increase time 10 seconds so there are rewards
    }

    function testCorrectness_infiniteRewards(address user_) public {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawSetUpAntagonist();

        // Add second depositor
        vm.startPrank(user_);
        wsteth.mint(user_, 1e18);
        wsteth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);
        liquidityVault.withdraw(1, minTokenAmounts_, false);
        vm.stopPrank();

        assertFalse(liquidityVault.internalRewardsForToken(0, user_) == type(uint256).max);
    }

    // ========= VIEW TESTS ========= //

    /// [X]  getMaxDeposit
    /// [X]  internalRewardsForToken
    /// [X]  externalRewardsForToken
    /// [X]  getOhmEmissions

    function testCorrectness_getMaxDeposit() public {
        // Check default limit
        assertEq(liquidityVault.getMaxDeposit(), 1e19);

        // Price moves
        ohmEthPriceFeed.setLatestAnswer(1e17);

        // Check limit
        assertEq(liquidityVault.getMaxDeposit(), 1e20);

        // Reset price
        ohmEthPriceFeed.setLatestAnswer(1e16);

        // Deposit
        vm.prank(alice);
        liquidityVault.deposit(1e18, 1e18);

        // Check limit
        assertEq(liquidityVault.getMaxDeposit(), 9e18);
    }

    function testCorrectness_internalRewardsForToken(address user_) public {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawTimeSetUp();
        _claimRewardsAddToken();

        // Add second depositor
        vm.startPrank(user_);
        wsteth.mint(user_, 1e18);
        wsteth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);
        vm.stopPrank();
        vm.warp(block.timestamp + 10); // Increase time by 10 seconds

        // Alice's rewards should be 15 REWARD tokens and 5 REWARD2 token
        // User's rewards should be 5 REWARD tokens and 5 REWARD2 tokens
        assertEq(liquidityVault.internalRewardsForToken(0, alice), 15e18);
        assertEq(liquidityVault.internalRewardsForToken(1, alice), 5e18);
        assertEq(liquidityVault.internalRewardsForToken(0, user_), 5e18);
        assertEq(liquidityVault.internalRewardsForToken(1, user_), 5e18);
    }

    function testCorrectness_externalRewardsForToken(address user_) public {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawTimeSetUp();

        // Add second depositor
        vm.startPrank(user_);
        wsteth.mint(user_, 1e18);
        wsteth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);
        vm.stopPrank();
        vm.warp(block.timestamp + 10); // Increase time by 10 seconds

        // Trigger external rewards accumulation
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, false);

        // Alice's rewards should be 1.5 external tokens
        // User's rewards should be 0.5 external tokens
        assertEq(liquidityVault.externalRewardsForToken(0, alice), 15e17);
        assertEq(liquidityVault.externalRewardsForToken(0, user_), 5e17);
    }

    function testCorrectness_getOhmEmissions() public {
        // Setup
        _withdrawTimeSetUp();

        // Verify initial state
        (uint256 emissions, uint256 removals) = liquidityVault.getOhmEmissions();
        assertEq(emissions, 0);
        assertEq(removals, 0);

        // Pools change in price
        vault.setPoolAmounts(200e9, 1e18);

        // Verify end state
        (emissions, removals) = liquidityVault.getOhmEmissions();
        assertEq(emissions, 0);
        assertEq(removals, 100e9);
    }

    // ========= ADMIN TESTS ========= //

    /// [X]  activate
    ///     [X]  Can only be called by admin
    ///     [X]  Adds vault to LQREG

    function _activateSetup() internal {
        // Remove currently activated vault
        liquidityVault.deactivate();
    }

    function testCorrectness_activateCanOnlyBeCalledByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        _activateSetup();

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        liquidityVault.activate();
    }

    function testCorrectness_activateCorrectlyAddsVaultToLQREG() public {
        _activateSetup();

        // Verify initial state
        assertEq(lqreg.activeVaultCount(), 0);

        // Activate vault
        liquidityVault.activate();

        // Verify end state
        assertEq(lqreg.activeVaultCount(), 1);
        assertEq(lqreg.activeVaults(0), address(liquidityVault));
    }

    /// [X]  deactivate
    ///     [X]  Can only be called by admin
    ///     [X]  Removes vault from LQREG

    function testCorrectness_deactivateCanOnlyBeCalledByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        liquidityVault.deactivate();
    }

    function testCorrectness_deactivateCorrectlyRemovesVaultFromLQREG() public {
        _activateSetup();

        // Activate vault
        liquidityVault.activate();

        // Verify initial state
        assertEq(lqreg.activeVaultCount(), 1);
        assertEq(lqreg.activeVaults(0), address(liquidityVault));

        // Deactivate vault
        liquidityVault.deactivate();

        // Verify end state
        assertEq(lqreg.activeVaultCount(), 0);
    }

    /// [X]  addInternalRewardToken
    ///     [X]  Can only be called by admin
    ///     [X]  Adds reward token correctly

    function testCorrectness_addInternalRewardTokenCanOnlyBeCalledByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        liquidityVault.addInternalRewardToken(address(reward), 1e18, block.timestamp);
    }

    function testCorrectness_addInternalRewardTokenCorrectlyAddsToken() public {
        // Add reward token
        liquidityVault.addInternalRewardToken(address(reward2), 1e18, block.timestamp); // 1 REWARD2 token per second

        // Verify state
        (
            address token,
            uint256 decimals,
            uint256 rewardsPerSecond,
            ,
            uint256 accumulatedRewardsPerShare
        ) = liquidityVault.internalRewardTokens(1);
        assertEq(token, address(reward2));
        assertEq(decimals, 1e18);
        assertEq(rewardsPerSecond, 1e18);
        assertEq(accumulatedRewardsPerShare, 0);
    }

    /// [X]  removeInternalRewardToken
    ///     [X]  Can only be called by admin
    ///     [X]  Fails on sanity check
    ///     [X]  Removes reward token correctly

    function testCorrectness_removeInternalRewardTokenCanOnlyBeCalledByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        liquidityVault.removeInternalRewardToken(0, address(reward2));
    }

    function testCorrectness_removeInternalRewardTokenFailsOnSanityCheck() public {
        // Add reward token
        liquidityVault.addInternalRewardToken(address(reward2), 1e18, block.timestamp); // 1 REWARD2 token per second

        bytes memory err = abi.encodeWithSignature("LiquidityVault_InvalidRemoval()");
        vm.expectRevert(err);

        // Remove reward token with wrong index
        liquidityVault.removeInternalRewardToken(0, address(reward2));
    }

    function testCorrectness_removeRewardTokenCorrectlyRemovesToken() public {
        // Add reward token
        liquidityVault.addInternalRewardToken(address(reward2), 1e18, block.timestamp); // 1 REWARD2 token per second

        // Verify initial state
        (
            address token,
            uint256 decimals,
            uint256 rewardsPerSecond,
            ,
            uint256 accumulatedRewardsPerShare
        ) = liquidityVault.internalRewardTokens(1);
        assertEq(token, address(reward2));
        assertEq(decimals, 1e18);
        assertEq(rewardsPerSecond, 1e18);
        assertEq(accumulatedRewardsPerShare, 0);

        // Remove reward token
        liquidityVault.removeInternalRewardToken(1, address(reward2));

        // Verify end state
        vm.expectRevert();
        (token, decimals, rewardsPerSecond, , accumulatedRewardsPerShare) = liquidityVault
            .internalRewardTokens(1);
    }

    /// [X]  addExternalRewardToken
    ///     [X]  Can only be called by admin
    ///     [X]  Adds external reward token correctly

    function testCorrectness_addExternalRewardTokenCanOnlyBeCalledByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        liquidityVault.addExternalRewardToken(address(externalReward));
    }

    function testCorrectness_addExternalRewardTokenCorrectlyAddsToken() public {
        // Add external reward token
        liquidityVault.addExternalRewardToken(address(externalReward));

        // Verify state
        (
            address token,
            uint256 decimals,
            uint256 accumulatedRewardsPerShare,
            uint256 lastBalance
        ) = liquidityVault.externalRewardTokens(1);
        assertEq(token, address(externalReward));
        assertEq(decimals, 1e18);
        assertEq(accumulatedRewardsPerShare, 0);
        assertEq(lastBalance, 0);
    }

    /// [X]  removeExternalRewardToken
    ///     [X]  Can only be called by admin
    ///     [X]  Fails on sanity check
    ///     [X]  Removes external reward token correctly

    function testCorrectness_removeExternalRewardTokenCanOnlyBeCalledByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        liquidityVault.removeExternalRewardToken(0, address(externalReward));
    }

    function testCorrectness_removeExternalRewardTokenFailsOnSanityCheck() public {
        // Add external reward token
        liquidityVault.addExternalRewardToken(address(reward2));

        bytes memory err = abi.encodeWithSignature("LiquidityVault_InvalidRemoval()");
        vm.expectRevert(err);

        // Remove external reward token with wrong index
        liquidityVault.removeExternalRewardToken(0, address(reward2));
    }

    function testCorrectness_removeExternalRewardTokenCorrectlyRemovesToken() public {
        // Add external reward token
        liquidityVault.addExternalRewardToken(address(externalReward));

        // Verify initial state
        (
            address token,
            uint256 decimals,
            uint256 accumulatedRewardsPerShare,
            uint256 lastBalance
        ) = liquidityVault.externalRewardTokens(1);
        assertEq(token, address(externalReward));
        assertEq(decimals, 1e18);
        assertEq(accumulatedRewardsPerShare, 0);
        assertEq(lastBalance, 0);

        // Remove external reward token
        liquidityVault.removeExternalRewardToken(1, address(externalReward));

        // Verify end state
        vm.expectRevert();
        (token, decimals, accumulatedRewardsPerShare, lastBalance) = liquidityVault
            .externalRewardTokens(1);
    }

    // [X]   claimFees
    ///     [X]  Can only be called by admin
    ///     [X]  Claims fees correctly

    function testCorrectness_claimFeesCanOnlyBeCalledByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        liquidityVault.claimFees();
    }

    function testCorrectness_claimFeesCorrectlyClaimsFees() public {
        // Set FEE to 10%
        liquidityVault.setFee(100);

        // Setup
        _withdrawTimeSetUp();

        // Trigger fee accumulation
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Accumulated fees should be 1e18 REWARD and 1e17 externalReward
        assertEq(liquidityVault.accumulatedFees(address(reward)), 1e18);
        assertEq(liquidityVault.accumulatedFees(address(externalReward)), 1e17);

        // Claim fees
        liquidityVault.claimFees();

        // Admin should have balances
        assertEq(reward.balanceOf(address(this)), 1e18);
        assertEq(externalReward.balanceOf(address(this)), 1e17);
    }

    /// []  setLimit
    ///     [X]  Can only be called by admin
    ///     [X]  Sets limit correctly
    ///     [X]  Fuzz below current minted amount
    ///     [X]  Fuzz above current minted amount

    function testCorrectness_setLimitCanOnlyBeCalledByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        liquidityVault.setLimit(1e18);
    }

    function testCorrectness_setLimitCorrectlySetsLimit() public {
        // Set limit
        liquidityVault.setLimit(1e18);

        // Verify state
        assertEq(liquidityVault.LIMIT(), 1e18);
    }

    function testCorrectness_setLimitFuzzBelowCurrentMintedAmount(uint256 newLimit_) public {
        vm.assume(newLimit_ < 1000e9);

        // Mint extra wstETH to alice
        wsteth.mint(alice, 1e19);

        // Deposit up to limit
        vm.startPrank(alice);
        wsteth.approve(address(liquidityVault), 1e19);
        liquidityVault.deposit(1e19, 1e18);
        vm.stopPrank();

        // Get error
        bytes memory err = abi.encodeWithSignature("LiquidityVault_InvalidParams()");
        vm.expectRevert(err);

        // Set limit
        liquidityVault.setLimit(newLimit_);
    }

    function testCorrectness_setLimitFuzzAboveCurrentMintedAmount(uint256 newLimit_) public {
        // Current minted amount is 0, all values should be valid
        // Set limit
        liquidityVault.setLimit(newLimit_);

        // Verify state
        assertEq(liquidityVault.LIMIT(), newLimit_);
    }

    /// [X]  setThreshold
    ///     [X]  Can only be called by admin
    ///     [X]  Sets threshold correctly
    ///     [X]  Fuzz below precision
    ///     [X]  Fuzz above precision

    function testCorrectness_setThresholdCanOnlyBeCalledByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        liquidityVault.setThreshold(200);
    }

    function testCorrectness_setThresholdCorrectlySetsThreshold() public {
        // Set threshold
        liquidityVault.setThreshold(200);

        // Verify state
        assertEq(liquidityVault.THRESHOLD(), 200);
    }

    function testCorrectness_setThresholdFuzzBelowPrecision(uint256 newThreshold_) public {
        vm.assume(newThreshold_ <= 1000);

        // Set threshold
        liquidityVault.setThreshold(newThreshold_);

        // Verify state
        assertEq(liquidityVault.THRESHOLD(), newThreshold_);
    }

    function testCorrectness_setThresholdFuzzAbovePrecision(uint256 newThreshold_) public {
        vm.assume(newThreshold_ > 1000);

        // Get error
        bytes memory err = abi.encodeWithSignature("LiquidityVault_InvalidParams()");
        vm.expectRevert(err);

        // Set threshold
        liquidityVault.setThreshold(newThreshold_);
    }

    /// [X]  setFee
    ///     [X]  Can only be called by admin
    ///     [X]  Sets fee correctly
    ///     [X]  Fuzz below precision
    ///     [X]  Fuzz above precision

    function testCorrectness_setFeeCanOnlyBeCalledByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        liquidityVault.setFee(10);
    }

    function testCorrectness_setFeeCorrectlySetsFee() public {
        // Set fee
        liquidityVault.setFee(10);

        // Verify state
        assertEq(liquidityVault.FEE(), 10);
    }

    function testCorrectness_setFeeFuzzBelowPrecision(uint256 newFee_) public {
        vm.assume(newFee_ <= 1000);

        // Set fee
        liquidityVault.setFee(newFee_);

        // Verify state
        assertEq(liquidityVault.FEE(), newFee_);
    }

    function testCorrectness_setFeeFuzzAbovePrecision(uint256 newFee_) public {
        vm.assume(newFee_ > 1000);

        // Get error
        bytes memory err = abi.encodeWithSignature("LiquidityVault_InvalidParams()");
        vm.expectRevert(err);

        // Set fee
        liquidityVault.setFee(newFee_);
    }

    /// [X] can view lp positions of all depositors

    function testCorrectness_canViewAllLpPositions(address user_) public {
        vm.assume(user_ != alice && user_ != address(this) && user_ != address(liquidityVault));

        // Alice deposit
        vm.prank(alice);
        liquidityVault.deposit(1e18, 1e18);

        // Add second depositor
        vm.startPrank(user_);
        wsteth.mint(user_, 1e18);
        wsteth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);
        vm.stopPrank();

        // Verify depositor list
        address[] memory users = liquidityVault.getUsers();
        assertEq(users[0], alice);
        assertEq(users[1], user_);

        // Build expected lp positions
        uint256 numUsers = users.length;
        uint256[] memory expectedLpPositions = new uint256[](2);
        for (uint256 i; i < numUsers; ++i) {
            expectedLpPositions[i] = liquidityVault.lpPositions(users[i]);
        }

        assertEq(expectedLpPositions[0], 1e18);
        assertEq(expectedLpPositions[1], 1e18);
    }
}
