// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

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
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";

import "src/Kernel.sol";

contract BunniManagerTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal policy;

    MockOhm internal ohm;
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
    uint256 constant OHM_USDC_PRICE = 115897 * 1e14; // 11.5897 USDC per OHM in 18 decimal places
    uint160 constant OHM_USDC_SQRTPRICEX96 = 8529245188595251053303005012; // From OHM-USDC, 1 OHM = 11.5897 USDC
    uint160 constant DAI_USDC_SQRTPRICEX96 = 79227120762198600072084; // From DAI-USDC, 1 DAI = 1 USDC

    int24 constant TICK = 887250; // (887272/50)*50

    uint8 constant BUNNI_TOKEN_DECIMALS = 18;

    uint256 constant SLIPPAGE_DEFAULT = 100; // 1%
    uint256 constant SLIPPAGE_MAX = 10000; // 100%

    uint8 constant PRICE_VERSION = 2;
    uint8 constant TRSRY_VERSION = 1;
    uint8 constant ROLES_VERSION = 1;
    uint8 constant MINTR_VERSION = 1;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            address[] memory users = userCreator.create(2);
            alice = users[0];
            policy = users[1];
        }

        {
            ohm = new MockOhm("Olympus", "OHM", 9);
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
            pool.initialize(OHM_USDC_SQRTPRICEX96);
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

    function _expectRevert_invalidAddress(address address_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_Params_InvalidAddress.selector,
            address_
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

    function _expectRevert_invalidSlippage(uint256 slippage_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_Params_InvalidSlippage.selector,
            slippage_,
            SLIPPAGE_MAX
        );
        vm.expectRevert(err);
    }

    function _expectRevert_wrongModuleVersion() internal {
        uint8[4] memory expectedVersions = [1, 1, 2, 1];

        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_WrongModuleVersion.selector, expectedVersions);
        vm.expectRevert(err);
    }

    function _expectRevert_inactive() internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_Inactive.selector
        );
        vm.expectRevert(err);
    }

    function _setUpNewBunniManager() internal returns (BunniManager) {
        // Create a new BunniManager policy, with the BunniHub set
        BunniManager newBunniManager = new BunniManager(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(newBunniManager));

        return newBunniManager;
    }

    function _getBunniKey(IUniswapV3Pool pool_, IBunniToken token_) internal view returns (BunniKey memory) {
        return BunniKey({
            pool: pool_,
            tickLower: token_.tickLower(),
            tickUpper: token_.tickUpper()
        });
    }

    // [X] constructor (tested in setUp)
    // [X] configureDependencies
    //  [X] reverts if TRSRY version is unsupported
    //  [X] configures correctly

    function test_configureDependencies() public {
        Keycode[] memory expectedDependencies = new Keycode[](4);
        expectedDependencies[0] = toKeycode("ROLES");
        expectedDependencies[1] = toKeycode("TRSRY");
        expectedDependencies[2] = toKeycode("PRICE");
        expectedDependencies[3] = toKeycode("MINTR");

        Keycode[] memory deps = bunniManager.configureDependencies();
        assertEq(deps.length, expectedDependencies.length);
        for (uint256 i = 0; i < deps.length; i++) {
            assertEq(fromKeycode(deps[i]), fromKeycode(expectedDependencies[i]));
        }
    }

    function test_configureDependencies_priceVersionReverts(uint8 version_) public {
        vm.assume(version_ != PRICE_VERSION);

        Keycode[] memory expectedDependencies = new Keycode[](4);
        expectedDependencies[0] = toKeycode("ROLES");
        expectedDependencies[1] = toKeycode("TRSRY");
        expectedDependencies[2] = toKeycode("PRICE");
        expectedDependencies[3] = toKeycode("MINTR");

        // Mock an incompatibility with the module
        vm.mockCall(
            address(price), 
            abi.encodeWithSelector(OlympusPricev2.VERSION.selector), 
            abi.encode(version_, 0)
        );
        _expectRevert_wrongModuleVersion();

        bunniManager.configureDependencies();
    }

    function test_configureDependencies_treasuryVersionReverts(uint8 version_) public {
        vm.assume(version_ != TRSRY_VERSION);

        Keycode[] memory expectedDependencies = new Keycode[](4);
        expectedDependencies[0] = toKeycode("ROLES");
        expectedDependencies[1] = toKeycode("TRSRY");
        expectedDependencies[2] = toKeycode("PRICE");
        expectedDependencies[3] = toKeycode("MINTR");

        // Mock an incompatibility with the module
        vm.mockCall(
            address(treasury), 
            abi.encodeWithSelector(OlympusTreasury.VERSION.selector), 
            abi.encode(version_, 0)
        );
        _expectRevert_wrongModuleVersion();

        bunniManager.configureDependencies();
    }

    function test_configureDependencies_rolesVersionReverts(uint8 version_) public {
        vm.assume(version_ != ROLES_VERSION);

        Keycode[] memory expectedDependencies = new Keycode[](4);
        expectedDependencies[0] = toKeycode("ROLES");
        expectedDependencies[1] = toKeycode("TRSRY");
        expectedDependencies[2] = toKeycode("PRICE");
        expectedDependencies[3] = toKeycode("MINTR");

        // Mock an incompatibility with the module
        vm.mockCall(
            address(roles), 
            abi.encodeWithSelector(OlympusRoles.VERSION.selector), 
            abi.encode(version_, 0)
        );
        _expectRevert_wrongModuleVersion();

        bunniManager.configureDependencies();
    }

    function test_configureDependencies_mintrVersionReverts(uint8 version_) public {
        vm.assume(version_ != MINTR_VERSION);

        Keycode[] memory expectedDependencies = new Keycode[](4);
        expectedDependencies[0] = toKeycode("ROLES");
        expectedDependencies[1] = toKeycode("TRSRY");
        expectedDependencies[2] = toKeycode("PRICE");
        expectedDependencies[3] = toKeycode("MINTR");

        // Mock an incompatibility with the module
        vm.mockCall(
            address(mintr), 
            abi.encodeWithSelector(OlympusMinter.VERSION.selector), 
            abi.encode(version_, 0)
        );
        _expectRevert_wrongModuleVersion();

        bunniManager.configureDependencies();
    }

    // [X] requestPermissions

    function test_requestPermissions() public {
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        Keycode PRICE_KEYCODE = toKeycode("PRICE");
        Keycode MINTR_KEYCODE = toKeycode("MINTR");

        Permissions[] memory expectedPermissions = new Permissions[](8);
        expectedPermissions[0] = Permissions(TRSRY_KEYCODE, treasury.withdrawReserves.selector);
        expectedPermissions[1] = Permissions(TRSRY_KEYCODE, treasury.increaseWithdrawApproval.selector);
        expectedPermissions[2] = Permissions(TRSRY_KEYCODE, treasury.decreaseWithdrawApproval.selector);
        expectedPermissions[3] = Permissions(PRICE_KEYCODE, price.addAsset.selector);
        expectedPermissions[4] = Permissions(MINTR_KEYCODE, mintr.mintOhm.selector);
        expectedPermissions[5] = Permissions(MINTR_KEYCODE, mintr.burnOhm.selector);
        expectedPermissions[6] = Permissions(MINTR_KEYCODE, mintr.increaseMintApproval.selector);
        expectedPermissions[7] = Permissions(MINTR_KEYCODE, mintr.decreaseMintApproval.selector);

        Permissions[] memory perms = bunniManager.requestPermissions();
        assertEq(perms.length, expectedPermissions.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPermissions[i].keycode));
            assertEq(perms[i].funcSelector, expectedPermissions[i].funcSelector);
        }
    }

    // [X] deployToken
    //  [X] caller is unauthorized
    //  [X] bunniHub not set
    //  [X] token already deployed
    //  [X] not a Uniswap V3 pool
    //  [X] deploys and returns token, registers with PRICEv2
    //  [X] reverts when inactive

    function test_deployToken_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.deployToken(address(pool));
    }

    function test_deployToken_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = new BunniManager(kernel);

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.deployToken(address(pool));
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
        assertEq(deployedToken.tickLower(), -1 * 887250);
        assertEq(deployedToken.tickUpper(), 887250);

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

    // [X] deposit
    //  [X] caller is unauthorized
    //  [X] bunniHub not set
    //  [X] token not deployed
    //  [X] insufficient balance of token0 in TRSRY to deposit
    //  [X] insufficient balance of token1 in TRSRY to deposit
    //  [X] OHM minted, deposits and returns shares
    //  [X] burns excess OHM after deposit
    //  [X] deposits non-OHM tokens and returns shares
    //  [X] returns non-OHM tokens to TRSRY
    //  [X] reverts when inactive

    function test_deposit_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.deposit(address(pool), address(ohm), 1e9, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_deposit_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = new BunniManager(kernel);

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.deposit(address(pool), address(ohm), 1e9, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_deposit_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.deposit(address(pool), address(ohm), 1e9, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_deposit_tokenNotDeployedReverts() public {
        _expectRevert_poolNotFound(address(pool));

        vm.prank(policy);
        bunniManager.deposit(address(pool), address(ohm), 1e9, 1e18, SLIPPAGE_DEFAULT);
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
        uint256 daiBalance = token0IsDai ? bound(token0Amount_, 0, 1e18 - 1) : 1e18;
        uint256 usdcBalance = token0IsDai ? 1e6 : bound(token0Amount_, 0, 1e6 - 1);

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
        bunniManager.deposit(address(newPool), address(dai), 1e18, 1e6, SLIPPAGE_DEFAULT);
    }

    function test_deposit_token1InsufficientBalanceReverts(uint256 token1Amount_) public {
        // Create a pool with non-OHM tokens
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        IUniswapV3Pool newPool = IUniswapV3Pool(uniswapFactory.createPool(address(usdc), address(dai), POOL_FEE));
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Determine balances
        address token0 = newPool.token0();
        bool token0IsDai = token0 == address(dai);
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
        bunniManager.deposit(address(newPool), address(dai), 1e18, 1e6, SLIPPAGE_DEFAULT);
    }

    function test_deposit_nonOhmTokens_fuzz(uint256 usdcAmount_) public {
        uint256 usdcAmount = bound(usdcAmount_, 100e6, 1e12);
        uint256 daiAmount = usdcAmount.mulDiv(1e18, 1e6); // Same price, different decimal scale

        // Create a pool with non-OHM tokens
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        IUniswapV3Pool newPool = IUniswapV3Pool(uniswapFactory.createPool(address(usdc), address(dai), POOL_FEE));
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployToken(address(newPool));

        // Mint tokens to the TRSRY
        dai.mint(address(treasury), daiAmount);
        usdc.mint(address(treasury), usdcAmount);
        uint256 ohmSupplyBefore = ohm.totalSupply();

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(address(newPool), address(dai), daiAmount, usdcAmount, SLIPPAGE_DEFAULT);

        // The tokens should have been deposited into TRSRY
        assertEq(bunniToken.balanceOf(address(treasury)), bunniTokenShares);

        // No remaining balance in the policy
        assertEq(dai.balanceOf(address(bunniManager)), 0);
        assertEq(usdc.balanceOf(address(bunniManager)), 0);

        // No remaining balance in the bunniHub
        assertEq(dai.balanceOf(address(bunniHub)), 0);
        assertEq(usdc.balanceOf(address(bunniHub)), 0);

        // No OHM was minted
        assertEq(ohm.totalSupply(), ohmSupplyBefore);
    }

    function test_deposit_ohmToken_fuzz(uint256 amount_) public {
        uint256 amount = bound(amount_, 100e6, 1e12);
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(address(treasury), USDC_DEPOSIT);
        uint256 ohmSupplyBefore = ohm.totalSupply();

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(address(pool), address(ohm), OHM_DEPOSIT, USDC_DEPOSIT, SLIPPAGE_DEFAULT);

        // The tokens should have been deposited into TRSRY
        assertEq(bunniToken.balanceOf(address(treasury)), bunniTokenShares);

        // No remaining balance in the policy
        assertEq(ohm.balanceOf(address(bunniManager)), 0);
        assertEq(usdc.balanceOf(address(bunniManager)), 0);

        // No remaining balance in the bunniHub
        assertEq(ohm.balanceOf(address(bunniHub)), 0);
        assertEq(usdc.balanceOf(address(bunniHub)), 0);

        // OHM was minted
        // The exact amount of OHM is only known at run-time (due to slippage)
        BunniLens bunniLens = new BunniLens(bunniHub);
        (uint112 reserve0, uint112 reserve1) = bunniLens.getReserves(_getBunniKey(pool, bunniToken));
        uint256 ohmReserve = pool.token0() == address(ohm) ? reserve0 : reserve1;

        // Tolerant of rounding
        assertApproxEqAbs(ohm.totalSupply(), ohmSupplyBefore + ohmReserve, 1);
    }

    function test_deposit_slippage_fuzz(uint256 amount_, uint256 slippage_) public {
        uint256 slippage = bound(slippage_, 50, 500); // 0.5 - 5%

        /**
         * Get a random amount of OHM to deposit
         * Calculate the amount of USDC to match that (so they are in proportion),
         * with the slippage parameter applied.
         */
        uint256 amount = bound(amount_, 100e6, 1e12);
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18).mulDiv(SLIPPAGE_MAX - slippage, SLIPPAGE_MAX);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(address(treasury), USDC_DEPOSIT);
        uint256 ohmSupplyBefore = ohm.totalSupply();

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(address(pool), address(ohm), OHM_DEPOSIT, USDC_DEPOSIT, slippage);

        // The tokens should have been deposited into TRSRY
        assertEq(bunniToken.balanceOf(address(treasury)), bunniTokenShares);

        // No remaining balance in the policy
        assertEq(ohm.balanceOf(address(bunniManager)), 0);
        assertEq(usdc.balanceOf(address(bunniManager)), 0);

        // No remaining balance in the bunniHub
        assertEq(ohm.balanceOf(address(bunniHub)), 0);
        assertEq(usdc.balanceOf(address(bunniHub)), 0);

        // OHM was minted
        // The exact amount of OHM is only known at run-time (due to slippage)
        BunniLens bunniLens = new BunniLens(bunniHub);
        (uint112 reserve0, uint112 reserve1) = bunniLens.getReserves(_getBunniKey(pool, bunniToken));
        uint256 ohmReserve = pool.token0() == address(ohm) ? reserve0 : reserve1;
        uint256 usdcReserve = pool.token0() == address(usdc) ? reserve0 : reserve1;

        // Tolerant of rounding
        assertApproxEqAbs(ohm.totalSupply(), ohmSupplyBefore + ohmReserve, 1);
        assertApproxEqAbs(usdcReserve, USDC_DEPOSIT, 1);
    }

    function test_deposit_invalidSlippage() public {
        uint256 OHM_DEPOSIT = 1000e9;
        uint256 USDC_DEPOSIT = OHM_DEPOSIT.mulDiv(1e6, 1e9).mulDiv(OHM_USDC_PRICE, 1e18);

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(address(treasury), USDC_DEPOSIT);
        
        // Set up the invalid slippage
        uint256 slippage = SLIPPAGE_MAX + 1;
        _expectRevert_invalidSlippage(slippage);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(address(pool), address(ohm), OHM_DEPOSIT, USDC_DEPOSIT, slippage);
    }

    // [X] withdraw
    //  [X] caller is unauthorized
    //  [X] bunniHub not set
    //  [X] token not deployed
    //  [X] insufficient share balance
    //  [X] withdraws and returns non-OHM tokens to TRSRY
    //  [X] withdraws, burns OHM and returns non-OHM tokens to TRSRY
    //  [X] reverts when inactive

    function test_withdraw_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.withdraw(address(pool), 1e18, SLIPPAGE_DEFAULT);
    }

    function test_withdraw_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = new BunniManager(kernel);

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.withdraw(address(pool), 1e18, SLIPPAGE_DEFAULT);
    }

    function test_withdraw_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.withdraw(address(pool), 1e18, SLIPPAGE_DEFAULT);
    }

    function test_withdraw_tokenNotDeployedReverts() public {
        _expectRevert_poolNotFound(address(pool));

        vm.prank(policy);
        bunniManager.withdraw(address(pool), 1e18, SLIPPAGE_DEFAULT);
    }

    function test_withdraw_insufficientBalanceReverts() public {
        uint256 USDC_DEPOSIT = 10e6 * OHM_USDC_PRICE / 1e18; // Ensures that the token amounts are in the correct ratio
        uint256 OHM_DEPOSIT = 10e9;

        // Deploy the token
        vm.prank(policy);
        IBunniToken token = bunniManager.deployToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(address(treasury), USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(address(pool), address(ohm), OHM_DEPOSIT, USDC_DEPOSIT, SLIPPAGE_DEFAULT);

        // Withdraw
        uint256 bunniTokenSharesToWithdraw = bunniTokenShares * 2;

        _expectRevert_insufficientBalance(address(token), bunniTokenSharesToWithdraw, bunniTokenShares);

        vm.prank(policy);
        bunniManager.withdraw(address(pool), bunniTokenSharesToWithdraw, SLIPPAGE_DEFAULT);
    }

    function test_withdraw_nonOhmTokens(uint256 shareToWithdraw_) public {
        // Create a pool with non-OHM tokens
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        IUniswapV3Pool newPool = IUniswapV3Pool(uniswapFactory.createPool(address(usdc), address(dai), POOL_FEE));
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Deploy the token
        vm.prank(policy);
        IBunniToken token = bunniManager.deployToken(address(newPool));

        // Mint tokens to the TRSRY
        dai.mint(address(treasury), 1e18);
        usdc.mint(address(treasury), 1e6);

        uint256 DAI_DEPOSIT = 1e18;
        uint256 USDC_DEPOSIT = 1e6;

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(address(newPool), address(dai), DAI_DEPOSIT, USDC_DEPOSIT, SLIPPAGE_DEFAULT);
        uint256 bunniTokenSharesToWithdraw = bound(shareToWithdraw_, 1e9, bunniTokenShares);

        // Withdraw
        uint256 usdcBalanceBefore = usdc.balanceOf(address(treasury));
        uint256 daiBalanceBefore = dai.balanceOf(address(treasury));
        uint256 ohmSupplyBefore = ohm.totalSupply();

        vm.prank(policy);
        bunniManager.withdraw(address(newPool), bunniTokenSharesToWithdraw, SLIPPAGE_DEFAULT);

        // Check that:
        // withdrawn DAU has been returned to TRSRY
        // withdrawn USDC has been returned to TRSRY
        // OHM supply did not change
        uint256 usdcBalanceAfter = usdc.balanceOf(address(treasury));
        uint256 daiBalanceAfter = dai.balanceOf(address(treasury));

        assertApproxEqAbs(usdcBalanceAfter - usdcBalanceBefore, USDC_DEPOSIT.mulDiv(bunniTokenSharesToWithdraw, bunniTokenShares), 1e3);
        assertApproxEqAbs(daiBalanceAfter - daiBalanceBefore, DAI_DEPOSIT.mulDiv(bunniTokenSharesToWithdraw, bunniTokenShares), 1e6);
        assertEq(ohm.totalSupply(), ohmSupplyBefore);

        // Policy does not contain any balances
        assertEq(usdc.balanceOf(address(bunniManager)), 0);
        assertEq(dai.balanceOf(address(bunniManager)), 0);
        assertEq(ohm.balanceOf(address(bunniManager)), 0);
        assertEq(token.balanceOf(address(bunniManager)), 0);
    }

    function test_withdraw_ohmToken(uint256 shareToWithdraw_) public {
        uint256 USDC_DEPOSIT = 10e6 * OHM_USDC_PRICE / 1e18; // Ensures that the token amounts are in the correct ratio
        uint256 OHM_DEPOSIT = 10e9;

        // Deploy the token
        vm.prank(policy);
        IBunniToken token = bunniManager.deployToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(address(treasury), USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(address(pool), address(ohm), OHM_DEPOSIT, USDC_DEPOSIT, SLIPPAGE_DEFAULT);
        uint256 bunniTokenSharesToWithdraw = bound(shareToWithdraw_, 1e9, bunniTokenShares);

        // Withdraw
        uint256 usdcBalanceBefore = usdc.balanceOf(address(treasury));
        uint256 ohmSupplyBefore = ohm.totalSupply();

        vm.prank(policy);
        bunniManager.withdraw(address(pool), bunniTokenSharesToWithdraw, SLIPPAGE_DEFAULT);

        // Check that:
        // withdrawn USDC has been returned to TRSRY
        // withdrawn OHM has been burnt
        uint256 usdcBalanceAfter = usdc.balanceOf(address(treasury));
        uint256 ohmSupplyAfter = ohm.totalSupply();

        assertApproxEqAbs(usdcBalanceAfter - usdcBalanceBefore, USDC_DEPOSIT.mulDiv(bunniTokenSharesToWithdraw, bunniTokenShares), 1e4);
        assertApproxEqAbs(ohmSupplyBefore - ohmSupplyAfter, OHM_DEPOSIT.mulDiv(bunniTokenSharesToWithdraw, bunniTokenShares), 1e3);

        // Policy does not contain any balances
        assertEq(usdc.balanceOf(address(bunniManager)), 0);
        assertEq(ohm.balanceOf(address(bunniManager)), 0);
        assertEq(token.balanceOf(address(bunniManager)), 0);
    }

    function test_withdraw_invalidSlippage() public {
        uint256 OHM_DEPOSIT = 1000e9;
        uint256 USDC_DEPOSIT = OHM_DEPOSIT.mulDiv(1e6, 1e9).mulDiv(OHM_USDC_PRICE, 1e18);

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(address(treasury), USDC_DEPOSIT);
        
        // Deposit
        vm.prank(policy);
        uint256 shares = bunniManager.deposit(address(pool), address(ohm), OHM_DEPOSIT, USDC_DEPOSIT, SLIPPAGE_DEFAULT);

        // Set up the incorrect slippage
        uint256 slippage = SLIPPAGE_MAX + 1;
        _expectRevert_invalidSlippage(slippage);

        // Withdraw
        vm.prank(policy);
        bunniManager.withdraw(address(pool), shares, slippage);
    }

    // [X] getToken
    //  [X] bunniHub is not set
    //  [X] token is not deployed
    //  [X] returns token struct
    //  [X] returns even if inactive

    function test_getToken_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        newBunniManager.getToken(address(pool));
    }

    function test_getToken_tokenNotDeployedReverts() public {
        _expectRevert_poolNotFound(address(pool));

        bunniManager.getToken(address(pool));
    }

    function test_getToken() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployToken(address(pool));

        // Get the token
        IBunniToken token = bunniManager.getToken(address(pool));

        // Check return value
        assertEq(address(token.pool()), address(pool));
        assertEq(token.tickLower(), int24(-1 * TICK));
        assertEq(token.tickUpper(), TICK);
    }

    function test_getToken_inactive() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployToken(address(pool));

        // Disable the policy
        kernel.executeAction(Actions.DeactivatePolicy, address(bunniManager));

        // Get the token
        IBunniToken token = bunniManager.getToken(address(pool));

        // Check return value
        assertEq(address(token.pool()), address(pool));
        assertEq(token.tickLower(), int24(-1 * TICK));
        assertEq(token.tickUpper(), TICK);
    }

    // [X] getTRSRYBalance
    //  [X] bunniHub is not set
    //  [X] token is not deployed
    //  [X] returns token balance
    //  [X] returns even if inactive

    function test_getTRSRYBalance_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        newBunniManager.getTRSRYBalance(address(pool));
    }

    function test_getTRSRYBalance_tokenNotDeployedReverts() public {
        _expectRevert_poolNotFound(address(pool));

        bunniManager.getTRSRYBalance(address(pool));
    }

    function test_getTRSRYBalance_zeroBalance() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployToken(address(pool));

        // Get the token
        uint256 balance = bunniManager.getTRSRYBalance(address(pool));

        // Check return value
        assertEq(balance, 0);
    }

    function test_getTRSRYBalance_fuzz(uint256 amount_) public {
        uint256 amount = bound(amount_, 100e6, 1e12);
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(address(treasury), USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(address(pool), address(ohm), OHM_DEPOSIT, USDC_DEPOSIT, SLIPPAGE_DEFAULT);

        // Check that the value is consistent
        uint256 balance = bunniManager.getTRSRYBalance(address(pool));
        assertEq(balance, bunniTokenShares);
    }

    function test_getTRSRYBalance_inactive() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(address(treasury), USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(address(pool), address(ohm), OHM_DEPOSIT, USDC_DEPOSIT, SLIPPAGE_DEFAULT);

        // Disable the policy
        kernel.executeAction(Actions.DeactivatePolicy, address(bunniManager));

        // Check that the value is consistent
        uint256 balance = bunniManager.getTRSRYBalance(address(pool));
        assertEq(balance, bunniTokenShares);
    }

    // [X] setBunniHub
    //  [X] caller is unauthorized
    //  [X] zero address
    //  [X] sets bunniHub variable
    //  [X] works if inactive

    function test_setBunniHub_unauthorizedReverts() public {
        // Create a new BunniHub
        BunniHub newBunniHub = new BunniHub(
            uniswapFactory,
            address(bunniManager),
            0 // No protocol fee
        );

        _expectRevert_unauthorized();

        // Call as an unauthorized user
        vm.prank(alice);
        bunniManager.setBunniHub(address(newBunniHub));
    }

    function test_setBunniHub_zeroAddressReverts() public {
        _expectRevert_invalidAddress(address(0));

        // Call with a zero address
        vm.prank(policy);
        bunniManager.setBunniHub(address(0));
    }

    function test_setBunniHub() public {
        // Create a new BunniHub
        BunniHub newBunniHub = new BunniHub(
            uniswapFactory,
            address(bunniManager),
            0 // No protocol fee
        );

        // Call
        vm.prank(policy);
        bunniManager.setBunniHub(address(newBunniHub));

        // Check that the value has been updated
        assertEq(address(bunniManager.bunniHub()), address(newBunniHub));
    }

    function test_setBunniHub_inactive() public {
        // Create a new BunniHub
        BunniHub newBunniHub = new BunniHub(
            uniswapFactory,
            address(bunniManager),
            0 // No protocol fee
        );

        // Disable the policy
        kernel.executeAction(Actions.DeactivatePolicy, address(bunniManager));

        // Call
        vm.prank(policy);
        bunniManager.setBunniHub(address(newBunniHub));

        // Check that the value has been updated
        assertEq(address(bunniManager.bunniHub()), address(newBunniHub));
    }

    // [X] setBunniOwner
    //  [X] caller is unauthorized
    //  [X] bunniHub is not set
    //  [X] zero address
    //  [X] sets owner of bunniHub
    //  [ ] works if inactive

    function test_setBunniOwner_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        // Call as an unauthorized user
        vm.prank(alice);
        bunniManager.setBunniOwner(alice);
    }

    function test_setBunniOwner_zeroAddressReverts() public {
        _expectRevert_invalidAddress(address(0));

        // Call with a zero address
        vm.prank(policy);
        bunniManager.setBunniOwner(address(0));
    }

    function test_setBunniOwner_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        // Call
        vm.prank(policy);
        newBunniManager.setBunniOwner(address(alice));
    }

    function test_setBunniOwner() public {
        // Call
        vm.prank(policy);
        bunniManager.setBunniOwner(address(alice));

        // Check that the value has been updated
        assertEq(bunniManager.bunniHub().owner(), address(alice));

        // Attempt to perform an action on the BunniHub as the old owner
        vm.expectRevert(
            bytes("UNAUTHORIZED")
        ); // Reverts with "UNAUTHORIZED" from the BunniHub (not Bophades)
        vm.prank(policy);
        bunniHub.setProtocolFee(1);

        // Attempt to perform an action on the BunniHub as the new owner
        vm.prank(alice);
        bunniHub.setProtocolFee(1);
        assertEq(bunniHub.protocolFee(), 1);
    }

    function test_setBunniOwner_inactive() public {
        // Disable the policy
        kernel.executeAction(Actions.DeactivatePolicy, address(bunniManager));

        // Call
        vm.prank(policy);
        bunniManager.setBunniOwner(address(alice));

        // Check that the value has been updated
        assertEq(bunniManager.bunniHub().owner(), address(alice));

        // Attempt to perform an action on the BunniHub as the old owner
        vm.expectRevert(
            bytes("UNAUTHORIZED")
        ); // Reverts with "UNAUTHORIZED" from the BunniHub (not Bophades)
        vm.prank(policy);
        bunniHub.setProtocolFee(1);

        // Attempt to perform an action on the BunniHub as the new owner
        vm.prank(alice);
        bunniHub.setProtocolFee(1);
        assertEq(bunniHub.protocolFee(), 1);
    }
}