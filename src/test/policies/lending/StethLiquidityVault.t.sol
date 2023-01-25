// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test, stdError} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {FullMath} from "libraries/FullMath.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockVault, MockBalancerPool} from "test/mocks/BalancerMocks.sol";
import {MockAuraBooster, MockAuraRewardPool} from "test/mocks/AuraMocks.sol";

import {IAuraBooster, IAuraRewardPool} from "policies/lending/interfaces/IAura.sol";

import {OlympusMinter, OHM} from "modules/MINTR/OlympusMinter.sol";
import {OlympusLiquidityRegistry} from "modules/LQREG/OlympusLiquidityRegistry.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {StethLiquidityVault} from "policies/lending/StethLiquidityVault.sol";

import "src/Kernel.sol";

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
contract StethLiquidityVaultTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address public godmode;

    MockOhm internal ohm;
    MockERC20 internal steth;
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
    StethLiquidityVault internal liquidityVault;

    uint256 internal constant STETH_AMOUNT = 1e18;
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
            // Deploy mock tokens
            ohm = new MockOhm("Olympus", "OHM", 9);
            steth = new MockERC20("Staked ETH", "stETH", 18);
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
            vault = new MockVault(address(liquidityPool), address(ohm), address(steth));
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
        }

        {
            // Deploy roles admin
            rolesAdmin = new RolesAdmin(kernel);

            StethLiquidityVault.OracleFeed memory ohmEthFeedStruct = StethLiquidityVault
                .OracleFeed({feed: ohmEthPriceFeed, updateThreshold: 1 days});
            StethLiquidityVault.OracleFeed memory ethUsdFeedStruct = StethLiquidityVault
                .OracleFeed({feed: ethUsdPriceFeed, updateThreshold: 1 days});
            StethLiquidityVault.OracleFeed memory stethUsdFeedStruct = StethLiquidityVault
                .OracleFeed({feed: stethUsdPriceFeed, updateThreshold: 1 days});

            StethLiquidityVault.AuraPool memory auraPoolStruct = StethLiquidityVault.AuraPool({
                pid: 0,
                booster: IAuraBooster(booster),
                rewardsPool: IAuraRewardPool(auraPool)
            });

            // Deploy stETH Single Sided Liquidity Vault
            liquidityVault = new StethLiquidityVault(
                kernel,
                address(ohm),
                address(steth),
                address(vault),
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

            reward.mint(address(liquidityVault), 1e23);
        }

        {
            /// Initialize timestamps on mock price feeds
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            ethUsdPriceFeed.setTimestamp(block.timestamp);
            stethUsdPriceFeed.setTimestamp(block.timestamp);
        }

        {
            // Mint stETH to alice
            steth.mint(alice, STETH_AMOUNT);

            // Approve vault to spend alice's stETH
            vm.prank(alice);
            steth.approve(address(liquidityVault), STETH_AMOUNT);
        }
    }

    /// [X]  deposit
    ///     [X]  Can be accessed by anyone
    ///     [X]  Fails if pool is imbalanced
    ///     [X]  Cannot be called beyond limit
    ///     [X]  Increases user's stETH deposit
    ///     [X]  Correctly values stETH in terms of OHM
    ///     [X]  Transfers stETH from user
    ///     [X]  Deposits stETH and OHM into Balancer LP
    ///     [X]  Deposits Balancer LP into Aura
    ///     [X]  Updates user's tracked LP position
    ///     [X]  Updates tracked total LP amount

    function testCorrectness_depositCanBeCalledByAnyone(address user_) public {
        vm.assume(user_ != address(0) && user_ != address(liquidityVault));
        steth.mint(user_, 1e18);
        vm.startPrank(user_);
        steth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);
        vm.stopPrank();
    }

    function testCorrectness_depositCannotBeCalledBeyondLimit() public {
        steth.mint(alice, 1e19);

        vm.startPrank(alice);
        steth.approve(address(liquidityVault), 2e19);
        liquidityVault.deposit(1e19, 1e18); // Should mint 1000 OHM which is up to the limit

        bytes memory err = abi.encodeWithSignature("LiquidityVault_LimitViolation()");
        vm.expectRevert(err);

        liquidityVault.deposit(1e18, 1e18); // Should try to push mint beyond limit
        vm.stopPrank();
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

    function testCorrectness_depositIncreasesUserStethDeposit() public {
        vm.prank(alice);
        liquidityVault.deposit(STETH_AMOUNT, 1e18);

        assertEq(liquidityVault.pairTokenDeposits(alice), STETH_AMOUNT);
    }

    function testCorrectness_depositCorrectlyValuesSteth() public {
        vm.prank(alice);
        liquidityVault.deposit(1e18, 1e18);

        assertEq(ohm.balanceOf(address(vault)), 100e9);
    }

    function testCorrectness_depositTransfersStethFromUser() public {
        vm.prank(alice);
        liquidityVault.deposit(STETH_AMOUNT, 1e18);

        assertEq(steth.balanceOf(alice), 0);
    }

    function testCorrectness_depositDepositsStethAndOhmToVault() public {
        vm.prank(alice);
        liquidityVault.deposit(STETH_AMOUNT, 1e18);

        assertEq(steth.balanceOf(address(vault)), STETH_AMOUNT);
        assertEq(ohm.balanceOf(address(vault)), STETH_AMOUNT / 1e7);
    }

    function testCorrectness_depositDepositsBptToAura() public {
        vm.prank(alice);
        liquidityVault.deposit(STETH_AMOUNT, 1e18);

        assertEq(liquidityPool.balanceOf(address(liquidityVault)), 0);
        assertEq(liquidityPool.balanceOf(address(auraPool)), 1e18);
    }

    function testCorrectness_depositUpdatesUserTrackedLpPosition() public {
        vm.prank(alice);
        liquidityVault.deposit(STETH_AMOUNT, 1e18);

        assertTrue(liquidityVault.lpPositions(alice) > 0);
    }

    function testCorrectness_depositUpdatesTrackedTotalLPAmount() public {
        vm.prank(alice);
        liquidityVault.deposit(STETH_AMOUNT, 1e18);

        assertEq(liquidityVault.totalLP(), 1e18);
    }

    /// [X]  withdraw
    ///     [X]  Can be accessed by anyone
    ///     [X]  Fails if pool and oracle prices differ substantially
    ///     [X]  Foregoes rewards if called with claim as false
    ///     [X]  Claims rewards
    ///     [X]  Claims external rewards
    ///     [X]  Returns correct rewards with multiple users
    ///     [X]  Returns correct external rewards with multiple users
    ///     [X]  Fails if user has no LP positions
    ///     [X]  Removes stETH and OHM from Balancer LP
    ///     [X]  Decreases user's stETH deposit value
    ///     [X]  Updates user's reward debts for reward tokens
    ///     [X]  Burns received OHM
    ///     [X]  Transfers stETH to user

    function _withdrawSetUp() internal {
        vm.prank(alice);
        liquidityVault.deposit(STETH_AMOUNT, 1e18);
        vm.warp(block.timestamp + 10); // Increase time 10 seconds so there are rewards
    }

    function testCorrectness_withdrawCanBeCalledByAnyone(address user_) public {
        vm.assume(user_ != address(0) && user_ != address(liquidityVault));
        steth.mint(user_, 1e18);

        // Setup with deposit
        vm.startPrank(user_);
        steth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);

        // Withdraw and claim
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);
        vm.stopPrank();
    }

    function testCorrectness_withdrawFailsIfPricesDiffer() public {
        // Setup
        _withdrawSetUp();

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

    function testCorrectness_withdrawForegoesRewardsIfCalledWithoutClaim() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        assertEq(reward.balanceOf(alice), 0);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, false);

        // Verify end state
        assertEq(reward.balanceOf(alice), 0);
    }

    function testCorrectness_withdrawClaimsRewards() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        assertEq(reward.balanceOf(alice), 0);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(reward.balanceOf(alice), 10e18);
    }

    function testCorrectness_withdrawClaimsExternalRewards() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        assertEq(externalReward.balanceOf(alice), 0);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(externalReward.balanceOf(alice), 1e18);
    }

    function testCorrectness_withdrawReturnsCorrectRewardsMultiUser(address user_) public {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawSetUp();

        // Add second depositor
        vm.startPrank(user_);
        steth.mint(user_, 1e18);
        steth.approve(address(liquidityVault), 1e18);
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

    function testCorrectness_withdrawReturnsCorrectExternalRewardsMultiUser(address user_) public {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawSetUp();

        // Add second depositor
        vm.startPrank(user_);
        steth.mint(user_, 1e18);
        steth.approve(address(liquidityVault), 1e18);
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

    function testCorrectness_withdrawFailsIfUserHasNoLpPosition() public {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Attempt withdrawal
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);
    }

    function testCorrectness_withdrawRemovesStethAndOhmFromVault() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        assertEq(steth.balanceOf(address(vault)), STETH_AMOUNT);
        assertEq(ohm.balanceOf(address(vault)), STETH_AMOUNT / 1e7);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(steth.balanceOf(address(vault)), 0);
        assertEq(ohm.balanceOf(address(vault)), 0);
    }

    function testCorrectness_withdrawDecreasesUserStethDeposit() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        assertEq(liquidityVault.pairTokenDeposits(alice), STETH_AMOUNT);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(liquidityVault.pairTokenDeposits(alice), 0);
    }

    function testCorrectness_withdrawUpdatesRewardDebt() public {
        // Setup
        _withdrawSetUp();

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(liquidityVault.userRewardDebts(alice, address(reward)), 0);
    }

    function testCorrectness_withdrawBurnsOhm() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        assertEq(ohm.balanceOf(address(vault)), STETH_AMOUNT / 1e7);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(ohm.balanceOf(address(liquidityVault)), 0);
    }

    function testCorrectness_withdrawTransfersStethToUser() public {
        // Setup
        _withdrawSetUp();

        // Verify initial state
        assertEq(steth.balanceOf(alice), 0);

        // Withdraw and claim
        vm.prank(alice);
        liquidityVault.withdraw(1e18, minTokenAmounts_, true);

        // Verify end state
        assertEq(steth.balanceOf(alice), 1e18);
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
        _withdrawSetUp();

        // Claim rewards
        vm.prank(alice);
        liquidityVault.claimRewards();
    }

    function testCorrectness_claimRewardsOneTokenOneUser() public {
        // Setup
        _withdrawSetUp();

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
        _withdrawSetUp();

        // Add second depositor
        vm.startPrank(user_);
        steth.mint(user_, 1e18);
        steth.approve(address(liquidityVault), 1e18);
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
        _withdrawSetUp();
        _claimRewardsAddToken();

        // Add second depositor
        vm.startPrank(user_);
        steth.mint(user_, 1e18);
        steth.approve(address(liquidityVault), 1e18);
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

    // ========= VIEW TESTS ========= //

    /// [X]  internalRewardsForToken
    /// [X]  externalRewardsForToken
    /// [X]  getOhmEmissions

    function testCorrectness_internalRewardsForToken(address user_) public {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawSetUp();
        _claimRewardsAddToken();

        // Add second depositor
        vm.startPrank(user_);
        steth.mint(user_, 1e18);
        steth.approve(address(liquidityVault), 1e18);
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
        _withdrawSetUp();

        // Add second depositor
        vm.startPrank(user_);
        steth.mint(user_, 1e18);
        steth.approve(address(liquidityVault), 1e18);
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
        _withdrawSetUp();

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

    function testCorrectness_activateCanOnlyBeCalledByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("liquidityvault_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        liquidityVault.activate();
    }

    function testCorrectness_activateCorrectlyAddsVaultToLQREG() public {
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
        liquidityVault.deactivate(0);
    }

    function testCorrectness_deactivateCorrectlyRemovesVaultFromLQREG() public {
        // Activate vault
        liquidityVault.activate();

        // Verify initial state
        assertEq(lqreg.activeVaultCount(), 1);
        assertEq(lqreg.activeVaults(0), address(liquidityVault));

        // Deactivate vault
        liquidityVault.deactivate(0);

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
            uint256 rewardsPerSecond,
            ,
            uint256 accumulatedRewardsPerShare
        ) = liquidityVault.internalRewardTokens(1);
        assertEq(token, address(reward2));
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
            uint256 rewardsPerSecond,
            ,
            uint256 accumulatedRewardsPerShare
        ) = liquidityVault.internalRewardTokens(1);
        assertEq(token, address(reward2));
        assertEq(rewardsPerSecond, 1e18);
        assertEq(accumulatedRewardsPerShare, 0);

        // Remove reward token
        liquidityVault.removeInternalRewardToken(1, address(reward2));

        // Verify end state
        vm.expectRevert();
        (token, rewardsPerSecond, , accumulatedRewardsPerShare) = liquidityVault
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
        (address token, uint256 accumulatedRewardsPerShare) = liquidityVault.externalRewardTokens(
            1
        );
        assertEq(token, address(externalReward));
        assertEq(accumulatedRewardsPerShare, 0);
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
        (address token, uint256 accumulatedRewardsPerShare) = liquidityVault.externalRewardTokens(
            1
        );
        assertEq(token, address(externalReward));
        assertEq(accumulatedRewardsPerShare, 0);

        // Remove external reward token
        liquidityVault.removeExternalRewardToken(1, address(externalReward));

        // Verify end state
        vm.expectRevert();
        (token, accumulatedRewardsPerShare) = liquidityVault.externalRewardTokens(1);
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
        _withdrawSetUp();

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

    /// [X]  setThreshold
    ///     [X]  Can only be called by admin
    ///     [X]  Sets threshold correctly

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

    /// [X]  setFee
    ///     [X]  Can only be called by admin
    ///     [X]  Sets fee correctly

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
}
