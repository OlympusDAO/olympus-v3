// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {RolesAdmin} from "policies/RolesAdmin.sol";

import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";

import {FullMath} from "libraries/FullMath.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {BunniManager} from "policies/UniswapV3/BunniManager.sol";
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";

import "src/Kernel.sol";

contract BunniManagerTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal policy;

    MockERC20 internal ohm;
    MockERC20 internal usdc;

    Kernel internal kernel;
    OlympusRoles internal roles;
    OlympusTreasury internal treasury;
    OlympusMinter internal mintr;
    OlympusPricev2 internal price;

    UniswapV3Factory internal uniswapFactory;

    RolesAdmin internal rolesAdmin;

    BunniManager internal bunniManager;
    BunniHub internal bunniHub;
    IUniswapV3Pool internal pool;

    uint24 constant POOL_FEE = 500;
    uint160 constant OHM_USDC_SQRTPRICEX96 = 8529245188595251053303005012; // From OHM-USDC
    uint160 constant DAI_USDC_SQRTPRICEX96 = 79227120762198600072084; // From DAI-USDC, = $1

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            address[] memory users = userCreator.create(2);
            alice = users[0];
            policy = users[1];
        }

        {
            ohm = new MockERC20("Olympus", "OHM", 9);
            usdc = new MockERC20("USDC", "USDC", 6);
        }

        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy modules
            roles = new OlympusRoles(kernel);
            treasury = new OlympusTreasury(kernel);
            mintr = new OlympusMinter(kernel, address(ohm));
            price = new OlympusPricev2(kernel, uint8(8), uint32(8 hours));
        }

        {
            // Deploy BunniManager policy
            bunniManager = new BunniManager(kernel);

            // Deploy Uniswap V3 factory
            uniswapFactory = new UniswapV3Factory();

            // Deploy BunniHub
            bunniHub = new BunniHub(
                uniswapFactory,
                address(bunniManager),
                0 // No protocol fee
            );

            rolesAdmin = new RolesAdmin(kernel);
        }

        {
            // Initialize system and kernel

            // Install modules
            kernel.executeAction(Actions.InstallModule, address(roles));
            kernel.executeAction(Actions.InstallModule, address(treasury));
            kernel.executeAction(Actions.InstallModule, address(mintr));
            kernel.executeAction(Actions.InstallModule, address(price));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(bunniManager));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }

        {
            // Configure access control

            // BunniManager roles
            rolesAdmin.grantRole("bunni_admin", policy);
        }

        {
            // Create a Uniswap V3 pool
            pool = IUniswapV3Pool(uniswapFactory.createPool(address(ohm), address(usdc), POOL_FEE));

            // Initialize it
            pool.initialize(DAI_USDC_SQRTPRICEX96);
        }

        {
            vm.prank(policy);
            // Set the BunniHub on the manager policy
            bunniManager.setBunniHub(address(bunniHub));
        }
    }

    function _expectRevert_unauthorized() internal {
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bunni_admin")
        );
        vm.expectRevert(err);
    }

    function _expectRevert_bunniHubNotSet() internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_HubNotSet.selector
        );
        vm.expectRevert(err);
    }

    function _expectRevert_poolNotFound(address pool_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_PoolNotFound.selector,
            pool_
        );
        vm.expectRevert(err);
    }

    function _expectRevert_insufficientBalance(address token_, uint256 requiredBalance_, uint256 actualBalance_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_InsufficientBalance.selector,
            token_,
            requiredBalance_,
            actualBalance_
        );
        vm.expectRevert(err);
    }

    function _setUpNewBunniManager() internal returns (BunniManager) {
        // Create a new BunniManager policy, with the BunniHub set
        BunniManager newBunniManager = new BunniManager(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(newBunniManager));

        return newBunniManager;
    }

    // [ ] constructor
    // [ ] configureDependencies
    //  [ ] reverts if TRSRY version is unsupported
    //  [ ] configures correctly
    // [ ] requestPermissions
    // [X] deployToken
    //  [X] caller is unauthorized
    //  [X] bunniHub not set
    //  [X] token already deployed
    //  [X] not a Uniswap V3 pool
    //  [X] deploys and returns token, registers with PRICEv2

    function test_deployToken_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.deployToken(address(pool));
    }

    function test_deployToken_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.deployToken(address(pool));
    }

    function test_deployToken_invalidPoolReverts() public {
        _expectRevert_poolNotFound(address(ohm));

        vm.prank(policy);
        bunniManager.deployToken(address(ohm));
    }

    function test_deployToken() public {
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployToken(address(pool));

        // Check details of token
        assertEq(address(deployedToken.pool()), address(pool));
        assertEq(deployedToken.tickLower(), TickMath.MIN_TICK);
        assertEq(deployedToken.tickUpper(), TickMath.MAX_TICK);

        // Check that the token has been added to PRICEv2
        PRICEv2.Asset memory priceAsset = price.getAssetData(address(deployedToken));
        assertTrue(priceAsset.approved);
        // TODO check that the submodule is configured for use
    }

    function test_deployToken_duplicateReverts() public {
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployToken(address(pool));

        // Deploy a second time
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_TokenDeployed.selector,
            address(pool),
            address(deployedToken)
        );
        vm.expectRevert(err);

        vm.prank(policy);
        bunniManager.deployToken(address(pool));
    }

    // [ ] deposit
    //  [X] caller is unauthorized
    //  [X] bunniHub not set
    //  [X] token not deployed
    //  [X] insufficient balance of token0 in TRSRY to deposit
    //  [X] insufficient balance of token1 in TRSRY to deposit
    //  [X] OHM minted, deposits and returns shares
    //  [ ] burns excess OHM after deposit
    //  [ ] deposits non-OHM tokens and returns shares
    //  [ ] returns non-OHM tokens to TRSRY

    function test_deposit_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.deposit(address(pool), 1e9, 1e18);
    }

    function test_deposit_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.deposit(address(pool), 1e9, 1e18);
    }

    function test_deposit_tokenNotDeployedReverts() public {
        _expectRevert_poolNotFound(address(pool));

        vm.prank(policy);
        bunniManager.deposit(address(pool), 1e9, 1e18);
    }

    function test_deposit_token0InsufficientBalanceReverts(uint256 token0Amount_) public {
        // Create a pool with non-OHM tokens
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        IUniswapV3Pool newPool = IUniswapV3Pool(uniswapFactory.createPool(address(usdc), address(dai), POOL_FEE));
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Determine balances
        address token0 = newPool.token0();
        bool token0IsDai = token0 == address(dai);
        uint256 TOKEN0_DEPOSIT = token0IsDai ? 1e18 : 1e6;
        uint256 TOKEN1_DEPOSIT = token0IsDai ? 1e6 : 1e18;
        uint256 daiBalance = token0IsDai ? bound(token0Amount_, 0, TOKEN0_DEPOSIT - 1) : 1e18;
        uint256 usdcBalance = token0IsDai ? 1e6 : bound(token0Amount_, 0, TOKEN0_DEPOSIT - 1);

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployToken(address(newPool));

        // Mint tokens to the TRSRY
        dai.mint(address(treasury), daiBalance);
        usdc.mint(address(treasury), usdcBalance);

        // Expect a revert
        _expectRevert_insufficientBalance(token0, TOKEN0_DEPOSIT, token0IsDai ? daiBalance : usdcBalance);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(address(newPool), TOKEN0_DEPOSIT, TOKEN1_DEPOSIT);
    }

    function test_deposit_token1InsufficientBalanceReverts(uint256 token1Amount_) public {
        // Create a pool with non-OHM tokens
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        IUniswapV3Pool newPool = IUniswapV3Pool(uniswapFactory.createPool(address(usdc), address(dai), POOL_FEE));
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Determine balances
        address token0 = newPool.token0();
        bool token0IsDai = token0 == address(dai);
        uint256 TOKEN0_DEPOSIT = token0IsDai ? 1e18 : 1e6;
        uint256 TOKEN1_DEPOSIT = token0IsDai ? 1e6 : 1e18;
        uint256 daiBalance = token0IsDai ? 1e18 : bound(token1Amount_, 0, TOKEN1_DEPOSIT - 1);
        uint256 usdcBalance = token0IsDai ? bound(token1Amount_, 0, TOKEN1_DEPOSIT - 1) : 1e6;

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployToken(address(newPool));

        // Mint tokens to the TRSRY
        dai.mint(address(treasury), daiBalance);
        usdc.mint(address(treasury), usdcBalance);

        // Expect a revert
        _expectRevert_insufficientBalance(newPool.token1(), TOKEN1_DEPOSIT, token0IsDai ? usdcBalance : daiBalance);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(address(newPool), TOKEN0_DEPOSIT, TOKEN1_DEPOSIT);
    }

    function test_deposit_nonOhmTokens() public {
        // Create a pool with non-OHM tokens
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        IUniswapV3Pool newPool = IUniswapV3Pool(uniswapFactory.createPool(address(usdc), address(dai), POOL_FEE));
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Determine balances
        address token0 = newPool.token0();
        bool token0IsDai = token0 == address(dai);
        uint256 TOKEN0_DEPOSIT = token0IsDai ? 1e18 : 1e6;
        uint256 TOKEN1_DEPOSIT = token0IsDai ? 1e6 : 1e18;

        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployToken(address(newPool));

        // Mint tokens to the TRSRY
        dai.mint(address(treasury), token0IsDai ? TOKEN0_DEPOSIT : TOKEN1_DEPOSIT);
        usdc.mint(address(treasury), token0IsDai ? TOKEN1_DEPOSIT : TOKEN0_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(address(newPool), TOKEN0_DEPOSIT, TOKEN1_DEPOSIT);

        // The tokens should have been deposited into TRSRY
        assertEq(bunniToken.balanceOf(address(treasury)), bunniTokenShares);
    }

    function test_deposit_ohmToken() public {
        uint256 OTHER_DEPOSIT = 1e18;
        uint256 OHM_DEPOSIT = 1e9;

        // Determine which token is token0
        address token0 = pool.token0();
        uint256 token0Amount = token0 == address(ohm) ? OHM_DEPOSIT : OTHER_DEPOSIT;
        uint256 token1Amount = token0 == address(ohm) ? OTHER_DEPOSIT : OHM_DEPOSIT;

        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(address(treasury), OTHER_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(address(pool), token0Amount, token1Amount);

        // The tokens should have been deposited into TRSRY
        assertEq(bunniToken.balanceOf(address(treasury)), bunniTokenShares);
    }

    // [ ] withdraw
    //  [ ] caller is unauthorized
    //  [ ] bunniHub not set
    //  [ ] token not deployed
    //  [ ] withdraws and returns non-OHM tokens to TRSRY
    //  [ ] withdraws, burns OHM and returns non-OHM tokens to TRSRY
    // [ ] getToken
    //  [ ] bunniHub is not set
    //  [ ] token is not deployed
    //  [ ] returns token struct
    // [ ] getTRSRYBalance
    //  [ ] bunniHub is not set
    //  [ ] token is not deployed
    //  [ ] returns token balance
    // [ ] setBunniHub
    //  [ ] caller is unauthorized
    //  [ ] zero address
    //  [ ] sets bunniHub variable
    // [ ] setBunniOwner
    //  [ ] caller is unauthorized
    //  [ ] bunniHub is not set
    //  [ ] zero address
    //  [ ] sets owner of bunniHub
}