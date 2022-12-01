// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

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
import {SSLiquidityVault} from "policies/SSLiquidityVault.sol";

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
contract SSLiquidityVaultTest is Test {
    using ModuleTestFixtureGenerator for OlympusLender;
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address public godmode;

    MockOhm internal ohm;
    MockERC20 internal steth;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;
    MockPriceFeed internal stethUsdPriceFeed;

    MockVault internal vault;
    MockBalancerPool internal stethOhmPool;

    Kernel internal kernel;
    OlympusMinter internal minter;
    OlympusRoles internal roles;
    OlympusLender internal lender;

    RolesAdmin internal rolesAdmin;
    SSLiquidityVault internal sslv;

    uint256 internal STETH_AMOUNT = 1_000_000_000_000_000_000;

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
            // Deploy mock balancer contracts
            stethOhmPool = new MockBalancerPool();
            vault = new MockVault(address(stethOhmPool));
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

            // Deploy stETH Single Sided liquidity vault
            sslv = new SSLiquidityVault(
                kernel,
                address(ohm),
                address(steth),
                address(vault),
                address(stethOhmPool),
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
            kernel.executeAction(Actions.ActivatePolicy, address(sslv));
            kernel.executeAction(Actions.ActivatePolicy, godmode);
        }

        {
            // Set LENDR limits
            vm.startPrank(godmode);
            lender.setApproval(address(sslv), true);
            lender.setGlobalLimit(10000e18);
            lender.setMarketLimit(address(sslv), 10000e18);
            vm.stopPrank();
        }

        {
            // Set MINTR approval
            vm.prank(address(sslv));
            minter.increaseMintApproval(address(sslv), 10000e18);
        }

        {
            // Mint stETH to alice
            steth.mint(alice, STETH_AMOUNT);

            // Approve Single Sided Liquidity Vault to spend alice's stETH
            vm.prank(alice);
            steth.approve(address(sslv), STETH_AMOUNT);
        }
    }

    /// [X]  depositAndLP
    ///     [X]  Can be accessed by anyone
    ///     [X]  Increases user's stETH deposit
    ///     [X]  Increases user's OHM debt
    ///     [X]  Increases SSLV's debt in LENDR module
    ///     [X]  Values stETH correctly
    ///     [X]  Takes stETH from user
    ///     [X]  Deposits stETH and OHM into Balancer LP
    ///     [X]  Increases user's tracked LP position

    function testCorrectness_anyoneCanDepositAndLP(address user_) public {
        vm.assume(user_ != address(0));
        steth.mint(user_, 1e18);
        vm.startPrank(user_);
        steth.approve(address(sslv), 1e18);
        sslv.depositAndLP(1e18);
        vm.stopPrank();
    }

    function testCorrectness_depositAndLPIncreasesUserStETHDeposit() public {
        vm.prank(alice);
        sslv.depositAndLP(STETH_AMOUNT);

        assertEq(sslv.stethDeposits(alice), STETH_AMOUNT);
    }

    function testCorrectness_depositAndLPIncreasesUserOhmDebt() public {
        vm.prank(alice);
        sslv.depositAndLP(STETH_AMOUNT);

        assertEq(sslv.ohmDebtOutstanding(alice), STETH_AMOUNT / 1e11);
    }

    function testCorrectness_depositAndLPIncreasesContractDebt() public {
        vm.prank(alice);
        sslv.depositAndLP(STETH_AMOUNT);

        assertEq(lender.marketDebtOutstanding(address(sslv)), STETH_AMOUNT / 1e11);
    }

    function testCorrectness_depositAndLPValuesStETHCorrectly() public {
        vm.prank(alice);
        sslv.depositAndLP(1e11);

        assertEq(sslv.ohmDebtOutstanding(alice), 1);
        assertEq(ohm.balanceOf(address(vault)), 1);
    }

    function testCorrectness_depositAndLPTakesStETHFromUser() public {
        vm.prank(alice);
        sslv.depositAndLP(STETH_AMOUNT);

        assertEq(steth.balanceOf(alice), 0);
    }

    function testCorrectness_depositAndLPDepositsStETHAndOhmToVault() public {
        vm.prank(alice);
        sslv.depositAndLP(STETH_AMOUNT);

        assertEq(steth.balanceOf(address(vault)), STETH_AMOUNT);
        assertEq(ohm.balanceOf(address(vault)), sslv.ohmDebtOutstanding(alice));
    }

    function testCorrectness_depositAndLPIncreasesUserLPPosition() public {
        vm.prank(alice);
        sslv.depositAndLP(STETH_AMOUNT);

        assertTrue(sslv.lpPositions(alice) > 0);
    }

    /// [X]  unwindAndRepay
    ///     [X]  Can be accessed by anyone
    ///     [X]  Decreases user's tracked LP position
    ///     [X]  Removes stETH and OHM from Balancer LP
    ///     [X]  Decreases user's OHM debt
    ///     [X]  Decreases users's stETH deposit
    ///     [X]  Decreases SSLV's debt in LENDR module
    ///     [X]  Burns received OHM
    ///     [X]  Returns stETH to user

    function _setupUnwindAndRepay() internal returns (uint256) {
        vm.prank(alice);
        uint256 lpAmount = sslv.depositAndLP(1e18);
        return lpAmount;
    }

    function testCorrectness_anyoneCanUnwindAndRepay(address user_) public {
        vm.assume(user_ != address(0));

        // Setup
        steth.mint(user_, STETH_AMOUNT);
        vm.startPrank(user_);
        steth.approve(address(sslv), STETH_AMOUNT);
        uint256 lpAmount = sslv.depositAndLP(STETH_AMOUNT);

        // Withdraw and unwind
        sslv.unwindAndRepay(lpAmount, 1e7, 1e18);
        vm.stopPrank();
    }

    function testCorrectness_unwindAndRepayDecreasesLpPosition() public {
        uint256 lpAmount = _setupUnwindAndRepay();

        // Verify initial state
        assertEq(sslv.lpPositions(alice), lpAmount);

        vm.startPrank(alice);
        vault.bpt().approve(address(sslv), lpAmount);
        sslv.unwindAndRepay(lpAmount, 1e7, 1e18);

        // Verify final state
        assertEq(sslv.lpPositions(alice), 0);
    }

    function testCorrectness_unwindAndRepayRemovesOhmAndStethFromBalancer() public {
        uint256 lpAmount = _setupUnwindAndRepay();

        // Verify initial state
        assertEq(steth.balanceOf(address(vault)), 1e18);
        assertEq(ohm.balanceOf(address(vault)), 1e7);

        vm.startPrank(alice);
        vault.bpt().approve(address(sslv), lpAmount);
        sslv.unwindAndRepay(lpAmount, 1e7, 1e18);

        // Verify final state
        assertEq(steth.balanceOf(address(vault)), 0);
        assertEq(ohm.balanceOf(address(vault)), 0);
    }

    function testCorrectness_unwindAndRepayDecreasesOhmDebt() public {
        uint256 lpAmount = _setupUnwindAndRepay();

        // Verify initial state
        assertEq(sslv.ohmDebtOutstanding(alice), 1e7);

        vm.startPrank(alice);
        vault.bpt().approve(address(sslv), lpAmount);
        sslv.unwindAndRepay(lpAmount, 1e7, 1e18);

        // Verify final state
        assertEq(sslv.ohmDebtOutstanding(alice), 0);
    }

    function testCorrectness_unwindAndRepayDecreasesStethDeposit() public {
        uint256 lpAmount = _setupUnwindAndRepay();

        // Verify initial state
        assertEq(sslv.stethDeposits(alice), 1e18);

        vm.startPrank(alice);
        vault.bpt().approve(address(sslv), lpAmount);
        sslv.unwindAndRepay(lpAmount, 1e7, 1e18);

        // Verify final state
        assertEq(sslv.stethDeposits(alice), 0);
    }

    function testCorrectness_unwindAndRepayDecreasesLenderDebt() public {
        uint256 lpAmount = _setupUnwindAndRepay();

        // Verify initial state
        assertEq(lender.marketDebtOutstanding(address(sslv)), 1e7);

        vm.startPrank(alice);
        vault.bpt().approve(address(sslv), lpAmount);
        sslv.unwindAndRepay(lpAmount, 1e7, 1e18);

        // Verify final state
        assertEq(lender.marketDebtOutstanding(address(sslv)), 0);
    }

    function testCorrectness_unwindAndRepayBurnsOhm() public {
        uint256 lpAmount = _setupUnwindAndRepay();

        vm.startPrank(alice);
        vault.bpt().approve(address(sslv), lpAmount);
        sslv.unwindAndRepay(lpAmount, 1e7, 1e18);

        // Verify final state
        assertEq(ohm.balanceOf(address(sslv)), 0);
    }

    function testCorrectness_unwindAndRepayReturnsStethToUser() public {
        uint256 lpAmount = _setupUnwindAndRepay();

        vm.startPrank(alice);
        vault.bpt().approve(address(sslv), lpAmount);
        sslv.unwindAndRepay(lpAmount, 1e7, 1e18);

        // Verify final state
        assertEq(steth.balanceOf(alice), 1e18);
    }
}
