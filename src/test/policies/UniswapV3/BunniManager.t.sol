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
import {SqrtPriceMath} from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";

import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {SwapRouter} from "test/lib/UniswapV3/SwapRouter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

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
    MockERC20 internal wETH;

    Kernel internal kernel;
    OlympusRoles internal roles;
    OlympusTreasury internal treasury;
    OlympusMinter internal mintr;
    OlympusPricev2 internal price;

    UniswapV3Factory internal uniswapFactory;
    SwapRouter internal swapRouter;

    RolesAdmin internal rolesAdmin;

    BunniManager internal bunniManager;
    BunniHub internal bunniHub;
    IUniswapV3Pool internal pool;

    uint24 private constant POOL_FEE = 500;
    uint256 private constant OHM_USDC_PRICE = 115897 * 1e14; // 11.5897 USDC per OHM in 18 decimal places
    uint160 private constant OHM_USDC_SQRTPRICEX96 = 8529245188595251053303005012; // From OHM-USDC, 1 OHM = 11.5897 USDC
    uint160 private constant DAI_USDC_SQRTPRICEX96 = 79227120762198600072084; // From DAI-USDC, 1 DAI = 1 USDC

    int24 private constant TICK = 887250; // (887272/50)*50

    uint8 private constant BUNNI_TOKEN_DECIMALS = 18;

    uint16 private constant BPS_MAX = 10_000; // 100%

    uint256 private constant SLIPPAGE_DEFAULT = 100; // 1%
    uint256 private constant SLIPPAGE_MAX = 10000; // 100%

    uint8 private constant PRICE_VERSION = 2;
    uint8 private constant TRSRY_VERSION = 1;
    uint8 private constant ROLES_VERSION = 1;
    uint8 private constant MINTR_VERSION = 1;

    uint256 private constant USDC_PRICE = 1e18;
    uint256 private constant OHM_PRICE = OHM_USDC_PRICE;

    // Keep the max reward low and fee high, so that the capped reward is low
    uint256 private constant HARVEST_REWARD = 1e9;
    uint16 private constant HARVEST_REWARD_FEE = 1000; // 10%
    uint48 private constant HARVEST_FREQUENCY = uint48(24 hours);

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
            wETH = new MockERC20("Wrapped Ether", "wETH", 18);
        }

        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy modules
            roles = new OlympusRoles(kernel);
            treasury = new OlympusTreasury(kernel);
            mintr = new OlympusMinter(kernel, address(ohm));
            price = new OlympusPricev2(kernel, uint8(18), uint32(8 hours));
        }

        {
            // Deploy BunniManager policy
            bunniManager = new BunniManager(
                kernel,
                HARVEST_REWARD,
                HARVEST_REWARD_FEE,
                HARVEST_FREQUENCY
            );

            // Deploy Uniswap V3 factory
            uniswapFactory = new UniswapV3Factory();

            // Deploy Uniswap V3 SwapRouter
            swapRouter = new SwapRouter(address(uniswapFactory), address(wETH));

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
            // Mock values, to avoid having to set up all of PRICEv2 and submodules
            _mockGetPrice(address(ohm), OHM_PRICE);
            _mockGetPrice(address(usdc), USDC_PRICE);
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

    function _expectRevert_tokenDeployed(address pool_, address token_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_TokenDeployed.selector,
            pool_,
            token_
        );
        vm.expectRevert(err);
    }

    function _expectRevert_tokenNotDeployed(address pool_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_TokenNotDeployed.selector,
            pool_
        );
        vm.expectRevert(err);
    }

    function _expectRevert_priceZero(address asset_) internal {
        bytes memory err = abi.encodeWithSelector(
            PRICEv2.PRICE_AssetNotApproved.selector, asset_);
        vm.expectRevert(err);
    }

    function _expectRevert_harvestTooEarly(uint48 nextHarvest_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_HarvestTooEarly.selector, nextHarvest_);
        vm.expectRevert(err);
    }

    function _mockGetPrice(address asset_, uint256 price_) internal {
        vm.mockCall(
            address(price),
            abi.encodeWithSignature("getPrice(address)", address(asset_)),
            abi.encode(price_)
        );
    }

    function _mockGetPriceReverts(address asset_) internal {
        bytes memory err = abi.encodeWithSelector(
            PRICEv2.PRICE_AssetNotApproved.selector, asset_);

        vm.mockCallRevert(
            address(price),
            abi.encodeWithSignature("getPrice(address)", asset_),
            err
        );
    }

    function _createNewBunniManager() internal returns (BunniManager) {
        // Create a new BunniManager policy
        return new BunniManager(kernel, HARVEST_REWARD, HARVEST_REWARD_FEE, HARVEST_FREQUENCY);
    }

    function _setUpNewBunniManager() internal returns (BunniManager) {
        // Create a new BunniManager policy, with the BunniHub set
        BunniManager newBunniManager = _createNewBunniManager();
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

    function _swap(address tokenIn_, address tokenOut_, address recipient_, uint256 amountIn_, uint256 amountOutMinimum_) internal returns (uint256) {
        // Approve token transfer
        vm.prank(recipient_);
        IERC20(tokenIn_).approve(address(swapRouter), amountIn_);

        bool zeroForOne = pool.token0() == tokenIn_ ? true : false;
        // NOTE: The docs say that a value of 0 should work in testing, but it reverts due to a check. This value seems to work, after days of testing.
        uint160 sqrtPriceLimitX96 = TickMath.getSqrtRatioAtTick(zeroForOne ? -TICK : TICK);

        // Perform the swap
        vm.prank(recipient_);
        return swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn_,
                tokenOut: tokenOut_,
                fee: POOL_FEE,
                recipient: recipient_,
                deadline: block.timestamp,
                amountIn: amountIn_,
                amountOutMinimum: amountOutMinimum_,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            })
        );
    }

    function _recalculateFees(IUniswapV3Pool pool_) internal {
        // Calling burn with 0 amount triggers an update of fees for the caller
        vm.prank(address(bunniHub));
        pool_.burn(-TICK, TICK, uint128(0));
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

    // [X] registerPool
    //  [X] reverts if caller is unauthorized
    //  [X] reverts if bunniHub not set
    //  [X] reverts if token already managed by the policy
    //  [X] reverts if not a Uniswap V3 pool
    //  [X] reverts if no token deployed
    //  [X] reverts if inactive
    //  [X] deploys and returns token
    //  [X] reverts if either asset price not defined

    function test_registerPool_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.registerPool(address(pool));
    }

    function test_registerPool_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.registerPool(address(pool));
    }

    function test_registerPool_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.registerPool(address(pool));
    }

    function test_registerPool_invalidPoolReverts() public {
        _expectRevert_poolNotFound(address(ohm));

        vm.prank(policy);
        bunniManager.registerPool(address(ohm));
    }

    function test_registerPool_noDeployedTokenReverts() public {
        // Expect an error, as no token has been deployed against the pool
        _expectRevert_poolNotFound(address(pool));

        // Register the pool with the new policy
        vm.prank(policy);
        bunniManager.registerPool(address(pool));
    }

    function test_registerPool_alreadyDeployedTokenReverts() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployToken(address(pool));

        _expectRevert_tokenDeployed(address(pool), address(deployedToken));

        // Register the pool
        vm.prank(policy);
        bunniManager.registerPool(address(pool));
    }

    function test_registerPool_usdcPriceUnsetReverts() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        bunniManager.deployToken(address(pool));

        // Install a new policy
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniHub(address(bunniHub));

        // Mock an error when getting the price
        _mockGetPriceReverts(address(usdc));

        _expectRevert_priceZero(address(usdc));

        vm.prank(policy);
        newBunniManager.registerPool(address(pool));
    }

    function test_registerPool_ohmPriceUnsetReverts() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        bunniManager.deployToken(address(pool));

        // Install a new policy
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniHub(address(bunniHub));

        // Mock an error when getting the price
        _mockGetPriceReverts(address(ohm));

        _expectRevert_priceZero(address(ohm));

        vm.prank(policy);
        newBunniManager.registerPool(address(pool));
    }

    function test_registerPool() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployToken(address(pool));

        // Install a new policy
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniHub(address(bunniHub));

        // Register the pool with the new policy
        vm.prank(policy);
        IBunniToken newDeployedToken = newBunniManager.registerPool(address(pool));

        // Token should be the same as before
        assertEq(address(newDeployedToken), address(deployedToken));

        // Check that the pool is registered
        uint256 poolCount = newBunniManager.poolCount();
        assertEq(poolCount, 1);
        address poolOne = newBunniManager.pools(0);
        assertEq(poolOne, address(pool));

        // Check that the token has been added to PRICEv2
        PRICEv2.Asset memory priceAsset = price.getAssetData(address(newDeployedToken));
        assertTrue(priceAsset.approved);
    }

    // [X] deployToken
    //  [X] caller is unauthorized
    //  [X] bunniHub not set
    //  [X] token already deployed
    //  [X] not a Uniswap V3 pool
    //  [X] deploys and returns token, registers with PRICEv2
    //  [X] reverts when inactive
    //  [X] reverts if either asset price not defined

    function test_deployToken_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.deployToken(address(pool));
    }

    function test_deployToken_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

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

    function test_deployToken_usdcPriceUnsetReverts() public {
        _mockGetPriceReverts(address(usdc));

        _expectRevert_priceZero(address(usdc));

        vm.prank(policy);
        bunniManager.deployToken(address(pool));
    }

    function test_deployToken_ohmPriceUnsetReverts() public {
        _mockGetPriceReverts(address(ohm));

        _expectRevert_priceZero(address(ohm));

        vm.prank(policy);
        bunniManager.deployToken(address(pool));
    }

    function test_deployToken() public {
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployToken(address(pool));

        // Check details of token
        assertEq(address(deployedToken.pool()), address(pool));
        assertEq(deployedToken.tickLower(), -1 * 887250);
        assertEq(deployedToken.tickUpper(), 887250);

        // Check that the pool is registered
        uint256 poolCount = bunniManager.poolCount();
        assertEq(poolCount, 1);
        address poolOne = bunniManager.pools(0);
        assertEq(poolOne, address(pool));

        // Check that the token has been added to PRICEv2
        PRICEv2.Asset memory priceAsset = price.getAssetData(address(deployedToken));
        assertTrue(priceAsset.approved);
        // TODO check that the submodule is configured for use
    }

    function test_deployToken_duplicateReverts() public {
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployToken(address(pool));

        _expectRevert_tokenDeployed(address(pool), address(deployedToken));

        // Deploy a second time
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
        BunniManager newBunniManager = _createNewBunniManager();

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
        _mockGetPrice(address(dai), 1e18);
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
        _mockGetPrice(address(dai), 1e18);
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
        _mockGetPrice(address(dai), 1e18);
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
        BunniManager newBunniManager = _createNewBunniManager();

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
        _mockGetPrice(address(dai), 1e18);
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
    //  [X] works if inactive

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

    // [ ] harvest
    //  [X] reverts if bunniHub is not set
    //  [X] reverts when inactive
    //  [X] reverts if sufficient time has not elapsed
    //  [X] harvest compounds fees to the pool
    //  [ ] harvest compounds fees to the pool, multiple pools
    //  [ ] harvest reward paid matches currentHarvestReward

    function test_harvest_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        // Call
        vm.prank(alice);
        newBunniManager.harvest();
    }

    function test_harvest_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        // Call
        vm.prank(alice);
        newBunniManager.harvest();
    }

    function test_harvest_beforeFrequencyReverts() public {
        _expectRevert_harvestTooEarly(uint48(block.timestamp + HARVEST_FREQUENCY));

        // Call
        vm.prank(policy);
        bunniManager.harvest();
    }

    // [X] getCurrentHarvestReward
    //  [X] returns 0 if sufficient time has not elapsed
    //  [X] returns 0 if no fees
    //  [X] returns fee multiplier * fees
    //  [X] capped at maximum reward

    function test_getCurrentHarvestReward_beforeFrequency(uint48 elapsed_) public {
        uint48 elapsed = uint48(bound(elapsed_, 0, HARVEST_FREQUENCY - 1));
        // Simulate time passing
        vm.warp(block.timestamp + elapsed);

        uint256 currentReward = bunniManager.getCurrentHarvestReward();

        // Should remain 0
        assertEq(currentReward, 0);
    }

    function test_getCurrentHarvestReward_noFees() public {
        // Call
        uint256 currentReward = bunniManager.getCurrentHarvestReward();

        // As no swaps have been done, there are no fees
        assertEq(currentReward, 0);
    }

    function test_getCurrentHarvestReward(uint256 swapAmount_) public {
        uint256 swapAmountUsdcIn = bound(swapAmount_, 100_000e6, 5_000_000e6);

        IBunniToken token;
        {
            uint256 USDC_DEPOSIT = 10_000_000e6 * OHM_USDC_PRICE / 1e18; // Ensures that the token amounts are in the correct ratio
            uint256 OHM_DEPOSIT = 10_000_000e9;

            // Deploy the token
            vm.prank(policy);
            token = bunniManager.deployToken(address(pool));

            // Mint the non-OHM token to the TRSRY
            usdc.mint(address(treasury), USDC_DEPOSIT);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(address(pool), address(ohm), OHM_DEPOSIT, USDC_DEPOSIT, SLIPPAGE_DEFAULT);

            // Mint USDC into another wallet
            usdc.mint(address(alice), swapAmountUsdcIn);
        }

        // Perform the swap
        uint256 swapOneOhmMinimum;
        {
            swapOneOhmMinimum = swapAmountUsdcIn.mulDiv(1e18, 1e6).mulDiv(1e18, OHM_USDC_PRICE).mulDiv(1e9, 1e18).mulDiv(95, 100);
            _swap(address(usdc), address(ohm), address(alice), swapAmountUsdcIn, swapOneOhmMinimum);
        }

        // And reverse
        {
            uint256 swapTwoUsdcMinimum = swapOneOhmMinimum.mulDiv(1e18, 1e9).mulDiv(OHM_USDC_PRICE, 1e18).mulDiv(1e6, 1e18).mulDiv(95, 100);
            console2.log("before");
            _swap(address(ohm), address(usdc), address(alice), swapOneOhmMinimum, swapTwoUsdcMinimum);
            console2.log("after");
        }

        _recalculateFees(pool);

        uint256 expectedRewardOhm;
        {
            // Record the fees generated
            (, , , uint128 fees0, uint128 fees1) = pool.positions(
                keccak256(abi.encodePacked(address(bunniHub), token.tickLower(), token.tickUpper()))
            );
            uint256 usdcFees = uint256(address(pool.token0()) == address(usdc) ? fees0 : fees1).mulDiv(1e18, 1e6).mulDiv(USDC_PRICE, 1e18); // Convert to 18 decimals and multiply by price
            uint256 ohmFees = uint256(address(pool.token0()) == address(ohm) ? fees0 : fees1).mulDiv(1e18, 1e9).mulDiv(OHM_PRICE, 1e18); // Convert to 18 decimals and multiply by price
            uint256 expectedRewardValue = uint256(HARVEST_REWARD_FEE).mulDiv(usdcFees + ohmFees, uint256(BPS_MAX));
            assertGt(expectedRewardValue, 0);
            expectedRewardOhm = expectedRewardValue.mulDiv(1e9, OHM_PRICE);
        }

        // Cap the reward
        if (expectedRewardOhm > HARVEST_REWARD) {
            expectedRewardOhm = HARVEST_REWARD;
        }

        // Call
        uint256 currentReward = bunniManager.getCurrentHarvestReward();

        // Check that the value is consistent
        assertEq(currentReward, expectedRewardOhm);
    }

    // [X] harvestFrequency

    function test_harvestFrequency() public {
        // Check initial value
        assertEq(bunniManager.harvestFrequency(), HARVEST_FREQUENCY);
    }

    // [X] harvestRewardFee

    function test_harvestRewardFee() public {
        // Check initial value
        assertEq(bunniManager.harvestRewardFee(), HARVEST_REWARD_FEE);
    }

    // [X] harvestMaxReward

    function test_harvestRewardMax() public {
        // Check initial value
        assertEq(bunniManager.harvestRewardMax(), HARVEST_REWARD);
    }

    // [X] resetLastHarvest
    //  [X] reverts if caller is unauthorized
    //  [X] resets the lastHarvest so that harvest can be called
    //  [X] returns 0 if the frequency is higher than the current time
    //  [X] works if inactive

    function test_resetLastHarvest_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        // Call as an unauthorized user
        vm.prank(alice);
        bunniManager.resetLastHarvest();
    }

    function test_resetLastHarvest_underflow() public {
        // Set the frequency to be higher than the current block timestamp
        vm.prank(policy);
        bunniManager.setHarvestFrequency(uint48(block.timestamp + 1));

        // Reset the last harvest
        vm.prank(policy);
        bunniManager.resetLastHarvest();

        // lastHarvest is modified, but avoids an underflow
        assertEq(bunniManager.lastHarvest(), 0);
    }

    function test_resetLastHarvest() public {
        // Call harvest and verify that it fails
        _expectRevert_harvestTooEarly(uint48(block.timestamp + HARVEST_FREQUENCY));
        vm.prank(policy);
        bunniManager.harvest();

        // Call
        vm.prank(policy);
        bunniManager.resetLastHarvest();

        // lastHarvest is modified
        assertEq(bunniManager.lastHarvest(), uint48(block.timestamp - HARVEST_FREQUENCY));

        // Harvest should now work
        vm.prank(policy);
        bunniManager.harvest();

        // Check that the value has been updated
        assertEq(bunniManager.lastHarvest(), block.timestamp);
    }

    function test_resetLastHarvest_inactive() public {
        // Call harvest and verify that it fails
        _expectRevert_harvestTooEarly(uint48(block.timestamp + HARVEST_FREQUENCY));
        vm.prank(policy);
        bunniManager.harvest();

        // Deactivate the policy
        kernel.executeAction(Actions.DeactivatePolicy, address(bunniManager));

        // Call
        vm.prank(policy);
        bunniManager.resetLastHarvest();

        // lastHarvest is modified
        assertEq(bunniManager.lastHarvest(), uint48(block.timestamp - HARVEST_FREQUENCY));

        // Can't call harvest as it'll likely revert
    }

    // [X] setHarvestFrequency
    //  [X] reverts if caller is unauthorized
    //  [X] reverts if the frequency is 0
    //  [X] sets the harvestFrequency variable

    function test_setHarvestFrequency_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        // Call as an unauthorized user
        vm.prank(alice);
        bunniManager.setHarvestFrequency(HARVEST_FREQUENCY);
    }

    function test_setHarvestFrequency_zeroFrequencyReverts() public {
        uint48 newFrequency = 0;
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_Params_InvalidHarvestFrequency.selector,
            1,
            newFrequency,
            type(uint48).max
        );
        vm.expectRevert(err);

        // Call with a zero frequency
        vm.prank(policy);
        bunniManager.setHarvestFrequency(newFrequency);
    }

    function test_setHarvestFrequency() public {
        uint48 newFrequency = HARVEST_FREQUENCY + 2;

        // Call
        vm.prank(policy);
        bunniManager.setHarvestFrequency(newFrequency);

        // Check that the value has been updated
        assertEq(bunniManager.harvestFrequency(), newFrequency);
    }

    // [X] setHarvestRewardParameters
    //  [X] reverts if caller is unauthorized
    //  [X] reverts if the fee is invalid
    //  [X] sets the harvestRewardMax and harvestRewardFee variables

    function test_setHarvestRewardParameters_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        // Call as an unauthorized user
        vm.prank(alice);
        bunniManager.setHarvestRewardParameters(HARVEST_REWARD, HARVEST_REWARD_FEE);
    }

    function test_setHarvestRewardParameters_feeInvalidReverts() public {
        uint16 newFee = BPS_MAX + 1;
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_Params_InvalidHarvestFee.selector,
            newFee,
            BPS_MAX
        );
        vm.expectRevert(err);

        // Call with an invalid fee
        vm.prank(policy);
        bunniManager.setHarvestRewardParameters(HARVEST_REWARD, newFee);
    }

    function test_setHarvestRewardParameters() public {
        // Call
        vm.prank(policy);
        uint16 newFee = 200; // 2%
        uint256 newReward = HARVEST_REWARD + 2;
        bunniManager.setHarvestRewardParameters(newReward, newFee);

        // Check that the value has been updated
        assertEq(bunniManager.harvestRewardMax(), newReward);
        assertEq(bunniManager.harvestRewardFee(), newFee);
    }
}