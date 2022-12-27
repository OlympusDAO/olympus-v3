// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {FullMath} from "libraries/FullMath.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockVault} from "test/mocks/MockVault.sol";
import {MockBalancerPool} from "test/mocks/MockBalancerPool.sol";

import {OlympusMinter, OHM} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {OlympusLender} from "modules/LENDR/OlympusLender.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {StethLiquidityAMO} from "policies/lending/StethLiquidityAMO.sol";

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
contract StethLiquidityAMOTest is Test {
    using ModuleTestFixtureGenerator for OlympusLender;
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address public godmode;

    MockOhm internal ohm;
    MockERC20 internal steth;
    MockERC20 internal reward;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;
    MockPriceFeed internal stethUsdPriceFeed;

    MockVault internal vault;
    MockBalancerPool internal liquidityPool;

    Kernel internal kernel;
    OlympusMinter internal minter;
    OlympusRoles internal roles;
    OlympusLender internal lender;

    RolesAdmin internal rolesAdmin;
    StethLiquidityAMO internal liquidityAMO;

    uint256 internal constant STETH_AMOUNT = 1e18;

    function setUp() public {
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
        }

        {
            // Deploy mock price feeds
            ohmEthPriceFeed = new MockPriceFeed();
            ethUsdPriceFeed = new MockPriceFeed();
            stethUsdPriceFeed = new MockPriceFeed();

            ohmEthPriceFeed.setDecimals(18);
            ethUsdPriceFeed.setDecimals(18);
            stethUsdPriceFeed.setDecimals(18);

            ohmEthPriceFeed.setLatestAnswer(1e16); // 0.01 ETH
            ethUsdPriceFeed.setLatestAnswer(1e21); // 1000 USD
            stethUsdPriceFeed.setLatestAnswer(1e21); // 1000 USD
        }

        {
            // Deploy mock Balancer contracts
            liquidityPool = new MockBalancerPool();
            vault = new MockVault(address(liquidityPool));
        }

        {
            // Deploy kernel
            kernel = new Kernel();

            // Deploy modules
            minter = new OlympusMinter(kernel, address(ohm));
            roles = new OlympusRoles(kernel);
            lender = new OlympusLender(kernel);
        }

        {
            // Generate fixtures
            godmode = lender.generateGodmodeFixture(type(OlympusLender).name);
        }

        {
            // Deploy roles admin
            rolesAdmin = new RolesAdmin(kernel);

            // Deploy stETH Single Sided Liquidity Vault
            liquidityAMO = new StethLiquidityAMO(
                kernel,
                address(ohm),
                address(steth),
                address(vault),
                address(liquidityPool),
                address(ohmEthPriceFeed),
                address(ethUsdPriceFeed),
                address(stethUsdPriceFeed)
            );
        }

        {
            // Initialize system and kernel

            // Initialize modules
            kernel.executeAction(Actions.InstallModule, address(minter));
            kernel.executeAction(Actions.InstallModule, address(roles));
            kernel.executeAction(Actions.InstallModule, address(lender));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ActivatePolicy, address(liquidityAMO));
            kernel.executeAction(Actions.ActivatePolicy, godmode);
        }

        {
            // Set LENDR limits
            vm.startPrank(godmode);
            lender.setApproval(address(liquidityAMO), true);
            lender.setGlobalLimit(1e22);
            lender.setMarketLimit(address(liquidityAMO), 1e22);
            vm.stopPrank();
        }

        {
            // Mint stETH to alice
            steth.mint(alice, STETH_AMOUNT);

            // Approve AMO to spend alice's stETH
            vm.prank(alice);
            steth.approve(address(liquidityAMO), STETH_AMOUNT);
        }
    }

    /// [X]  deposit
    ///     [X]  Can be accessed by anyone
    ///     [X]  Increases user's stETH deposit
    ///     [X]  Correctly values stETH in terms of OHM
    ///     [X]  Increases AMO's debt in LENDR module
    ///     [X]  Transfers stETH from user
    ///     [X]  Deposits stETH and OHM into Balancer LP
    ///     [X]  Updates user's tracked LP position

    function testCorrectness_depositCanBeCalledByAnyone(address user_) public {
        vm.assume(user_ != address(0));
        steth.mint(user_, 1e18);
        vm.startPrank(user_);
        steth.approve(address(liquidityAMO), 1e18);
        liquidityAMO.deposit(1e18);
        vm.stopPrank();
    }

    function testCorrectness_depositIncreasesUserStethDeposit() public {
        vm.prank(alice);
        liquidityAMO.deposit(STETH_AMOUNT);

        assertEq(liquidityAMO.pairTokenDeposits(alice), STETH_AMOUNT);
    }

    function testCorrectness_depositCorrectlyValuesSteth() public {
        vm.prank(alice);
        liquidityAMO.deposit(1e11);

        assertEq(ohm.balanceOf(address(vault)), 1);
    }

    function testCorrectness_depositIncreasesAmoDebtInLendr() public {
        vm.prank(alice);
        liquidityAMO.deposit(STETH_AMOUNT);

        assertEq(lender.marketDebtOutstanding(address(liquidityAMO)), STETH_AMOUNT / 1e11);
    }

    function testCorrectness_depositTransfersStethFromUser() public {
        vm.prank(alice);
        liquidityAMO.deposit(STETH_AMOUNT);

        assertEq(steth.balanceOf(alice), 0);
    }

    function testCorrectness_depositDepositsStethAndOhmToVault() public {
        vm.prank(alice);
        liquidityAMO.deposit(STETH_AMOUNT);

        assertEq(steth.balanceOf(address(vault)), STETH_AMOUNT);
        assertEq(ohm.balanceOf(address(vault)), STETH_AMOUNT / 1e11);
    }

    function testCorrectness_depositUpdatesUserTrackedLpPosition() public {
        vm.prank(alice);
        liquidityAMO.deposit(STETH_AMOUNT);

        assertTrue(liquidityAMO.lpPositions(alice) > 0);
    }
}
