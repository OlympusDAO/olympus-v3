// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test, stdError} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {FullMath} from "libraries/FullMath.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockBalancerPool} from "test/mocks/BalancerMocks.sol";
import {MockAuraBooster, MockAuraRewardPool} from "test/mocks/AuraMocks.sol";
import {JoinPoolRequest, ExitPoolRequest} from "policies/lending/interfaces/IBalancer.sol";

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

// MockVault is modified so that it gives LP tokens in a not constant 1e18 amount but as equal to stETH amount provided
contract MockVault {
    MockERC20 public bpt;
    address public token0;
    address public token1;
    uint256 public token0Amount;
    uint256 public token1Amount;

    constructor(
        address bpt_,
        address token0_,
        address token1_
    ) {
        bpt = MockERC20(bpt_);
        token0 = token0_;
        token1 = token1_;
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest calldata request
    ) external {
        ERC20(request.assets[0]).transferFrom(sender, address(this), request.maxAmountsIn[0]);
        ERC20(request.assets[1]).transferFrom(sender, address(this), request.maxAmountsIn[1]);
        bpt.mint(recipient, request.maxAmountsIn[1]); // THIS LINE IS CHANGED
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest calldata request
    ) external {
        (, uint256 bptAmount) = abi.decode(request.userData, (uint256, uint256));
        bpt.burn(sender, bptAmount);
        ERC20(request.assets[0]).transfer(
            recipient,
            ERC20(request.assets[0]).balanceOf(address(this))
        );
        ERC20(request.assets[1]).transfer(
            recipient,
            ERC20(request.assets[1]).balanceOf(address(this))
        );
    }

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (
            address[] memory,
            uint256[] memory,
            uint256
        )
    {
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        uint256[] memory balances = new uint256[](2);
        balances[0] = token0Amount;
        balances[1] = token1Amount;

        return (tokens, balances, block.timestamp);
    }

    function setPoolAmounts(uint256 token0Amount_, uint256 token1Amount_) external {
        token0Amount = token0Amount_;
        token1Amount = token1Amount_;
    }
}

// solhint-disable-next-line max-states-count
contract KebabsecTest is Test {
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
    uint256[] internal kebabAmounts_ = [1, 1];

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
            liquidityVault.setLimit(100000e9); // 1000 OHM

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
            steth.mint(alice, STETH_AMOUNT * 100);

            // Approve vault to spend alice's stETH
            vm.prank(alice);
            steth.approve(address(liquidityVault), STETH_AMOUNT * 100);
        }
    }

    function _withdrawSetUpKebab() internal {
        vm.prank(alice);
        liquidityVault.deposit(STETH_AMOUNT * 100, 100e18);
        vm.warp(block.timestamp + 10); // Increase time 10 seconds so there are rewards
    }

    function testCorrectness_kebabsecInfiniteRewards(address user_) public {
        vm.assume(user_ != address(0) && user_ != alice && user_ != address(liquidityVault));

        // Setup
        _withdrawSetUpKebab();

        // Add second depositor
        vm.startPrank(user_);
        steth.mint(user_, 1e18);
        steth.approve(address(liquidityVault), 1e18);
        liquidityVault.deposit(1e18, 1e18);
        liquidityVault.withdraw(1, kebabAmounts_, false);
        vm.stopPrank();

        console.log(liquidityVault.internalRewardsForToken(0, user_));

        assertEq(liquidityVault.internalRewardsForToken(0, user_), type(uint256).max);
    }
}
