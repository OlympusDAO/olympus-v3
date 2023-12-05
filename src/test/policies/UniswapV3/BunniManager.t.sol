// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {RolesAdmin} from "policies/RolesAdmin.sol";

import {TRSRYv1_1, toCategory as toTreasuryCategory} from "modules/TRSRY/TRSRY.v1.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";
import {OlympusSupply} from "modules/SPPLY/OlympusSupply.sol";
import {SPPLYv1, Category as SupplyCategory, fromCategory as fromSupplyCategory, toCategory as toSupplyCategory} from "modules/SPPLY/SPPLY.v1.sol";
import {BunniPrice} from "modules/PRICE/submodules/feeds/BunniPrice.sol";
import {BunniSupply} from "modules/SPPLY/submodules/BunniSupply.sol";

import {FullMath} from "libraries/FullMath.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";

import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {UniswapV3Pool} from "test/lib/UniswapV3/UniswapV3Pool.sol";
import {SwapRouter} from "test/lib/UniswapV3/SwapRouter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {BunniManager} from "policies/UniswapV3/BunniManager.sol";
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";

import {UniswapV3PoolLibrary} from "libraries/UniswapV3/PoolLibrary.sol";

import {toSubKeycode} from "src/Submodules.sol";

import "src/Kernel.sol";

contract BunniManagerTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusPricev2;
    using ModuleTestFixtureGenerator for OlympusSupply;
    using ModuleTestFixtureGenerator for OlympusTreasury;

    UserFactory public userCreator;
    address internal alice;
    address internal policy;
    address internal writePRICE;
    address internal writeSPPLY;
    address internal writeTRSRY;

    MockOhm internal ohm;
    MockERC20 internal usdc;
    MockERC20 internal wETH;
    address internal usdcAddress;
    address internal ohmAddress;
    address internal token0Address;
    address internal token1Address;

    Kernel internal kernel;

    // Modules
    OlympusRoles internal ROLES;
    OlympusTreasury internal TRSRY;
    OlympusMinter internal MINTR;
    OlympusPricev2 internal PRICE;
    OlympusSupply internal SPPLY;
    address internal treasuryAddress;

    // PRICE submodules
    BunniPrice internal priceSubmoduleBunni;

    // SPPLY submodules
    BunniSupply internal supplySubmoduleBunni;

    UniswapV3Factory internal uniswapFactory;
    SwapRouter internal swapRouter;

    RolesAdmin internal rolesAdmin;

    BunniManager internal bunniManager;
    BunniHub internal bunniHub;
    BunniLens internal bunniLens;
    IUniswapV3Pool internal pool;
    address internal bunniHubAddress;
    address internal bunniLensAddress;
    address internal bunniManagerAddress;

    uint16 internal constant TWAP_DEFAULT_MAX_DEVIATION_BPS = 100; // 1%
    uint32 internal constant TWAP_DEFAULT_OBSERVATION_WINDOW = 600;

    uint24 private constant POOL_FEE = 500;
    uint256 private constant OHM_USDC_PRICE = 115897 * 1e14; // 11.5897 USDC per OHM in 18 decimal places
    // Current tick: -44579
    uint160 private constant OHM_USDC_SQRTPRICEX96 = 8529245188595251053303005012; // From OHM-USDC, 1 OHM = 11.5897 USDC
    // NOTE: these numbers are fudged to match the current tick and default observation window from BunniManager
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_0 = -2463052984970;
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_1 = -2463079732370;

    uint160 private constant DAI_USDC_SQRTPRICEX96 = 79227120762198600072084; // From DAI-USDC, 1 DAI = 1 USDC

    uint24 private constant TICK_SPACING_DIVISOR = 50;
    int24 private constant TICK = 887270; // (887272/(500/50))*(500/50)

    uint16 private constant BPS_MAX = 10_000; // 100%

    uint16 private constant SLIPPAGE_DEFAULT = 100; // 1%
    uint16 private constant SLIPPAGE_MAX = 10_000; // 100%

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

    // DO NOT change these salt values, as they are used to ensure that the addresses are deterministic, and the SQRTPRICEX96 values depend on the ordering
    bytes32 private constant OHM_SALT =
        0x0000000000000000000000000000000000000000000000000000000000000001;
    bytes32 private constant USDC_SALT =
        0x0000000000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant WETH_SALT =
        0x0000000000000000000000000000000000000000000000000000000000000002;
    bytes32 private constant DAI_SALT =
        0x0000000000000000000000000000000000000000000000000000000000000004;

    mapping(address => mapping(address => uint256)) private tokenBalances;

    // Reproduce events
    event BunniLensSet(address indexed newBunniHub_, address indexed newBunniLens_);

    event BunniHubOwnerSet(address indexed bunniHub_, address indexed newOwner_);

    event LastHarvestReset(uint48 newLastHarvest_);

    event HarvestFrequencySet(uint48 newFrequency_);

    event HarvestRewardParamsSet(uint256 newMaxReward_, uint16 newFee_);

    event PoolTokenRegistered(address indexed pool_, address indexed token_);

    event NewBunni(
        IBunniToken indexed token,
        bytes32 indexed bunniKeyHash,
        IUniswapV3Pool indexed pool,
        int24 tickLower,
        int24 tickUpper
    );

    event PoolTokenActivated(address indexed pool_, address indexed token_);

    event PoolTokenDeactivated(address indexed pool_, address indexed token_);

    event PoolSwapFeesUpdated(address indexed pool_);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            address[] memory users = userCreator.create(2);
            alice = users[0];
            policy = users[1];
        }

        {
            // Use salt to ensure that the addresses are deterministic, otherwise changing variables above will change the addresses and mess with the UniV3 pool
            // Source: https://docs.soliditylang.org/en/v0.8.19/control-structures.html#salted-contract-creations-create2
            ohm = new MockOhm{salt: OHM_SALT}("Olympus", "OHM", 9);
            usdc = new MockERC20{salt: USDC_SALT}("USDC", "USDC", 6);
            wETH = new MockERC20{salt: WETH_SALT}("Wrapped Ether", "wETH", 18);

            ohmAddress = address(ohm);
            usdcAddress = address(usdc);
            token0Address = address(ohm) > address(usdc) ? address(usdc) : address(ohm);
            token1Address = address(ohm) > address(usdc) ? address(ohm) : address(usdc);
        }

        // Deploy Bophades modules
        {
            address[2] memory tokens = [ohmAddress, usdcAddress];

            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy modules
            ROLES = new OlympusRoles(kernel);
            TRSRY = new OlympusTreasury(kernel);
            MINTR = new OlympusMinter(kernel, ohmAddress);
            PRICE = new OlympusPricev2(kernel, uint8(18), uint32(8 hours));
            SPPLY = new OlympusSupply(kernel, tokens, 0);

            // Deploy mock module writer
            writePRICE = PRICE.generateGodmodeFixture(type(OlympusPricev2).name);
            writeSPPLY = SPPLY.generateGodmodeFixture(type(OlympusSupply).name);
            writeTRSRY = TRSRY.generateGodmodeFixture(type(OlympusTreasury).name);

            treasuryAddress = address(TRSRY);
        }

        {
            // Deploy BunniManager policy
            bunniManager = new BunniManager(
                kernel,
                HARVEST_REWARD,
                HARVEST_REWARD_FEE,
                HARVEST_FREQUENCY
            );
            bunniManagerAddress = address(bunniManager);

            // Deploy Uniswap V3 factory
            uniswapFactory = new UniswapV3Factory();

            // Deploy Uniswap V3 SwapRouter
            swapRouter = new SwapRouter(address(uniswapFactory), address(wETH));

            // Deploy BunniHub
            bunniHub = new BunniHub(
                uniswapFactory,
                bunniManagerAddress,
                0 // No protocol fee
            );
            bunniHubAddress = address(bunniHub);

            // Deploy BunniLens
            bunniLens = new BunniLens(bunniHub);
            bunniLensAddress = address(bunniLens);

            rolesAdmin = new RolesAdmin(kernel);
        }

        {
            // Initialize system and kernel

            // Install modules
            kernel.executeAction(Actions.InstallModule, address(ROLES));
            kernel.executeAction(Actions.InstallModule, treasuryAddress);
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(PRICE));
            kernel.executeAction(Actions.InstallModule, address(SPPLY));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, bunniManagerAddress);
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ActivatePolicy, address(writePRICE));
            kernel.executeAction(Actions.ActivatePolicy, address(writeSPPLY));
            kernel.executeAction(Actions.ActivatePolicy, address(writeTRSRY));
        }

        // PRICE Submodule
        {
            priceSubmoduleBunni = new BunniPrice(PRICE);

            vm.startPrank(writePRICE);
            PRICE.installSubmodule(priceSubmoduleBunni);
            vm.stopPrank();
        }

        // SPPLY Submodule
        {
            supplySubmoduleBunni = new BunniSupply(SPPLY);

            vm.startPrank(writeSPPLY);
            SPPLY.installSubmodule(supplySubmoduleBunni);
            vm.stopPrank();
        }

        {
            // Configure access control

            // BunniManager roles
            rolesAdmin.grantRole("bunni_admin", policy);
        }

        {
            // Create a Uniswap V3 pool
            pool = IUniswapV3Pool(uniswapFactory.createPool(ohmAddress, usdcAddress, POOL_FEE));

            // Initialize it
            pool.initialize(OHM_USDC_SQRTPRICEX96);

            // Mock observations
            _mockPoolObserve(
                address(pool),
                TWAP_DEFAULT_OBSERVATION_WINDOW,
                OHM_USDC_TICK_CUMULATIVE_0,
                OHM_USDC_TICK_CUMULATIVE_1
            );
        }

        {
            // Mock values, to avoid having to set up all of PRICEv2 and submodules
            _mockGetPrice(ohmAddress, OHM_PRICE);
            _mockGetPrice(usdcAddress, USDC_PRICE);
        }

        {
            vm.prank(policy);
            // Set the BunniHub on the manager policy
            bunniManager.setBunniLens(bunniLensAddress);
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
        bytes memory err = abi.encodeWithSelector(BunniManager.BunniManager_HubNotSet.selector);
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

    function _expectRevert_insufficientBalance(
        address token_,
        uint256 requiredBalance_,
        uint256 actualBalance_
    ) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_InsufficientBalance.selector,
            token_,
            requiredBalance_,
            actualBalance_
        );
        vm.expectRevert(err);
    }

    function _expectRevert_invalidSlippage(uint16 slippage_) internal {
        bytes memory err = abi.encodeWithSelector(
            UniswapV3PoolLibrary.InvalidSlippage.selector,
            slippage_,
            SLIPPAGE_MAX
        );
        vm.expectRevert(err);
    }

    function _expectRevert_wrongModuleVersion() internal {
        bytes memory expectedVersions = abi.encode([1, 2, 1, 1, 1]);

        bytes memory err = abi.encodeWithSelector(
            Policy.Policy_WrongModuleVersion.selector,
            expectedVersions
        );
        vm.expectRevert(err);
    }

    function _expectRevert_inactive() internal {
        bytes memory err = abi.encodeWithSelector(BunniManager.BunniManager_Inactive.selector);
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

    function _expectRevert_priceZero(address asset_) internal {
        bytes memory err = abi.encodeWithSelector(PRICEv2.PRICE_AssetNotApproved.selector, asset_);
        vm.expectRevert(err);
    }

    function _expectRevert_harvestTooEarly(uint48 nextHarvest_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_HarvestTooEarly.selector,
            nextHarvest_
        );
        vm.expectRevert(err);
    }

    function _expectRevert_tokenActivated(address pool_, Keycode module_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_TokenActivated.selector,
            pool_,
            module_
        );
        vm.expectRevert(err);
    }

    function _mockGetPrice(address asset_, uint256 price_) internal {
        vm.mockCall(
            address(PRICE),
            abi.encodeWithSignature("getPrice(address)", address(asset_)),
            abi.encode(price_)
        );
    }

    function _mockGetPriceReverts(address asset_) internal {
        bytes memory err = abi.encodeWithSelector(PRICEv2.PRICE_AssetNotApproved.selector, asset_);

        vm.mockCallRevert(
            address(PRICE),
            abi.encodeWithSignature("getPrice(address)", asset_),
            err
        );
    }

    function _mockPoolObserve(
        address pool_,
        uint32 period_,
        int56 tickCumulative0_,
        int56 tickCumulative1_
    ) internal {
        // Input
        uint32[] memory observationWindow = new uint32[](2);
        observationWindow[0] = period_;
        observationWindow[1] = 0;

        // Output
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0_;
        tickCumulatives[1] = tickCumulative1_;

        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);

        vm.mockCall(
            address(pool_),
            abi.encodeWithSelector(UniswapV3Pool.observe.selector, observationWindow),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
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

    function _getBunniKey(
        IUniswapV3Pool pool_,
        IBunniToken token_
    ) internal view returns (BunniKey memory) {
        return
            BunniKey({pool: pool_, tickLower: token_.tickLower(), tickUpper: token_.tickUpper()});
    }

    function _getTick(uint24 poolFee, bool upper_) internal pure returns (int24) {
        int24 tickSpacing = int24(poolFee) / int24(TICK_SPACING_DIVISOR);
        return
            (upper_ == true ? int24(1) : int24(-1)) *
            (TickMath.MAX_TICK / tickSpacing) *
            tickSpacing;
    }

    function _swap(
        address tokenIn_,
        address tokenOut_,
        address recipient_,
        uint256 amountIn_,
        uint256 amountOutMinimum_,
        uint24 poolFee_
    ) internal returns (uint256) {
        // Approve token transfer
        vm.prank(recipient_);
        IERC20(tokenIn_).approve(address(swapRouter), amountIn_);

        bool zeroForOne = pool.token0() == tokenIn_ ? true : false;
        // NOTE: The docs say that a value of 0 should work in testing, but it reverts due to a check. This value seems to work, after days of testing.
        uint160 sqrtPriceLimitX96 = TickMath.getSqrtRatioAtTick(zeroForOne ? -TICK : TICK);

        // Perform the swap
        vm.prank(recipient_);
        return
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn_,
                    tokenOut: tokenOut_,
                    fee: poolFee_,
                    recipient: recipient_,
                    deadline: block.timestamp,
                    amountIn: amountIn_,
                    amountOutMinimum: amountOutMinimum_,
                    sqrtPriceLimitX96: sqrtPriceLimitX96
                })
            );
    }

    function _recalculateFees(IUniswapV3Pool pool_) internal {
        // Get the min and max tick for the pool
        int24 tick = _getTick(pool_.fee(), true);

        // Calling burn with 0 amount triggers an update of fees for the caller
        vm.prank(bunniHubAddress);
        pool_.burn(-tick, tick, uint128(0));
    }

    function _storeTokenBalance(address wallet_, address token_) internal {
        tokenBalances[wallet_][token_] = IERC20(token_).balanceOf(wallet_);
    }

    function _getStoredTokenBalance(
        address wallet_,
        address token_
    ) internal view returns (uint256) {
        return tokenBalances[wallet_][token_];
    }

    function _getPoolFees(
        IBunniToken token_,
        address tokenA_
    ) internal view returns (uint256 tokenAFees, uint256 tokenBFees) {
        (, , , uint128 fees0Before, uint128 fees1Before) = token_.pool().positions(
            keccak256(abi.encodePacked(bunniHubAddress, token_.tickLower(), token_.tickUpper()))
        );

        tokenAFees = address(token_.pool().token0()) == tokenA_ ? fees0Before : fees1Before;
        tokenBFees = address(token_.pool().token0()) == tokenA_ ? fees1Before : fees0Before;
    }

    // [X] constructor (tested in setUp)
    // [X] configureDependencies
    //  [X] reverts if TRSRY version is unsupported
    //  [X] configures correctly

    function test_configureDependencies() public {
        Keycode[] memory expectedDependencies = new Keycode[](5);
        expectedDependencies[0] = toKeycode("ROLES");
        expectedDependencies[1] = toKeycode("TRSRY");
        expectedDependencies[2] = toKeycode("PRICE");
        expectedDependencies[3] = toKeycode("MINTR");
        expectedDependencies[4] = toKeycode("SPPLY");

        Keycode[] memory deps = bunniManager.configureDependencies();
        assertEq(deps.length, expectedDependencies.length);
        for (uint256 i = 0; i < deps.length; i++) {
            assertEq(fromKeycode(deps[i]), fromKeycode(expectedDependencies[i]));
        }
    }

    function test_configureDependencies_priceVersionReverts(uint8 version_) public {
        vm.assume(version_ != PRICE_VERSION);

        Keycode[] memory expectedDependencies = new Keycode[](5);
        expectedDependencies[0] = toKeycode("ROLES");
        expectedDependencies[1] = toKeycode("TRSRY");
        expectedDependencies[2] = toKeycode("PRICE");
        expectedDependencies[3] = toKeycode("MINTR");
        expectedDependencies[4] = toKeycode("SPPLY");

        // Mock an incompatibility with the module
        vm.mockCall(
            address(PRICE),
            abi.encodeWithSelector(OlympusPricev2.VERSION.selector),
            abi.encode(version_, 0)
        );
        _expectRevert_wrongModuleVersion();

        bunniManager.configureDependencies();
    }

    function test_configureDependencies_treasuryVersionReverts(uint8 version_) public {
        vm.assume(version_ != TRSRY_VERSION);

        Keycode[] memory expectedDependencies = new Keycode[](5);
        expectedDependencies[0] = toKeycode("ROLES");
        expectedDependencies[1] = toKeycode("TRSRY");
        expectedDependencies[2] = toKeycode("PRICE");
        expectedDependencies[3] = toKeycode("MINTR");
        expectedDependencies[4] = toKeycode("SPPLY");

        // Mock an incompatibility with the module
        vm.mockCall(
            treasuryAddress,
            abi.encodeWithSelector(OlympusTreasury.VERSION.selector),
            abi.encode(version_, 1)
        );
        _expectRevert_wrongModuleVersion();

        bunniManager.configureDependencies();
    }

    function test_configureDependencies_rolesVersionReverts(uint8 version_) public {
        vm.assume(version_ != ROLES_VERSION);

        Keycode[] memory expectedDependencies = new Keycode[](5);
        expectedDependencies[0] = toKeycode("ROLES");
        expectedDependencies[1] = toKeycode("TRSRY");
        expectedDependencies[2] = toKeycode("PRICE");
        expectedDependencies[3] = toKeycode("MINTR");
        expectedDependencies[4] = toKeycode("SPPLY");

        // Mock an incompatibility with the module
        vm.mockCall(
            address(ROLES),
            abi.encodeWithSelector(OlympusRoles.VERSION.selector),
            abi.encode(version_, 0)
        );
        _expectRevert_wrongModuleVersion();

        bunniManager.configureDependencies();
    }

    function test_configureDependencies_mintrVersionReverts(uint8 version_) public {
        vm.assume(version_ != MINTR_VERSION);

        Keycode[] memory expectedDependencies = new Keycode[](5);
        expectedDependencies[0] = toKeycode("ROLES");
        expectedDependencies[1] = toKeycode("TRSRY");
        expectedDependencies[2] = toKeycode("PRICE");
        expectedDependencies[3] = toKeycode("MINTR");
        expectedDependencies[4] = toKeycode("SPPLY");

        // Mock an incompatibility with the module
        vm.mockCall(
            address(MINTR),
            abi.encodeWithSelector(OlympusMinter.VERSION.selector),
            abi.encode(version_, 0)
        );
        _expectRevert_wrongModuleVersion();

        bunniManager.configureDependencies();
    }

    function test_configureDependencies_spplyVersionReverts(uint8 version_) public {
        vm.assume(version_ != MINTR_VERSION);

        Keycode[] memory expectedDependencies = new Keycode[](5);
        expectedDependencies[0] = toKeycode("ROLES");
        expectedDependencies[1] = toKeycode("TRSRY");
        expectedDependencies[2] = toKeycode("PRICE");
        expectedDependencies[3] = toKeycode("MINTR");
        expectedDependencies[4] = toKeycode("SPPLY");

        // Mock an incompatibility with the module
        vm.mockCall(
            address(SPPLY),
            abi.encodeWithSelector(OlympusSupply.VERSION.selector),
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
        Keycode SPPLY_KEYCODE = toKeycode("SPPLY");

        Permissions[] memory expectedPermissions = new Permissions[](14);
        expectedPermissions[0] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        expectedPermissions[1] = Permissions(
            TRSRY_KEYCODE,
            TRSRY.increaseWithdrawApproval.selector
        );
        expectedPermissions[2] = Permissions(
            TRSRY_KEYCODE,
            TRSRY.decreaseWithdrawApproval.selector
        );
        expectedPermissions[3] = Permissions(TRSRY_KEYCODE, TRSRY.addAsset.selector);
        expectedPermissions[4] = Permissions(TRSRY_KEYCODE, TRSRY.addAssetLocation.selector);
        expectedPermissions[5] = Permissions(TRSRY_KEYCODE, TRSRY.removeAssetLocation.selector);
        expectedPermissions[6] = Permissions(TRSRY_KEYCODE, TRSRY.categorize.selector);
        expectedPermissions[7] = Permissions(PRICE_KEYCODE, PRICE.addAsset.selector);
        expectedPermissions[8] = Permissions(PRICE_KEYCODE, PRICE.removeAsset.selector);
        expectedPermissions[9] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        expectedPermissions[10] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        expectedPermissions[11] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        expectedPermissions[12] = Permissions(MINTR_KEYCODE, MINTR.decreaseMintApproval.selector);
        expectedPermissions[13] = Permissions(SPPLY_KEYCODE, SPPLY.execOnSubmodule.selector);

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
        _expectRevert_poolNotFound(ohmAddress);

        vm.prank(policy);
        bunniManager.registerPool(ohmAddress);
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
        IBunniToken deployedToken = bunniManager.deployPoolToken(address(pool));

        _expectRevert_tokenDeployed(address(pool), address(deployedToken));

        // Register the pool
        vm.prank(policy);
        bunniManager.registerPool(address(pool));
    }

    function test_registerPool_usdcPriceUnsetReverts() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Install a new policy
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniLens(bunniLensAddress);

        // Mock an error when getting the price
        _mockGetPriceReverts(usdcAddress);

        _expectRevert_priceZero(usdcAddress);

        vm.prank(policy);
        newBunniManager.registerPool(address(pool));
    }

    function test_registerPool_ohmPriceUnsetReverts() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Install a new policy
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniLens(bunniLensAddress);

        // Mock an error when getting the price
        _mockGetPriceReverts(ohmAddress);

        _expectRevert_priceZero(ohmAddress);

        vm.prank(policy);
        newBunniManager.registerPool(address(pool));
    }

    function test_registerPool() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployPoolToken(address(pool));

        // Install a new policy
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniLens(bunniLensAddress);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PoolTokenRegistered(address(pool), address(deployedToken));

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

        // Check that the token has NOT been added to PRICEv2
        PRICEv2.Asset memory priceAsset = PRICE.getAssetData(address(newDeployedToken));
        assertFalse(priceAsset.approved);

        // Check that the token has NOT been added to TRSRY
        TRSRYv1_1.Asset memory trsryAsset = TRSRY.getAssetData(address(newDeployedToken));
        assertFalse(trsryAsset.approved);

        // Check that the token has NOT been added to the BunniSupply submodule
        uint256 supplySubmoduleBunniTokenCount = supplySubmoduleBunni.bunniTokenCount();
        assertEq(supplySubmoduleBunniTokenCount, 0);

        // Check that the token is NOT included in SPPLY metrics
        uint256 polo = SPPLY.getSupplyByCategory(toSupplyCategory("protocol-owned-liquidity"));
        assertEq(polo, 0);
    }

    function test_registerPool_multiple() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployPoolToken(address(pool));

        // Create a new pool with an overlapping underlying token
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        _mockGetPrice(address(dai), 1e18);
        IUniswapV3Pool newPool = IUniswapV3Pool(
            uniswapFactory.createPool(usdcAddress, address(dai), POOL_FEE)
        );
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Deploy the second token
        vm.prank(policy);
        IBunniToken deployedTokenTwo = bunniManager.deployPoolToken(address(newPool));

        // Install a new policy
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniLens(bunniLensAddress);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PoolTokenRegistered(address(pool), address(deployedToken));

        // Register the pool with the new policy
        vm.prank(policy);
        newBunniManager.registerPool(address(pool));

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PoolTokenRegistered(address(newPool), address(deployedTokenTwo));

        // Register the new pool with the new policy
        vm.prank(policy);
        newBunniManager.registerPool(address(newPool));

        // Check that the pools are registered
        uint256 poolCount = newBunniManager.poolCount();
        assertEq(poolCount, 2);
        address poolOne = newBunniManager.pools(0);
        assertEq(poolOne, address(pool));
        address poolTwo = newBunniManager.pools(1);
        assertEq(poolTwo, address(newPool));
    }

    // [X] deployPoolToken
    //  [X] caller is unauthorized
    //  [X] bunniHub not set
    //  [X] token already deployed
    //  [X] not a Uniswap V3 pool
    //  [X] deploys and returns token
    //  [X] reverts when inactive
    //  [X] reverts if either asset price not defined
    //  [X] handles different pool fees

    function test_deployPoolToken_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.deployPoolToken(address(pool));
    }

    function test_deployPoolToken_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.deployPoolToken(address(pool));
    }

    function test_deployPoolToken_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.deployPoolToken(address(pool));
    }

    function test_deployPoolToken_invalidPoolReverts() public {
        _expectRevert_poolNotFound(ohmAddress);

        vm.prank(policy);
        bunniManager.deployPoolToken(ohmAddress);
    }

    function test_deployPoolToken_usdcPriceUnsetReverts() public {
        _mockGetPriceReverts(usdcAddress);

        _expectRevert_priceZero(usdcAddress);

        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));
    }

    function test_deployPoolToken_ohmPriceUnsetReverts() public {
        _mockGetPriceReverts(ohmAddress);

        _expectRevert_priceZero(ohmAddress);

        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));
    }

    function test_deployPoolToken() public {
        // Recognise the emitted event
        vm.expectEmit(false, false, true, false);
        emit NewBunni(IBunniToken(address(0)), bytes32(0), pool, 0, 0);

        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployPoolToken(address(pool));

        // Check details of token
        assertEq(address(deployedToken.pool()), address(pool));
        assertEq(deployedToken.tickLower(), -1 * 887270);
        assertEq(deployedToken.tickUpper(), 887270);

        // Check that the pool is registered
        uint256 poolCount = bunniManager.poolCount();
        assertEq(poolCount, 1);
        address poolOne = bunniManager.pools(0);
        assertEq(poolOne, address(pool));

        // Check that the token has NOT been added to PRICEv2
        PRICEv2.Asset memory priceAsset = PRICE.getAssetData(address(deployedToken));
        assertFalse(priceAsset.approved);

        // Check that the token has NOT been added to TRSRY
        TRSRYv1_1.Asset memory trsryAsset = TRSRY.getAssetData(address(deployedToken));
        assertFalse(trsryAsset.approved);

        // Check that the token has NOT been added to the BunniSupply submodule
        uint256 supplySubmoduleBunniTokenCount = supplySubmoduleBunni.bunniTokenCount();
        assertEq(supplySubmoduleBunniTokenCount, 0);

        // Check that the token is NOT included in SPPLY metrics
        uint256 polo = SPPLY.getSupplyByCategory(toSupplyCategory("protocol-owned-liquidity"));
        assertEq(polo, 0);
    }

    function test_deployPoolToken_multiple() public {
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Create a new pool with an overlapping underlying token
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        _mockGetPrice(address(dai), 1e18);
        IUniswapV3Pool newPool = IUniswapV3Pool(
            uniswapFactory.createPool(usdcAddress, address(dai), POOL_FEE)
        );
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Deploy the second token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(newPool));

        // Check that the pools are registered
        uint256 poolCount = bunniManager.poolCount();
        assertEq(poolCount, 2);
        address poolOne = bunniManager.pools(0);
        assertEq(poolOne, address(pool));
        address poolTwo = bunniManager.pools(1);
        assertEq(poolTwo, address(newPool));
    }

    function test_deployPoolToken_duplicateReverts() public {
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployPoolToken(address(pool));

        _expectRevert_tokenDeployed(address(pool), address(deployedToken));

        // Deploy a second time
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));
    }

    function test_deployPoolToken_poolFee3000() public {
        // Create a pool with a different fee
        uint24 poolFee = 3000;
        IUniswapV3Pool poolTwo = IUniswapV3Pool(
            uniswapFactory.createPool(ohmAddress, usdcAddress, poolFee)
        );
        poolTwo.initialize(OHM_USDC_SQRTPRICEX96);

        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployPoolToken(address(poolTwo));

        int24 tick = _getTick(poolFee, true);

        // Check details of token
        assertEq(address(deployedToken.pool()), address(poolTwo));
        assertEq(deployedToken.tickLower(), -1 * tick);
        assertEq(deployedToken.tickUpper(), tick);

        // Check that the pool is registered
        uint256 poolCount = bunniManager.poolCount();
        assertEq(poolCount, 1);
        address poolOne = bunniManager.pools(0);
        assertEq(poolOne, address(poolTwo));

        // === Deposit === //
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        // Will revert if there is a problem
        vm.prank(policy);
        bunniManager.deposit(
            address(poolTwo),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );
    }

    function test_deployPoolToken_poolFee100() public {
        uint24 poolFee = 100;

        // 0.01% / 100 pool fee isn't enabled in UniswapV3Factory, so add it
        // Values from: https://support.uniswap.org/hc/en-us/articles/21069524840589-What-is-a-tick-when-providing-liquidity-
        uniswapFactory.enableFeeAmount(poolFee, 1);

        // Create a pool with a different fee
        IUniswapV3Pool poolTwo = IUniswapV3Pool(
            uniswapFactory.createPool(ohmAddress, usdcAddress, poolFee)
        );
        poolTwo.initialize(OHM_USDC_SQRTPRICEX96);

        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployPoolToken(address(poolTwo));

        int24 tick = _getTick(poolFee, true);

        // Check details of token
        assertEq(address(deployedToken.pool()), address(poolTwo));
        assertEq(deployedToken.tickLower(), -1 * tick);
        assertEq(deployedToken.tickUpper(), tick);

        // Check that the pool is registered
        uint256 poolCount = bunniManager.poolCount();
        assertEq(poolCount, 1);
        address poolOne = bunniManager.pools(0);
        assertEq(poolOne, address(poolTwo));

        // === Deposit === //
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        // Will revert if there is a problem
        vm.prank(policy);
        bunniManager.deposit(
            address(poolTwo),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );
    }

    // [X] activatePoolToken
    //  [X] reverts if caller is unauthorized
    //  [X] reverts if inactive
    //  [X] reverts if bunniHub not set
    //  [X] reverts if token not deployed
    //  [X] reverts if no liquidity
    //  [X] reverts if already registered with TRSRY
    //  [X] reverts if already registered with PRICE
    //  [X] reverts if already registered with SPPLY
    //  [X] success - registers with TRSRY, PRICE, SPPLY

    function test_activatePoolToken_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );
    }

    function test_activatePoolToken_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );
    }

    function test_activatePoolToken_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );
    }

    function test_activatePoolToken_tokenNotDeployedReverts() public {
        _expectRevert_poolNotFound(address(pool));

        vm.prank(policy);
        bunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );
    }

    function test_activatePoolToken_noLiquidityReverts() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_PoolHasNoLiquidity.selector,
            address(pool)
        );
        vm.expectRevert(err);

        vm.prank(policy);
        bunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );
    }

    function test_activatePoolToken_registeredWithTrsryLocationsReverts() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployPoolToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Register the asset with TRSRY
        address[] memory trsryLocations = new address[](1);
        trsryLocations[0] = treasuryAddress;
        vm.prank(writeTRSRY);
        TRSRY.addAsset(address(poolToken), trsryLocations);

        // Expect a revert
        _expectRevert_tokenActivated(address(pool), toKeycode("TRSRY"));

        vm.prank(policy);
        bunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );
    }

    function test_activatePoolToken_registeredWithPriceReverts() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployPoolToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Prepare parameters for PRICE
        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        {
            BunniPrice.BunniParams memory params = BunniPrice.BunniParams(
                address(bunniLens),
                TWAP_DEFAULT_MAX_DEVIATION_BPS,
                TWAP_DEFAULT_OBSERVATION_WINDOW
            );

            feeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.BNI"), // Subkeycode
                BunniPrice.getBunniTokenPrice.selector, // Selector
                abi.encode(params) // Params
            );
        }

        // Register the asset with PRICE
        vm.prank(writePRICE);
        PRICE.addAsset(
            address(poolToken), // address asset_
            false, // bool storeMovingAverage_
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds // Component[] memory feeds_
        );

        // Expect a revert
        _expectRevert_tokenActivated(address(pool), toKeycode("PRICE"));

        vm.prank(policy);
        bunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );
    }

    function test_activatePoolToken_registeredWithSupplyReverts() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployPoolToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Register the asset with SPPLY
        vm.prank(address(SPPLY));
        supplySubmoduleBunni.addBunniToken(address(poolToken), address(bunniLens), 100, 30);

        // Expect a revert
        _expectRevert_tokenActivated(address(pool), toKeycode("SPPLY"));

        vm.prank(policy);
        bunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );
    }

    function test_activatePoolToken_registeredTreasuryAsset() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployPoolToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Register the pool token in the TRSRY
        // This mimics the case where the token has been registered with the TRSRY (since it cannot be removed)
        address[] memory trsryLocations = new address[](0);
        vm.prank(writeTRSRY);
        TRSRY.addAsset(address(poolToken), trsryLocations);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PoolTokenActivated(address(pool), address(poolToken));

        vm.prank(policy);
        bunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );

        // Check that the token has been added to TRSRY
        OlympusTreasury.Asset memory trsryAsset = TRSRY.getAssetData(address(poolToken));
        assertTrue(trsryAsset.approved);
        assertEq(trsryAsset.locations.length, 1);
        assertEq(trsryAsset.locations[0], treasuryAddress);
        // Check that the token is categorized in TRSRY
        address[] memory trsryPolAssets = TRSRY.getAssetsByCategory(
            toTreasuryCategory("protocol-owned-liquidity")
        );
        assertEq(trsryPolAssets.length, 1);
        assertEq(trsryPolAssets[0], address(poolToken));

        // Check that the token has been added to PRICEv2
        PRICEv2.Asset memory priceAsset = PRICE.getAssetData(address(poolToken));
        assertTrue(priceAsset.approved);
        // Check that the price is non-zero
        assertTrue(PRICE.getPrice(address(poolToken)) > 0);

        // Check that the token is included in SPPLY metrics
        uint256 polo = SPPLY.getSupplyByCategory(toSupplyCategory("protocol-owned-liquidity"));
        assertTrue(polo > 0);
    }

    function test_activatePoolToken_categorizedTreasuryAsset() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployPoolToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Register the pool token in the TRSRY
        // This mimics the case where the token has been registered and categorized with the TRSRY (since it cannot be removed)
        address[] memory trsryLocations = new address[](0);
        vm.prank(writeTRSRY);
        TRSRY.addAsset(address(poolToken), trsryLocations);
        vm.prank(writeTRSRY);
        TRSRY.categorize(address(poolToken), toTreasuryCategory("protocol-owned-liquidity"));

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PoolTokenActivated(address(pool), address(poolToken));

        vm.prank(policy);
        bunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );

        // Check that the token has been added to TRSRY
        OlympusTreasury.Asset memory trsryAsset = TRSRY.getAssetData(address(poolToken));
        assertTrue(trsryAsset.approved);
        assertEq(trsryAsset.locations.length, 1);
        assertEq(trsryAsset.locations[0], treasuryAddress);
        // Check that the token is categorized in TRSRY
        address[] memory trsryPolAssets = TRSRY.getAssetsByCategory(
            toTreasuryCategory("protocol-owned-liquidity")
        );
        assertEq(trsryPolAssets.length, 1);
        assertEq(trsryPolAssets[0], address(poolToken));

        // Check that the token has been added to PRICEv2
        PRICEv2.Asset memory priceAsset = PRICE.getAssetData(address(poolToken));
        assertTrue(priceAsset.approved);
        // Check that the price is non-zero
        assertTrue(PRICE.getPrice(address(poolToken)) > 0);

        // Check that the token is included in SPPLY metrics
        uint256 polo = SPPLY.getSupplyByCategory(toSupplyCategory("protocol-owned-liquidity"));
        assertTrue(polo > 0);
    }

    function test_activatePoolToken() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployPoolToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PoolTokenActivated(address(pool), address(poolToken));

        vm.prank(policy);
        bunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );

        // Check that the token has been added to TRSRY
        OlympusTreasury.Asset memory trsryAsset = TRSRY.getAssetData(address(poolToken));
        assertTrue(trsryAsset.approved);
        assertEq(trsryAsset.locations.length, 1);
        assertEq(trsryAsset.locations[0], treasuryAddress);
        // Check that the token is categorized in TRSRY
        address[] memory trsryPolAssets = TRSRY.getAssetsByCategory(
            toTreasuryCategory("protocol-owned-liquidity")
        );
        assertEq(trsryPolAssets.length, 1);
        assertEq(trsryPolAssets[0], address(poolToken));

        // Check that the token has been added to PRICEv2
        PRICEv2.Asset memory priceAsset = PRICE.getAssetData(address(poolToken));
        assertTrue(priceAsset.approved);

        // Check that the price feed has the correct parameters
        PRICEv2.Component[] memory priceFeeds = abi.decode(priceAsset.feeds, (PRICEv2.Component[]));
        BunniPrice.BunniParams memory bunniParams = abi.decode(
            priceFeeds[0].params,
            (BunniPrice.BunniParams)
        );
        assertEq(bunniParams.bunniLens, address(bunniLens));
        assertEq(bunniParams.twapMaxDeviationsBps, TWAP_DEFAULT_MAX_DEVIATION_BPS);
        assertEq(bunniParams.twapObservationWindow, TWAP_DEFAULT_OBSERVATION_WINDOW);

        // Check that the price is non-zero
        assertTrue(PRICE.getPrice(address(poolToken)) > 0);

        // Check that the token is included in SPPLY metrics
        uint256 polo = SPPLY.getSupplyByCategory(toSupplyCategory("protocol-owned-liquidity"));
        assertTrue(polo > 0);

        // Check that the token has been added to the BunniSupply submodule
        (
            IBunniToken submoduleBunniToken_,
            BunniLens submoduleBunniLens_,
            uint16 submoduleTwapMaxDeviation_,
            uint32 submoduleTwapObservationWindow_
        ) = supplySubmoduleBunni.bunniTokens(0);
        assertEq(address(submoduleBunniToken_), address(poolToken));
        assertEq(address(submoduleBunniLens_), address(bunniLens));
        assertEq(submoduleTwapMaxDeviation_, TWAP_DEFAULT_MAX_DEVIATION_BPS);
        assertEq(submoduleTwapObservationWindow_, TWAP_DEFAULT_OBSERVATION_WINDOW);
    }

    function test_activatePoolToken_twapParameters() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployPoolToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PoolTokenActivated(address(pool), address(poolToken));

        // Set TWAP parameters
        uint16 twapMaxDeviationBps = 5000;
        uint32 twapObservationWindow = TWAP_DEFAULT_OBSERVATION_WINDOW + 1;

        _mockPoolObserve(
            address(pool),
            twapObservationWindow,
            OHM_USDC_TICK_CUMULATIVE_0,
            OHM_USDC_TICK_CUMULATIVE_1
        );

        vm.prank(policy);
        bunniManager.activatePoolToken(address(pool), twapMaxDeviationBps, twapObservationWindow);

        // Check that the token has been added to TRSRY
        OlympusTreasury.Asset memory trsryAsset = TRSRY.getAssetData(address(poolToken));
        assertTrue(trsryAsset.approved);
        assertEq(trsryAsset.locations.length, 1);
        assertEq(trsryAsset.locations[0], treasuryAddress);
        // Check that the token is categorized in TRSRY
        address[] memory trsryPolAssets = TRSRY.getAssetsByCategory(
            toTreasuryCategory("protocol-owned-liquidity")
        );
        assertEq(trsryPolAssets.length, 1);
        assertEq(trsryPolAssets[0], address(poolToken));

        // Check that the token has been added to PRICEv2
        PRICEv2.Asset memory priceAsset = PRICE.getAssetData(address(poolToken));
        assertTrue(priceAsset.approved);

        // Check that the price feed has the correct parameters
        PRICEv2.Component[] memory priceFeeds = abi.decode(priceAsset.feeds, (PRICEv2.Component[]));
        BunniPrice.BunniParams memory bunniParams = abi.decode(
            priceFeeds[0].params,
            (BunniPrice.BunniParams)
        );
        assertEq(bunniParams.bunniLens, address(bunniLens));
        assertEq(bunniParams.twapMaxDeviationsBps, twapMaxDeviationBps);
        assertEq(bunniParams.twapObservationWindow, twapObservationWindow);

        // Check that the price is non-zero
        assertTrue(PRICE.getPrice(address(poolToken)) > 0);

        // Check that the token is included in SPPLY metrics
        uint256 polo = SPPLY.getSupplyByCategory(toSupplyCategory("protocol-owned-liquidity"));
        assertTrue(polo > 0);

        // Check that the token has been added to the BunniSupply submodule
        (
            IBunniToken submoduleBunniToken_,
            BunniLens submoduleBunniLens_,
            uint16 submoduleTwapMaxDeviation_,
            uint32 submoduleTwapObservationWindow_
        ) = supplySubmoduleBunni.bunniTokens(0);
        assertEq(address(submoduleBunniToken_), address(poolToken));
        assertEq(address(submoduleBunniLens_), address(bunniLens));
        assertEq(submoduleTwapMaxDeviation_, twapMaxDeviationBps);
        assertEq(submoduleTwapObservationWindow_, twapObservationWindow);
    }

    // [X] deactivatePoolToken
    //  [X] reverts if caller is unauthorized
    //  [X] reverts if inactive
    //  [X] reverts if bunniHub not set
    //  [X] reverts if token not deployed
    //  [X] reverts if has liquidity
    //  [X] success - unregisters with TRSRY, PRICE, SPPLY
    //  [X] success if not registered with TRSRY, PRICE, SPPLY

    function test_deactivatePoolToken_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.deactivatePoolToken(address(pool));
    }

    function test_deactivatePoolToken_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.deactivatePoolToken(address(pool));
    }

    function test_deactivatePoolToken_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.deactivatePoolToken(address(pool));
    }

    function test_deactivatePoolToken_tokenNotDeployedReverts() public {
        _expectRevert_poolNotFound(address(pool));

        vm.prank(policy);
        bunniManager.deactivatePoolToken(address(pool));
    }

    function test_deactivatePoolToken_hasLiquidityReverts() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_PoolHasLiquidity.selector,
            address(pool)
        );
        vm.expectRevert(err);

        vm.prank(policy);
        bunniManager.deactivatePoolToken(address(pool));
    }

    function test_deactivatePoolToken() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployPoolToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Activate the token
        vm.prank(policy);
        bunniManager.activatePoolToken(
            address(pool),
            TWAP_DEFAULT_MAX_DEVIATION_BPS,
            TWAP_DEFAULT_OBSERVATION_WINDOW
        );

        // Withdraw
        vm.prank(policy);
        bunniManager.withdraw(address(pool), bunniTokenShares, SLIPPAGE_DEFAULT);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, false);
        emit PoolTokenDeactivated(address(pool), address(poolToken));

        // Deactivate
        vm.prank(policy);
        bunniManager.deactivatePoolToken(address(pool));

        // Check that the token has NOT been removed from TRSRY (since we can't actually do that)
        OlympusTreasury.Asset memory trsryAsset = TRSRY.getAssetData(address(poolToken));
        assertTrue(trsryAsset.approved);
        // Locations are removed
        assertEq(trsryAsset.locations.length, 0);
        // Cannot remove the category for the asset
        address[] memory trsryPolAssets = TRSRY.getAssetsByCategory(
            toTreasuryCategory("protocol-owned-liquidity")
        );
        assertEq(trsryPolAssets.length, 1);
        assertEq(trsryPolAssets[0], address(poolToken));

        // Check that the token has been removed from PRICEv2
        PRICEv2.Asset memory priceAsset = PRICE.getAssetData(address(poolToken));
        assertFalse(priceAsset.approved);

        // Check that the token is NOT included in SPPLY metrics
        uint256 polo = SPPLY.getSupplyByCategory(toSupplyCategory("protocol-owned-liquidity"));
        assertEq(polo, 0);
    }

    function test_deactivatePoolToken_ignoresUnregistered() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployPoolToken(address(pool));

        // Do NOT deposit or activate, so that TRSRY/PRICE/SPPLY are not registered

        // Recognise the emitted event
        vm.expectEmit(true, true, false, false);
        emit PoolTokenDeactivated(address(pool), address(poolToken));

        // Deactivate
        vm.prank(policy);
        bunniManager.deactivatePoolToken(address(pool));

        // Check that the token has NOT been added to TRSRY
        OlympusTreasury.Asset memory trsryAsset = TRSRY.getAssetData(address(poolToken));
        assertFalse(trsryAsset.approved);
        assertEq(trsryAsset.locations.length, 0);
        // Check that the token is NOT categorized in TRSRY
        address[] memory trsryPolAssets = TRSRY.getAssetsByCategory(
            toTreasuryCategory("protocol-owned-liquidity")
        );
        assertEq(trsryPolAssets.length, 0);

        // Check that the token has NOT been added to PRICEv2
        PRICEv2.Asset memory priceAsset = PRICE.getAssetData(address(poolToken));
        assertFalse(priceAsset.approved);

        // Check that the token is NOT included in SPPLY metrics
        uint256 polo = SPPLY.getSupplyByCategory(toSupplyCategory("protocol-owned-liquidity"));
        assertEq(polo, 0);
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
        bunniManager.deposit(address(pool), ohmAddress, 1e9, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_deposit_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.deposit(address(pool), ohmAddress, 1e9, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_deposit_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.deposit(address(pool), ohmAddress, 1e9, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_deposit_tokenNotDeployedReverts() public {
        _expectRevert_poolNotFound(address(pool));

        vm.prank(policy);
        bunniManager.deposit(address(pool), ohmAddress, 1e9, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_deposit_token0InsufficientBalanceReverts(uint256 token0Amount_) public {
        // Create a pool with non-OHM tokens
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        _mockGetPrice(address(dai), 1e18);
        IUniswapV3Pool newPool = IUniswapV3Pool(
            uniswapFactory.createPool(usdcAddress, address(dai), POOL_FEE)
        );
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Determine balances
        address token0 = newPool.token0();
        bool token0IsDai = token0 == address(dai);
        uint256 TOKEN0_DEPOSIT = token0IsDai ? 1e18 : 1e6;
        uint256 daiBalance = token0IsDai ? bound(token0Amount_, 0, 1e18 - 1) : 1e18;
        uint256 usdcBalance = token0IsDai ? 1e6 : bound(token0Amount_, 0, 1e6 - 1);

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(newPool));

        // Mint tokens to the TRSRY
        dai.mint(treasuryAddress, daiBalance);
        usdc.mint(treasuryAddress, usdcBalance);

        // Expect a revert
        _expectRevert_insufficientBalance(
            token0,
            TOKEN0_DEPOSIT,
            token0IsDai ? daiBalance : usdcBalance
        );

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(address(newPool), address(dai), 1e18, 1e6, SLIPPAGE_DEFAULT);
    }

    function test_deposit_token1InsufficientBalanceReverts(uint256 token1Amount_) public {
        // Create a pool with non-OHM tokens
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        _mockGetPrice(address(dai), 1e18);
        IUniswapV3Pool newPool = IUniswapV3Pool(
            uniswapFactory.createPool(usdcAddress, address(dai), POOL_FEE)
        );
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Determine balances
        address token0 = newPool.token0();
        bool token0IsDai = token0 == address(dai);
        uint256 TOKEN1_DEPOSIT = token0IsDai ? 1e6 : 1e18;
        uint256 daiBalance = token0IsDai ? 1e18 : bound(token1Amount_, 0, TOKEN1_DEPOSIT - 1);
        uint256 usdcBalance = token0IsDai ? bound(token1Amount_, 0, TOKEN1_DEPOSIT - 1) : 1e6;

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(newPool));

        // Mint tokens to the TRSRY
        dai.mint(treasuryAddress, daiBalance);
        usdc.mint(treasuryAddress, usdcBalance);

        // Expect a revert
        _expectRevert_insufficientBalance(
            newPool.token1(),
            TOKEN1_DEPOSIT,
            token0IsDai ? usdcBalance : daiBalance
        );

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(address(newPool), address(dai), 1e18, 1e6, SLIPPAGE_DEFAULT);
    }

    function test_deposit_nonOhmTokens_fuzz(uint256 usdcAmount_) public {
        uint256 usdcAmount = bound(usdcAmount_, 100e6, 1e12);
        uint256 daiAmount = usdcAmount.mulDiv(1e18, 1e6); // Same price, different decimal scale

        // Create a pool with non-OHM tokens
        MockERC20 dai = new MockERC20{salt: DAI_SALT}("DAI", "DAI", 18);
        _mockGetPrice(address(dai), 1e18);
        IUniswapV3Pool newPool = IUniswapV3Pool(
            uniswapFactory.createPool(usdcAddress, address(dai), POOL_FEE)
        );
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployPoolToken(address(newPool));

        // Mint tokens to the TRSRY
        dai.mint(treasuryAddress, daiAmount);
        usdc.mint(treasuryAddress, usdcAmount);
        uint256 ohmSupplyBefore = ohm.totalSupply();

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(newPool),
            address(dai),
            daiAmount,
            usdcAmount,
            SLIPPAGE_DEFAULT
        );

        // The tokens should have been deposited into TRSRY
        assertEq(bunniToken.balanceOf(treasuryAddress), bunniTokenShares);

        // No remaining balance in the policy
        assertEq(dai.balanceOf(bunniManagerAddress), 0);
        assertEq(usdc.balanceOf(bunniManagerAddress), 0);

        // No remaining balance in the bunniHub
        assertEq(dai.balanceOf(bunniHubAddress), 0);
        assertEq(usdc.balanceOf(bunniHubAddress), 0);

        // No OHM was minted
        assertEq(ohm.totalSupply(), ohmSupplyBefore);
    }

    function test_deposit_invalidUnderlyingTokenReverts() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Expect a revert
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_Params_InvalidUnderlyingToken.selector,
            address(wETH)
        );
        vm.expectRevert(err);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(address(pool), address(wETH), 1e9, 1e6, SLIPPAGE_DEFAULT);
    }

    function test_deposit_ohmToken_fuzz(uint256 amount_) public {
        uint256 amount = bound(amount_, 100e6, 1e12);
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployPoolToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);
        uint256 ohmSupplyBefore = ohm.totalSupply();

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // The tokens should have been deposited into TRSRY
        assertEq(bunniToken.balanceOf(treasuryAddress), bunniTokenShares);

        // No remaining balance in the policy
        assertEq(ohm.balanceOf(bunniManagerAddress), 0);
        assertEq(usdc.balanceOf(bunniManagerAddress), 0);

        // No remaining balance in the bunniHub
        assertEq(ohm.balanceOf(bunniHubAddress), 0);
        assertEq(usdc.balanceOf(bunniHubAddress), 0);

        // OHM was minted
        // The exact amount of OHM is only known at run-time (due to slippage)
        (uint112 reserve0, uint112 reserve1) = bunniLens.getReserves(
            _getBunniKey(pool, bunniToken)
        );
        uint256 ohmReserve = pool.token0() == ohmAddress ? reserve0 : reserve1;

        // Tolerant of rounding
        assertApproxEqAbs(ohm.totalSupply(), ohmSupplyBefore + ohmReserve, 1);
    }

    function test_deposit_slippage_fuzz(uint256 amount_, uint256 slippage_) public {
        uint16 slippage = uint16(bound(slippage_, 50, 500)); // 0.5 - 5%

        /**
         * Get a random amount of OHM to deposit
         * Calculate the amount of USDC to match that (so they are in proportion),
         * with the slippage parameter applied.
         */
        uint256 amount = bound(amount_, 100e6, 1e12);
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18).mulDiv(
            SLIPPAGE_MAX - slippage,
            SLIPPAGE_MAX
        );
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployPoolToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);
        uint256 ohmSupplyBefore = ohm.totalSupply();

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            slippage
        );

        // The tokens should have been deposited into TRSRY
        assertEq(bunniToken.balanceOf(treasuryAddress), bunniTokenShares);

        // No remaining balance in the policy
        assertEq(ohm.balanceOf(bunniManagerAddress), 0);
        assertEq(usdc.balanceOf(bunniManagerAddress), 0);

        // No remaining balance in the bunniHub
        assertEq(ohm.balanceOf(bunniHubAddress), 0);
        assertEq(usdc.balanceOf(bunniHubAddress), 0);

        // OHM was minted
        // The exact amount of OHM is only known at run-time (due to slippage)
        (uint112 reserve0, uint112 reserve1) = bunniLens.getReserves(
            _getBunniKey(pool, bunniToken)
        );
        uint256 ohmReserve = pool.token0() == ohmAddress ? reserve0 : reserve1;
        uint256 usdcReserve = pool.token0() == usdcAddress ? reserve0 : reserve1;

        // Tolerant of rounding
        assertApproxEqAbs(ohm.totalSupply(), ohmSupplyBefore + ohmReserve, 1);
        assertApproxEqAbs(usdcReserve, USDC_DEPOSIT, 1);
    }

    function test_deposit_invalidSlippage() public {
        uint256 OHM_DEPOSIT = 1000e9;
        uint256 USDC_DEPOSIT = OHM_DEPOSIT.mulDiv(1e6, 1e9).mulDiv(OHM_USDC_PRICE, 1e18);

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Set up the invalid slippage
        uint16 slippage = SLIPPAGE_MAX + 1;
        _expectRevert_invalidSlippage(slippage);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(address(pool), ohmAddress, OHM_DEPOSIT, USDC_DEPOSIT, slippage);
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
        uint256 USDC_DEPOSIT = (10e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
        uint256 OHM_DEPOSIT = 10e9;

        // Deploy the token
        vm.prank(policy);
        IBunniToken token = bunniManager.deployPoolToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Withdraw
        uint256 bunniTokenSharesToWithdraw = bunniTokenShares * 2;

        _expectRevert_insufficientBalance(
            address(token),
            bunniTokenSharesToWithdraw,
            bunniTokenShares
        );

        vm.prank(policy);
        bunniManager.withdraw(address(pool), bunniTokenSharesToWithdraw, SLIPPAGE_DEFAULT);
    }

    function test_withdraw_nonOhmTokens(uint256 shareToWithdraw_) public {
        // Create a pool with non-OHM tokens
        MockERC20 dai = new MockERC20{salt: DAI_SALT}("DAI", "DAI", 18);
        _mockGetPrice(address(dai), 1e18);
        IUniswapV3Pool newPool = IUniswapV3Pool(
            uniswapFactory.createPool(usdcAddress, address(dai), POOL_FEE)
        );
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Deploy the token
        vm.prank(policy);
        IBunniToken token = bunniManager.deployPoolToken(address(newPool));

        // Mint tokens to the TRSRY
        dai.mint(treasuryAddress, 1e18);
        usdc.mint(treasuryAddress, 1e6);

        uint256 DAI_DEPOSIT = 1e18;
        uint256 USDC_DEPOSIT = 1e6;

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(newPool),
            address(dai),
            DAI_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );
        uint256 bunniTokenSharesToWithdraw = bound(shareToWithdraw_, 1e9, bunniTokenShares);

        // Withdraw
        uint256 usdcBalanceBefore = usdc.balanceOf(treasuryAddress);
        uint256 daiBalanceBefore = dai.balanceOf(treasuryAddress);
        uint256 ohmSupplyBefore = ohm.totalSupply();

        vm.prank(policy);
        bunniManager.withdraw(address(newPool), bunniTokenSharesToWithdraw, SLIPPAGE_DEFAULT);

        // Check that:
        // withdrawn DAU has been returned to TRSRY
        // withdrawn USDC has been returned to TRSRY
        // OHM supply did not change
        uint256 usdcBalanceAfter = usdc.balanceOf(treasuryAddress);
        uint256 daiBalanceAfter = dai.balanceOf(treasuryAddress);

        assertApproxEqAbs(
            usdcBalanceAfter - usdcBalanceBefore,
            USDC_DEPOSIT.mulDiv(bunniTokenSharesToWithdraw, bunniTokenShares),
            1e3
        );
        assertApproxEqAbs(
            daiBalanceAfter - daiBalanceBefore,
            DAI_DEPOSIT.mulDiv(bunniTokenSharesToWithdraw, bunniTokenShares),
            1e6
        );
        assertEq(ohm.totalSupply(), ohmSupplyBefore);

        // Policy does not contain any balances
        assertEq(usdc.balanceOf(bunniManagerAddress), 0);
        assertEq(dai.balanceOf(bunniManagerAddress), 0);
        assertEq(ohm.balanceOf(bunniManagerAddress), 0);
        assertEq(token.balanceOf(bunniManagerAddress), 0);
    }

    function test_withdraw_ohmToken(uint256 shareToWithdraw_) public {
        uint256 USDC_DEPOSIT = (10e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
        uint256 OHM_DEPOSIT = 10e9;

        // Deploy the token
        vm.prank(policy);
        IBunniToken token = bunniManager.deployPoolToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );
        uint256 bunniTokenSharesToWithdraw = bound(shareToWithdraw_, 1e9, bunniTokenShares);

        // Withdraw
        uint256 usdcBalanceBefore = usdc.balanceOf(treasuryAddress);
        uint256 ohmSupplyBefore = ohm.totalSupply();

        vm.prank(policy);
        bunniManager.withdraw(address(pool), bunniTokenSharesToWithdraw, SLIPPAGE_DEFAULT);

        // Check that:
        // withdrawn USDC has been returned to TRSRY
        // withdrawn OHM has been burnt
        uint256 usdcBalanceAfter = usdc.balanceOf(treasuryAddress);
        uint256 ohmSupplyAfter = ohm.totalSupply();

        assertApproxEqAbs(
            usdcBalanceAfter - usdcBalanceBefore,
            USDC_DEPOSIT.mulDiv(bunniTokenSharesToWithdraw, bunniTokenShares),
            1e4
        );
        assertApproxEqAbs(
            ohmSupplyBefore - ohmSupplyAfter,
            OHM_DEPOSIT.mulDiv(bunniTokenSharesToWithdraw, bunniTokenShares),
            1e3
        );

        // Policy does not contain any balances
        assertEq(usdc.balanceOf(bunniManagerAddress), 0);
        assertEq(ohm.balanceOf(bunniManagerAddress), 0);
        assertEq(token.balanceOf(bunniManagerAddress), 0);
    }

    function test_withdraw_invalidSlippage() public {
        uint256 OHM_DEPOSIT = 1000e9;
        uint256 USDC_DEPOSIT = OHM_DEPOSIT.mulDiv(1e6, 1e9).mulDiv(OHM_USDC_PRICE, 1e18);

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 shares = bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Set up the incorrect slippage
        uint16 slippage = SLIPPAGE_MAX + 1;
        _expectRevert_invalidSlippage(slippage);

        // Withdraw
        vm.prank(policy);
        bunniManager.withdraw(address(pool), shares, slippage);
    }

    // [X] getPoolToken
    //  [X] bunniHub is not set
    //  [X] token is not deployed
    //  [X] returns token struct
    //  [X] returns even if inactive

    function test_getPoolToken_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        newBunniManager.getPoolToken(address(pool));
    }

    function test_getPoolToken_tokenNotDeployedReverts() public {
        _expectRevert_poolNotFound(address(pool));

        bunniManager.getPoolToken(address(pool));
    }

    function test_getPoolToken() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Get the token
        IBunniToken token = bunniManager.getPoolToken(address(pool));

        // Check return value
        assertEq(address(token.pool()), address(pool));
        assertEq(token.tickLower(), int24(-1 * TICK));
        assertEq(token.tickUpper(), TICK);
    }

    function test_getPoolToken_inactive() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Disable the policy
        kernel.executeAction(Actions.DeactivatePolicy, bunniManagerAddress);

        // Get the token
        IBunniToken token = bunniManager.getPoolToken(address(pool));

        // Check return value
        assertEq(address(token.pool()), address(pool));
        assertEq(token.tickLower(), int24(-1 * TICK));
        assertEq(token.tickUpper(), TICK);
    }

    // [X] getPoolTokenBalance
    //  [X] bunniHub is not set
    //  [X] token is not deployed
    //  [X] returns token balance
    //  [X] returns even if inactive

    function test_getPoolTokenBalance_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        newBunniManager.getPoolTokenBalance(address(pool));
    }

    function test_getPoolTokenBalance_tokenNotDeployedReverts() public {
        _expectRevert_poolNotFound(address(pool));

        bunniManager.getPoolTokenBalance(address(pool));
    }

    function test_getPoolTokenBalance_zeroBalance() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Get the token
        uint256 balance = bunniManager.getPoolTokenBalance(address(pool));

        // Check return value
        assertEq(balance, 0);
    }

    function test_getPoolTokenBalance_fuzz(uint256 amount_) public {
        uint256 amount = bound(amount_, 100e6, 1e12);
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Check that the value is consistent
        uint256 balance = bunniManager.getPoolTokenBalance(address(pool));
        assertEq(balance, bunniTokenShares);
    }

    function test_getPoolTokenBalance_inactive() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Disable the policy
        kernel.executeAction(Actions.DeactivatePolicy, bunniManagerAddress);

        // Check that the value is consistent
        uint256 balance = bunniManager.getPoolTokenBalance(address(pool));
        assertEq(balance, bunniTokenShares);
    }

    // [X] setBunniLens
    //  [X] caller is unauthorized
    //  [X] reverts if the hub address does not match
    //  [X] zero address
    //  [X] sets bunniHub variable
    //  [X] works if inactive

    function test_setBunniLens_unauthorizedReverts() public {
        // Create a new BunniHub
        BunniHub newBunniHub = new BunniHub(
            uniswapFactory,
            bunniManagerAddress,
            0 // No protocol fee
        );
        BunniLens newBunniLens = new BunniLens(newBunniHub);

        _expectRevert_unauthorized();

        // Call as an unauthorized user
        vm.prank(alice);
        bunniManager.setBunniLens(address(newBunniLens));
    }

    function test_setBunniLens_zeroAddressReverts() public {
        _expectRevert_invalidAddress(address(0));

        // Call with a zero address
        vm.prank(policy);
        bunniManager.setBunniLens(address(0));
    }

    function test_setBunniLens_bunniHubZeroReverts() public {
        // Create a new BunniLens
        BunniLens newBunniLens = new BunniLens(BunniHub(address(0)));

        _expectRevert_invalidAddress(address(newBunniLens));

        // Call
        vm.prank(policy);
        bunniManager.setBunniLens(address(newBunniLens));
    }

    function test_setBunniLens() public {
        // Create a new BunniHub
        BunniHub newBunniHub = new BunniHub(
            uniswapFactory,
            bunniManagerAddress,
            0 // No protocol fee
        );
        BunniLens newBunniLens = new BunniLens(newBunniHub);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit BunniLensSet(address(newBunniHub), address(newBunniLens));

        // Call
        vm.prank(policy);
        bunniManager.setBunniLens(address(newBunniLens));

        // Check that the values have been updated
        assertEq(address(bunniManager.bunniHub()), address(newBunniHub));
        assertEq(address(bunniManager.bunniLens()), address(newBunniLens));
    }

    function test_setBunniLens_inactive() public {
        // Create a new BunniHub
        BunniHub newBunniHub = new BunniHub(
            uniswapFactory,
            bunniManagerAddress,
            0 // No protocol fee
        );
        BunniLens newBunniLens = new BunniLens(newBunniHub);

        // Disable the policy
        kernel.executeAction(Actions.DeactivatePolicy, bunniManagerAddress);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit BunniLensSet(address(newBunniHub), address(newBunniLens));

        // Call
        vm.prank(policy);
        bunniManager.setBunniLens(address(newBunniLens));

        // Check that the value has been updated
        assertEq(address(bunniManager.bunniHub()), address(newBunniHub));
        assertEq(address(bunniManager.bunniLens()), address(newBunniLens));
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
        newBunniManager.setBunniOwner(alice);
    }

    function test_setBunniOwner() public {
        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit BunniHubOwnerSet(address(bunniHub), alice);

        // Call
        vm.prank(policy);
        bunniManager.setBunniOwner(alice);

        // Check that the value has been updated
        assertEq(bunniManager.bunniHub().owner(), alice);

        // Attempt to perform an action on the BunniHub as the old owner
        vm.expectRevert(bytes("UNAUTHORIZED")); // Reverts with "UNAUTHORIZED" from the BunniHub (not Bophades)
        vm.prank(policy);
        bunniHub.setProtocolFee(1);

        // Attempt to perform an action on the BunniHub as the new owner
        vm.prank(alice);
        bunniHub.setProtocolFee(1);
        assertEq(bunniHub.protocolFee(), 1);
    }

    function test_setBunniOwner_inactive() public {
        // Disable the policy
        kernel.executeAction(Actions.DeactivatePolicy, bunniManagerAddress);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit BunniHubOwnerSet(address(bunniHub), alice);

        // Call
        vm.prank(policy);
        bunniManager.setBunniOwner(alice);

        // Check that the value has been updated
        assertEq(bunniManager.bunniHub().owner(), alice);

        // Attempt to perform an action on the BunniHub as the old owner
        vm.expectRevert(bytes("UNAUTHORIZED")); // Reverts with "UNAUTHORIZED" from the BunniHub (not Bophades)
        vm.prank(policy);
        bunniHub.setProtocolFee(1);

        // Attempt to perform an action on the BunniHub as the new owner
        vm.prank(alice);
        bunniHub.setProtocolFee(1);
        assertEq(bunniHub.protocolFee(), 1);
    }

    // [X] harvest
    //  [X] reverts if bunniHub is not set
    //  [X] reverts when inactive
    //  [X] reverts if sufficient time has not elapsed
    //  [X] can be called by anyone
    //  [X] harvest compounds fees to the pool
    //  [X] harvest compounds fees to the pool, multiple pools
    //  [X] harvest reward paid matches currentHarvestReward
    //  [X] harvest forces recalculation of fees
    //  [X] ignores pools with no position

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

    function test_harvest_noPosition() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // No deposit

        // Warp
        vm.warp(block.timestamp + HARVEST_FREQUENCY);

        // Harvest does not revert in order to avoid blocking the harvest of other pools
        vm.prank(alice);
        bunniManager.harvest();
    }

    function test_harvest_unpermissioned() public {
        uint256 USDC_DEPOSIT = (10_000_000e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
        uint256 OHM_DEPOSIT = 10_000_000e9;

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Warp forward
        vm.warp(block.timestamp + HARVEST_FREQUENCY);

        // Call
        vm.prank(alice);
        bunniManager.harvest();
    }

    function test_harvest() public {
        IBunniToken token;
        {
            uint256 USDC_DEPOSIT = (10_000_000e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
            uint256 OHM_DEPOSIT = 10_000_000e9;

            // Deploy the token
            vm.prank(policy);
            token = bunniManager.deployPoolToken(address(pool));

            // Mint the non-OHM token to the TRSRY
            usdc.mint(treasuryAddress, USDC_DEPOSIT);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(pool),
                ohmAddress,
                OHM_DEPOSIT,
                USDC_DEPOSIT,
                SLIPPAGE_DEFAULT
            );
        }

        // Perform the swap
        {
            uint256 swapAmountUsdcIn = 1_000_000e6;

            // Mint USDC into another wallet
            usdc.mint(alice, swapAmountUsdcIn);

            uint256 swapOneOhmMinimum = swapAmountUsdcIn
                .mulDiv(1e18, 1e6)
                .mulDiv(1e18, OHM_USDC_PRICE)
                .mulDiv(1e9, 1e18)
                .mulDiv(95, 100);
            _swap(usdcAddress, ohmAddress, alice, swapAmountUsdcIn, swapOneOhmMinimum, POOL_FEE);

            // And reverse
            uint256 swapTwoUsdcMinimum = swapOneOhmMinimum
                .mulDiv(1e18, 1e9)
                .mulDiv(OHM_USDC_PRICE, 1e18)
                .mulDiv(1e6, 1e18)
                .mulDiv(95, 100);
            _swap(ohmAddress, usdcAddress, alice, swapOneOhmMinimum, swapTwoUsdcMinimum, POOL_FEE);
        }

        // Store balances for comparison
        _storeTokenBalance(treasuryAddress, usdcAddress);
        _storeTokenBalance(treasuryAddress, ohmAddress);
        _storeTokenBalance(policy, usdcAddress);
        _storeTokenBalance(policy, ohmAddress);
        _storeTokenBalance(alice, usdcAddress);
        _storeTokenBalance(alice, ohmAddress);

        // Determine the reward to be given
        uint256 currentReward;
        uint256 usdcFeeAmountBefore;
        uint256 ohmFeeAmountBefore;
        {
            _recalculateFees(pool);
            currentReward = bunniManager.getCurrentHarvestReward();

            (uint256 usdcFeeAmountBefore_, uint256 ohmFeeAmountBefore_) = _getPoolFees(
                token,
                usdcAddress
            );
            usdcFeeAmountBefore = usdcFeeAmountBefore_;
            ohmFeeAmountBefore = ohmFeeAmountBefore_;
        }

        // Get current liquidity
        uint128 liquidityBefore = pool.liquidity();

        // Harvest
        {
            // Warp forward
            vm.warp(block.timestamp + HARVEST_FREQUENCY);

            vm.prank(alice);
            bunniManager.harvest();
        }

        // Check that there are less owed fees
        {
            _recalculateFees(pool);
            (uint256 usdcFeeAmount, uint256 ohmFeeAmount) = _getPoolFees(token, usdcAddress);

            assertLt(usdcFeeAmount, usdcFeeAmountBefore, "post-harvest USDC fees should be less");
            assertLt(ohmFeeAmount, ohmFeeAmountBefore, "post-harvest OHM fees should be less");
        }

        // Pool liquidity has increased
        assertGt(pool.liquidity(), liquidityBefore, "post-harvest liquidity did not increase");

        // OHM, USDC not transferred to any of the wallets
        assertEq(
            usdc.balanceOf(treasuryAddress),
            _getStoredTokenBalance(treasuryAddress, usdcAddress),
            "TRSRY balance of USDC should be same"
        );
        assertEq(
            ohm.balanceOf(treasuryAddress),
            _getStoredTokenBalance(treasuryAddress, ohmAddress),
            "TRSRY balance of OHM should be same"
        );
        assertEq(usdc.balanceOf(bunniHubAddress), 0, "bunniHub balance of USDC should be 0");
        assertEq(ohm.balanceOf(bunniHubAddress), 0, "bunniHub balance of OHM should be 0");
        assertEq(
            usdc.balanceOf(bunniManagerAddress),
            0,
            "bunniManager balance of USDC should be 0"
        );
        assertEq(ohm.balanceOf(bunniManagerAddress), 0, "bunniManager balance of OHM should be 0");
        assertEq(
            usdc.balanceOf(policy),
            _getStoredTokenBalance(policy, usdcAddress),
            "policy wallet balance of USDC should be same"
        );
        assertEq(
            ohm.balanceOf(policy),
            _getStoredTokenBalance(policy, ohmAddress),
            "policy wallet balance of OHM should be same"
        );
        assertEq(
            usdc.balanceOf(alice),
            _getStoredTokenBalance(alice, usdcAddress),
            "alice wallet balance of USDC should be same"
        );

        // Caller received the OHM reward
        assertEq(
            ohm.balanceOf(alice),
            _getStoredTokenBalance(alice, ohmAddress) + currentReward,
            "alice wallet balance of OHM should have increased due to reward"
        );

        // lastHarvest updated
        assertEq(
            bunniManager.lastHarvest(),
            block.timestamp,
            "lastHarvest should be updated to the current timestamp"
        );
    }

    function test_harvest_multiplePools() public {
        // Create a new pool
        IUniswapV3Pool poolTwo;
        {
            // Creates a new pool with a different fee
            poolTwo = IUniswapV3Pool(uniswapFactory.createPool(usdcAddress, ohmAddress, 3000));
            poolTwo.initialize(OHM_USDC_SQRTPRICEX96);
        }

        // Deploy the token
        IBunniToken token;
        IBunniToken tokenTwo;
        {
            // Deploy the token
            vm.prank(policy);
            token = bunniManager.deployPoolToken(address(pool));
            vm.prank(policy);
            tokenTwo = bunniManager.deployPoolToken(address(poolTwo));
        }

        // Perform the deposit
        {
            uint256 USDC_DEPOSIT = (10_000_000e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
            uint256 OHM_DEPOSIT = 10_000_000e9;

            // Mint the non-OHM token to the TRSRY
            usdc.mint(treasuryAddress, USDC_DEPOSIT * 2);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(pool),
                ohmAddress,
                OHM_DEPOSIT,
                USDC_DEPOSIT,
                SLIPPAGE_DEFAULT
            );

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(poolTwo),
                ohmAddress,
                OHM_DEPOSIT,
                USDC_DEPOSIT,
                SLIPPAGE_DEFAULT
            );
        }

        // Perform the swap on the first pool
        {
            uint256 swapAmountUsdcIn = 100_000e6;

            // Mint USDC into another wallet
            usdc.mint(alice, swapAmountUsdcIn);

            uint256 swapOneOhmMinimum = swapAmountUsdcIn
                .mulDiv(1e18, 1e6)
                .mulDiv(1e18, OHM_USDC_PRICE)
                .mulDiv(1e9, 1e18)
                .mulDiv(95, 100);
            _swap(usdcAddress, ohmAddress, alice, swapAmountUsdcIn, swapOneOhmMinimum, POOL_FEE);

            // And reverse
            uint256 swapTwoUsdcMinimum = swapOneOhmMinimum
                .mulDiv(1e18, 1e9)
                .mulDiv(OHM_USDC_PRICE, 1e18)
                .mulDiv(1e6, 1e18)
                .mulDiv(95, 100);
            _swap(ohmAddress, usdcAddress, alice, swapOneOhmMinimum, swapTwoUsdcMinimum, POOL_FEE);
        }

        // Perform the swap on the second pool
        {
            uint256 swapAmountUsdcIn = 1_000_000e6;
            uint24 poolFee = 3000;

            // Mint USDC into another wallet
            usdc.mint(alice, swapAmountUsdcIn);

            uint256 swapOneOhmMinimum = swapAmountUsdcIn
                .mulDiv(1e18, 1e6)
                .mulDiv(1e18, OHM_USDC_PRICE)
                .mulDiv(1e9, 1e18)
                .mulDiv(95, 100);
            _swap(usdcAddress, ohmAddress, alice, swapAmountUsdcIn, swapOneOhmMinimum, poolFee);

            // And reverse
            uint256 swapTwoUsdcMinimum = swapOneOhmMinimum
                .mulDiv(1e18, 1e9)
                .mulDiv(OHM_USDC_PRICE, 1e18)
                .mulDiv(1e6, 1e18)
                .mulDiv(95, 100);
            _swap(ohmAddress, usdcAddress, alice, swapOneOhmMinimum, swapTwoUsdcMinimum, poolFee);
        }

        // Store balances for comparison
        _storeTokenBalance(treasuryAddress, usdcAddress);
        _storeTokenBalance(treasuryAddress, ohmAddress);
        _storeTokenBalance(policy, usdcAddress);
        _storeTokenBalance(policy, ohmAddress);
        _storeTokenBalance(alice, usdcAddress);
        _storeTokenBalance(alice, ohmAddress);

        // Determine the reward to be given
        uint256 currentReward;
        uint256 poolOneUsdcFeeAmountBefore;
        uint256 poolOneOhmFeeAmountBefore;
        uint256 poolTwoUsdcFeeAmountBefore;
        uint256 poolTwoOhmFeeAmountBefore;
        {
            _recalculateFees(pool);
            _recalculateFees(poolTwo);
            currentReward = bunniManager.getCurrentHarvestReward();

            (uint256 poolOneUsdcFeeAmount, uint256 poolOneOhmFeeAmount) = _getPoolFees(
                token,
                usdcAddress
            );
            poolOneUsdcFeeAmountBefore = poolOneUsdcFeeAmount;
            poolOneOhmFeeAmountBefore = poolOneOhmFeeAmount;

            (uint256 poolTwoUsdcFeeAmount, uint256 poolTwoOhmFeeAmount) = _getPoolFees(
                tokenTwo,
                usdcAddress
            );
            poolTwoUsdcFeeAmountBefore = poolTwoUsdcFeeAmount;
            poolTwoOhmFeeAmountBefore = poolTwoOhmFeeAmount;
        }

        // Get current liquidity
        uint128 poolOneLiquidityBefore = pool.liquidity();
        uint128 poolTwoLiquidityBefore = poolTwo.liquidity();

        // Harvest
        {
            // Warp forward
            vm.warp(block.timestamp + HARVEST_FREQUENCY);

            vm.prank(alice);
            bunniManager.harvest();
        }

        // Check that there are less owed fees for the first pool
        {
            _recalculateFees(pool);
            (uint256 usdcFeeAmount, uint256 ohmFeeAmount) = _getPoolFees(token, usdcAddress);

            assertLt(
                usdcFeeAmount,
                poolOneUsdcFeeAmountBefore,
                "post-harvest USDC fees for pool one should be less"
            );
            assertLt(
                ohmFeeAmount,
                poolOneOhmFeeAmountBefore,
                "post-harvest OHM fees  for pool one should be less"
            );
        }

        // Check that there are less owed fees for the second pool
        {
            _recalculateFees(poolTwo);
            (uint256 usdcFeeAmount, uint256 ohmFeeAmount) = _getPoolFees(tokenTwo, usdcAddress);

            assertLt(
                usdcFeeAmount,
                poolTwoUsdcFeeAmountBefore,
                "post-harvest USDC fees for pool two should be less"
            );
            assertLt(
                ohmFeeAmount,
                poolTwoOhmFeeAmountBefore,
                "post-harvest OHM fees  for pool two should be less"
            );
        }

        // Pool liquidity has increased
        assertGt(
            pool.liquidity(),
            poolOneLiquidityBefore,
            "post-harvest liquidity for pool one did not increase"
        );
        assertGt(
            poolTwo.liquidity(),
            poolTwoLiquidityBefore,
            "post-harvest liquidity for pool two did not increase"
        );

        // OHM, USDC not transferred to any of the wallets
        assertEq(
            usdc.balanceOf(treasuryAddress),
            _getStoredTokenBalance(treasuryAddress, usdcAddress),
            "TRSRY balance of USDC should be same"
        );
        assertEq(
            ohm.balanceOf(treasuryAddress),
            _getStoredTokenBalance(treasuryAddress, ohmAddress),
            "TRSRY balance of OHM should be same"
        );
        assertEq(usdc.balanceOf(bunniHubAddress), 0, "bunniHub balance of USDC should be 0");
        assertEq(ohm.balanceOf(bunniHubAddress), 0, "bunniHub balance of OHM should be 0");
        assertEq(
            usdc.balanceOf(bunniManagerAddress),
            0,
            "bunniManager balance of USDC should be 0"
        );
        assertEq(ohm.balanceOf(bunniManagerAddress), 0, "bunniManager balance of OHM should be 0");
        assertEq(
            usdc.balanceOf(policy),
            _getStoredTokenBalance(policy, usdcAddress),
            "policy wallet balance of USDC should be same"
        );
        assertEq(
            ohm.balanceOf(policy),
            _getStoredTokenBalance(policy, ohmAddress),
            "policy wallet balance of OHM should be same"
        );
        assertEq(
            usdc.balanceOf(alice),
            _getStoredTokenBalance(alice, usdcAddress),
            "alice wallet balance of USDC should be same"
        );

        // Caller received the OHM reward
        assertEq(
            ohm.balanceOf(alice),
            _getStoredTokenBalance(alice, ohmAddress) + currentReward,
            "alice wallet balance of OHM should have increased due to reward"
        );

        // lastHarvest updated
        assertEq(bunniManager.lastHarvest(), block.timestamp);
    }

    function test_harvest_updateSwapFees() public {
        IBunniToken token;
        {
            uint256 USDC_DEPOSIT = (10_000_000e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
            uint256 OHM_DEPOSIT = 10_000_000e9;

            // Deploy the token
            vm.prank(policy);
            token = bunniManager.deployPoolToken(address(pool));

            // Mint the non-OHM token to the TRSRY
            usdc.mint(treasuryAddress, USDC_DEPOSIT);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(pool),
                ohmAddress,
                OHM_DEPOSIT,
                USDC_DEPOSIT,
                SLIPPAGE_DEFAULT
            );
        }

        // Perform the swap
        {
            uint256 swapAmountUsdcIn = 1_000_000e6;

            // Mint USDC into another wallet
            usdc.mint(alice, swapAmountUsdcIn);

            uint256 swapOneOhmMinimum = swapAmountUsdcIn
                .mulDiv(1e18, 1e6)
                .mulDiv(1e18, OHM_USDC_PRICE)
                .mulDiv(1e9, 1e18)
                .mulDiv(95, 100);
            _swap(usdcAddress, ohmAddress, alice, swapAmountUsdcIn, swapOneOhmMinimum, POOL_FEE);

            // And reverse
            uint256 swapTwoUsdcMinimum = swapOneOhmMinimum
                .mulDiv(1e18, 1e9)
                .mulDiv(OHM_USDC_PRICE, 1e18)
                .mulDiv(1e6, 1e18)
                .mulDiv(95, 100);
            _swap(ohmAddress, usdcAddress, alice, swapOneOhmMinimum, swapTwoUsdcMinimum, POOL_FEE);
        }

        // DO NOT recalculate fees, as we want to test if harvest() does it

        // Get current liquidity
        uint128 liquidityBefore = pool.liquidity();

        // Harvest
        {
            // Warp forward
            vm.warp(block.timestamp + HARVEST_FREQUENCY);

            vm.prank(alice);
            bunniManager.harvest();
        }

        // Pool liquidity has increased
        assertGt(pool.liquidity(), liquidityBefore, "post-harvest liquidity did not increase");
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
            uint256 USDC_DEPOSIT = (10_000_000e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
            uint256 OHM_DEPOSIT = 10_000_000e9;

            // Deploy the token
            vm.prank(policy);
            token = bunniManager.deployPoolToken(address(pool));

            // Mint the non-OHM token to the TRSRY
            usdc.mint(treasuryAddress, USDC_DEPOSIT);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(pool),
                ohmAddress,
                OHM_DEPOSIT,
                USDC_DEPOSIT,
                SLIPPAGE_DEFAULT
            );

            // Mint USDC into another wallet
            usdc.mint(alice, swapAmountUsdcIn);
        }

        // Perform the swap
        uint256 swapOneOhmMinimum;
        {
            swapOneOhmMinimum = swapAmountUsdcIn
                .mulDiv(1e18, 1e6)
                .mulDiv(1e18, OHM_USDC_PRICE)
                .mulDiv(1e9, 1e18)
                .mulDiv(95, 100);
            _swap(usdcAddress, ohmAddress, alice, swapAmountUsdcIn, swapOneOhmMinimum, POOL_FEE);
        }

        // And reverse
        {
            uint256 swapTwoUsdcMinimum = swapOneOhmMinimum
                .mulDiv(1e18, 1e9)
                .mulDiv(OHM_USDC_PRICE, 1e18)
                .mulDiv(1e6, 1e18)
                .mulDiv(95, 100);
            _swap(ohmAddress, usdcAddress, alice, swapOneOhmMinimum, swapTwoUsdcMinimum, POOL_FEE);
        }

        _recalculateFees(pool);

        uint256 expectedRewardOhm;
        {
            // Record the fees generated
            (uint256 usdcFeesAmount, uint256 ohmFeesAmount) = _getPoolFees(token, usdcAddress);

            uint256 usdcFees = usdcFeesAmount.mulDiv(1e18, 1e6).mulDiv(USDC_PRICE, 1e18); // Convert to 18 decimals and multiply by price
            uint256 ohmFees = ohmFeesAmount.mulDiv(1e18, 1e9).mulDiv(OHM_PRICE, 1e18); // Convert to 18 decimals and multiply by price
            uint256 expectedRewardValue = uint256(HARVEST_REWARD_FEE).mulDiv(
                usdcFees + ohmFees,
                uint256(BPS_MAX)
            );
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

        // Recognise the emitted event
        vm.expectEmit(true, false, false, true);
        emit LastHarvestReset(0);

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

        // Recognise the emitted event
        vm.expectEmit(true, false, false, true);
        emit LastHarvestReset(uint48(block.timestamp - HARVEST_FREQUENCY));

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
        kernel.executeAction(Actions.DeactivatePolicy, bunniManagerAddress);

        // Recognise the emitted event
        vm.expectEmit(true, false, false, true);
        emit LastHarvestReset(uint48(block.timestamp - HARVEST_FREQUENCY));

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

        // Recognise the emitted event
        vm.expectEmit(true, false, false, true);
        emit HarvestFrequencySet(newFrequency);

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
        uint16 newFee = 200; // 2%
        uint256 newReward = HARVEST_REWARD + 2;

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit HarvestRewardParamsSet(newReward, newFee);

        // Call
        vm.prank(policy);
        bunniManager.setHarvestRewardParameters(newReward, newFee);

        // Check that the value has been updated
        assertEq(bunniManager.harvestRewardMax(), newReward);
        assertEq(bunniManager.harvestRewardFee(), newFee);
    }

    // [X] updateSwapFees
    //  [X] can be called by anyone
    //  [X] reverts if bunniHub is not set
    //  [X] reverts if inactive
    //  [X] handles no pools
    //  [X] handles multiple pools
    //  [X] ignores pools with no position

    function test_updateSwapFees_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        // Call
        vm.prank(policy);
        newBunniManager.updateSwapFees();
    }

    function test_updateSwapFees_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        // Call
        vm.prank(policy);
        newBunniManager.updateSwapFees();
    }

    function test_updateSwapFees_unpermissioned() public {
        // Call
        vm.prank(alice);
        bunniManager.updateSwapFees();
    }

    function test_updateSwapFees_noPools() public {
        // Install a new manager without any pools
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniLens(bunniLensAddress);

        // Call
        vm.prank(policy);
        newBunniManager.updateSwapFees();
    }

    function test_updateSwapFees_noPosition() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployPoolToken(address(pool));

        // No deposit

        // Warp
        vm.warp(block.timestamp + HARVEST_FREQUENCY);

        // updateSwapFees does not revert in order to avoid blocking the harvest/updateSwapFees for other pools
        vm.prank(alice);
        bunniManager.updateSwapFees();
    }

    function test_updateSwapFees() public {
        // Create a new pool
        IUniswapV3Pool poolTwo;
        {
            // Creates a new pool with a different fee
            poolTwo = IUniswapV3Pool(uniswapFactory.createPool(usdcAddress, ohmAddress, 3000));
            poolTwo.initialize(OHM_USDC_SQRTPRICEX96);
        }

        // Deploy the token
        IBunniToken token;
        IBunniToken tokenTwo;
        {
            // Deploy the token
            vm.prank(policy);
            token = bunniManager.deployPoolToken(address(pool));
            vm.prank(policy);
            tokenTwo = bunniManager.deployPoolToken(address(poolTwo));
        }

        // Perform the deposit
        {
            uint256 USDC_DEPOSIT = (10_000_000e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
            uint256 OHM_DEPOSIT = 10_000_000e9;

            // Mint the non-OHM token to the TRSRY
            usdc.mint(treasuryAddress, USDC_DEPOSIT * 2);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(pool),
                ohmAddress,
                OHM_DEPOSIT,
                USDC_DEPOSIT,
                SLIPPAGE_DEFAULT
            );

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(poolTwo),
                ohmAddress,
                OHM_DEPOSIT,
                USDC_DEPOSIT,
                SLIPPAGE_DEFAULT
            );
        }

        // Perform the swap on the first pool
        {
            uint256 swapAmountUsdcIn = 100_000e6;

            // Mint USDC into another wallet
            usdc.mint(alice, swapAmountUsdcIn);

            uint256 swapOneOhmMinimum = swapAmountUsdcIn
                .mulDiv(1e18, 1e6)
                .mulDiv(1e18, OHM_USDC_PRICE)
                .mulDiv(1e9, 1e18)
                .mulDiv(95, 100);
            _swap(usdcAddress, ohmAddress, alice, swapAmountUsdcIn, swapOneOhmMinimum, POOL_FEE);

            // And reverse
            uint256 swapTwoUsdcMinimum = swapOneOhmMinimum
                .mulDiv(1e18, 1e9)
                .mulDiv(OHM_USDC_PRICE, 1e18)
                .mulDiv(1e6, 1e18)
                .mulDiv(95, 100);
            _swap(ohmAddress, usdcAddress, alice, swapOneOhmMinimum, swapTwoUsdcMinimum, POOL_FEE);
        }

        // Perform the swap on the second pool
        {
            uint256 swapAmountUsdcIn = 1_000_000e6;
            uint24 poolFee = 3000;

            // Mint USDC into another wallet
            usdc.mint(alice, swapAmountUsdcIn);

            uint256 swapOneOhmMinimum = swapAmountUsdcIn
                .mulDiv(1e18, 1e6)
                .mulDiv(1e18, OHM_USDC_PRICE)
                .mulDiv(1e9, 1e18)
                .mulDiv(95, 100);
            _swap(usdcAddress, ohmAddress, alice, swapAmountUsdcIn, swapOneOhmMinimum, poolFee);

            // And reverse
            uint256 swapTwoUsdcMinimum = swapOneOhmMinimum
                .mulDiv(1e18, 1e9)
                .mulDiv(OHM_USDC_PRICE, 1e18)
                .mulDiv(1e6, 1e18)
                .mulDiv(95, 100);
            _swap(ohmAddress, usdcAddress, alice, swapOneOhmMinimum, swapTwoUsdcMinimum, poolFee);
        }

        uint256 poolOneUsdcFeeAmountBefore;
        uint256 poolOneOhmFeeAmountBefore;
        uint256 poolTwoUsdcFeeAmountBefore;
        uint256 poolTwoOhmFeeAmountBefore;
        {
            // DO NOT recalculate the fees, as we want to check that the fees are updated by updateSwapFees
            (uint256 poolOneUsdcFeeAmount, uint256 poolOneOhmFeeAmount) = _getPoolFees(
                token,
                usdcAddress
            );
            poolOneUsdcFeeAmountBefore = poolOneUsdcFeeAmount;
            poolOneOhmFeeAmountBefore = poolOneOhmFeeAmount;

            (uint256 poolTwoUsdcFeeAmount, uint256 poolTwoOhmFeeAmount) = _getPoolFees(
                tokenTwo,
                usdcAddress
            );
            poolTwoUsdcFeeAmountBefore = poolTwoUsdcFeeAmount;
            poolTwoOhmFeeAmountBefore = poolTwoOhmFeeAmount;
        }

        // Recognise the emitted event
        vm.expectEmit(true, false, false, true);
        emit PoolSwapFeesUpdated(address(pool));
        vm.expectEmit(true, false, false, true);
        emit PoolSwapFeesUpdated(address(poolTwo));

        // Call the function
        vm.prank(policy);
        bunniManager.updateSwapFees();

        // Check that there are more owed fees for the first pool
        {
            (uint256 usdcFeeAmount, uint256 ohmFeeAmount) = _getPoolFees(token, usdcAddress);

            assertGt(
                usdcFeeAmount,
                poolOneUsdcFeeAmountBefore,
                "post-harvest USDC fees for pool one should be greater"
            );
            assertGt(
                ohmFeeAmount,
                poolOneOhmFeeAmountBefore,
                "post-harvest OHM fees  for pool one should be greater"
            );
        }

        // Check that there are more owed fees for the second pool
        {
            (uint256 usdcFeeAmount, uint256 ohmFeeAmount) = _getPoolFees(tokenTwo, usdcAddress);

            assertGt(
                usdcFeeAmount,
                poolTwoUsdcFeeAmountBefore,
                "post-harvest USDC fees for pool two should be greater"
            );
            assertGt(
                ohmFeeAmount,
                poolTwoOhmFeeAmountBefore,
                "post-harvest OHM fees  for pool two should be greater"
            );
        }
    }
}
