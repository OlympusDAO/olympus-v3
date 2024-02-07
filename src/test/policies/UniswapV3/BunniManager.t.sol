// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {TRSRYv1_1, toCategory as toTreasuryCategory} from "modules/TRSRY/TRSRY.v1.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";
import {OlympusSupply} from "modules/SPPLY/OlympusSupply.sol";
import {toCategory as toSupplyCategory} from "modules/SPPLY/SPPLY.v1.sol";
import {BunniPrice} from "modules/PRICE/submodules/feeds/BunniPrice.sol";
import {BunniSupply} from "modules/SPPLY/submodules/BunniSupply.sol";

import {BunniSetup} from "test/policies/UniswapV3/BunniSetup.sol";

import {FullMath} from "libraries/FullMath.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";

import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {SwapRouter} from "test/lib/UniswapV3/SwapRouter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IBunniHub} from "src/external/bunni/interfaces/IBunniHub.sol";

import {BunniManager} from "policies/UniswapV3/BunniManager.sol";
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {BunniHelper} from "libraries/UniswapV3/BunniHelper.sol";

import {UniswapV3PoolLibrary} from "libraries/UniswapV3/PoolLibrary.sol";

import {PoolHelper} from "test/policies/UniswapV3/PoolHelper.sol";

import {ComputeAddress} from "test/libraries/ComputeAddress.sol";

import {toSubKeycode} from "src/Submodules.sol";

import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

import "src/Kernel.sol";

contract BunniManagerTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal policy;
    address internal writePRICE;
    address internal writeSPPLY;
    address internal writeTRSRY;

    MockOhm internal ohm;
    MockERC20 internal usdc;
    MockERC20 internal wETH;
    MockERC20 internal dai;
    MockGohm internal gohm;
    address internal usdcAddress;
    address internal ohmAddress;
    address internal token0Address;
    address internal token1Address;

    BunniSetup internal bunniSetup;

    Kernel internal kernel;

    // Modules
    OlympusTreasury internal TRSRY;
    OlympusPricev2 internal PRICE;
    OlympusSupply internal SPPLY;
    address internal treasuryAddress;

    // PRICE submodules
    BunniPrice internal priceSubmoduleBunni;

    // SPPLY submodules
    BunniSupply internal supplySubmoduleBunni;

    UniswapV3Factory internal uniswapFactory;
    SwapRouter internal swapRouter;

    BunniManager internal bunniManager;
    BunniHub internal bunniHub;
    BunniLens internal bunniLens;
    IUniswapV3Pool internal pool;
    address internal bunniHubAddress;
    address internal bunniLensAddress;
    address internal bunniManagerAddress;

    uint16 internal constant TWAP_DEFAULT_MAX_DEVIATION_BPS = 100; // 1%
    uint32 internal constant TWAP_DEFAULT_OBSERVATION_WINDOW = 600;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals

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

    uint256 private HARVEST_REWARD;
    uint16 private HARVEST_REWARD_FEE; // 10%
    uint48 private HARVEST_FREQUENCY;

    mapping(address => mapping(address => uint256)) private tokenBalances;

    // Moving average data
    uint32 internal _priceMovingAverageDuration = (8 hours) * 3;
    uint48 internal _priceLastObservationTime;
    uint256[] internal _priceObservations;
    uint32 internal _reserveMovingAverageDuration = (8 hours) * 3;
    uint48 internal _reserveLastObservationTime;
    uint256[] internal _reserveToken0Observations;
    uint256[] internal _reserveToken1Observations;

    // Reproduce events
    event BunniLensSet(address indexed newBunniHub_, address indexed newBunniLens_);

    event BunniHubOwnerSet(address indexed bunniHub_, address indexed newOwner_);

    event LastHarvestReset(uint48 newLastHarvest_);

    event HarvestFrequencySet(uint48 newFrequency_);

    event HarvestRewardParamsSet(uint256 newMaxReward_, uint16 newFee_);

    event PositionTokenRegistered(
        address indexed token_,
        address indexed pool_,
        int24 tickLower_,
        int24 tickUpper_
    );

    event NewBunni(
        IBunniToken indexed token,
        bytes32 indexed bunniKeyHash,
        IUniswapV3Pool indexed pool,
        int24 tickLower,
        int24 tickUpper
    );

    event PositionTokenStatusChanged(
        address indexed token_,
        address indexed pool_,
        int24 tickLower_,
        int24 tickUpper_,
        bool indexed activated
    );

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
            ohm = new MockOhm("Olympus", "OHM", 9);

            // The USDC address needs to be higher than ohm, so generate a salt to ensure that
            bytes32 usdcSalt = ComputeAddress.generateSalt(
                address(ohm),
                true,
                type(MockERC20).creationCode,
                abi.encode("USDC", "USDC", 6),
                address(this)
            );
            usdc = new MockERC20{salt: usdcSalt}("USDC", "USDC", 6);

            // The WETH address needs to be higher than ohm, so generate a salt to ensure that
            bytes32 wethSalt = ComputeAddress.generateSalt(
                address(ohm),
                true,
                type(MockERC20).creationCode,
                abi.encode("Wrapped Ether", "wETH", 18),
                address(this)
            );
            wETH = new MockERC20{salt: wethSalt}("Wrapped Ether", "wETH", 18);

            // The DAI address needs to be lesser than usdc, so generate a salt to ensure that
            bytes32 daiSalt = ComputeAddress.generateSalt(
                address(usdc),
                false,
                type(MockERC20).creationCode,
                abi.encode("DAI", "DAI", 18),
                address(this)
            );
            dai = new MockERC20{salt: daiSalt}("DAI", "DAI", 18);

            gohm = new MockGohm(GOHM_INDEX);

            ohmAddress = address(ohm);
            usdcAddress = address(usdc);
            token0Address = address(ohm) > address(usdc) ? address(usdc) : address(ohm);
            token1Address = address(ohm) > address(usdc) ? address(ohm) : address(usdc);
        }

        // Deploy BunniSetup
        {
            bunniSetup = new BunniSetup(ohmAddress, address(gohm), address(this), policy);

            kernel = bunniSetup.kernel();
            TRSRY = bunniSetup.TRSRY();
            PRICE = bunniSetup.PRICE();
            SPPLY = bunniSetup.SPPLY();
            uniswapFactory = bunniSetup.uniswapFactory();
            bunniHub = bunniSetup.bunniHub();
            bunniLens = bunniSetup.bunniLens();
            bunniManager = bunniSetup.bunniManager();

            treasuryAddress = address(bunniSetup.TRSRY());
            bunniHubAddress = address(bunniSetup.bunniHub());
            bunniLensAddress = address(bunniSetup.bunniLens());
            bunniManagerAddress = address(bunniManager);

            HARVEST_REWARD = bunniSetup.HARVEST_REWARD();
            HARVEST_REWARD_FEE = bunniSetup.HARVEST_REWARD_FEE();
            HARVEST_FREQUENCY = bunniSetup.HARVEST_FREQUENCY();
        }

        // Deploy pool
        {
            address pool_ = bunniSetup.setUpPool(
                token0Address,
                token1Address,
                POOL_FEE,
                OHM_USDC_SQRTPRICEX96
            );

            pool = IUniswapV3Pool(pool_);
        }

        // Deploy writer policies
        {
            (address writePRICE_, address writeSPPLY_, address writeTRSRY_) = bunniSetup
                .createWriterPolicies();

            writePRICE = writePRICE_;
            writeSPPLY = writeSPPLY_;
            writeTRSRY = writeTRSRY_;
        }

        {
            // Deploy Uniswap V3 SwapRouter
            swapRouter = new SwapRouter(address(uniswapFactory), address(wETH));
        }

        // Submodule
        {
            (address price_, address supply_) = bunniSetup.createSubmodules(writePRICE, writeSPPLY);

            priceSubmoduleBunni = BunniPrice(price_);
            supplySubmoduleBunni = BunniSupply(supply_);

            // Install strategy
            SimplePriceFeedStrategy strategySubmodule = new SimplePriceFeedStrategy(PRICE);
            vm.prank(writePRICE);
            PRICE.installSubmodule(strategySubmodule);
        }

        // Mock observations for the Uniswap V3 pool
        {
            bunniSetup.mockPoolObservations(
                address(pool),
                TWAP_DEFAULT_OBSERVATION_WINDOW,
                OHM_USDC_TICK_CUMULATIVE_0,
                OHM_USDC_TICK_CUMULATIVE_1
            );
        }

        // Mock values, to avoid having to set up all of PRICEv2 and submodules
        {
            bunniSetup.mockGetPrice(ohmAddress, OHM_USDC_PRICE);
            bunniSetup.mockGetPrice(usdcAddress, USDC_PRICE);
        }

        // Moving average
        {
            _priceLastObservationTime = uint48(block.timestamp) - (8 hours) + 1; // Ensures that it is not yet stale
            _priceObservations = new uint256[](3);
            _priceObservations[0] = 200e18;
            _priceObservations[1] = 200e18;
            _priceObservations[2] = 200e18;
            _reserveLastObservationTime = uint48(block.timestamp) - (8 hours) + 1; // Ensures that it is not yet stale
            _reserveToken0Observations = new uint256[](3);
            _reserveToken0Observations[0] = 100e9;
            _reserveToken0Observations[1] = 100e9;
            _reserveToken0Observations[2] = 100e9;
            _reserveToken1Observations = new uint256[](3);
            _reserveToken1Observations[0] = 1000e6;
            _reserveToken1Observations[1] = 1000e6;
            _reserveToken1Observations[2] = 1000e6;
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

    function _expectRevert_positionNotFound(
        address pool_,
        int24 tickLower_,
        int24 tickUpper_
    ) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_PositionNotFound.selector,
            pool_,
            tickLower_,
            tickUpper_
        );
        vm.expectRevert(err);
    }

    function _expectRevert_positionIdNotFound(address pool_, uint256 id_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_PositionIdNotFound.selector,
            pool_,
            id_
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

    function _expectRevert_tokenDeployed(address token_, address pool_, uint256 id_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_TokenDeployed.selector,
            token_,
            pool_,
            id_
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

    function _expectRevert_tokenActivated(address pool_, uint256 id_, Keycode module_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_TokenActivated.selector,
            pool_,
            id_,
            module_
        );
        vm.expectRevert(err);
    }

    function _mockGetPriceReverts(address asset_) internal {
        bytes memory err = abi.encodeWithSelector(PRICEv2.PRICE_AssetNotApproved.selector, asset_);

        vm.mockCallRevert(
            address(PRICE),
            abi.encodeWithSignature("getPrice(address,uint8)", asset_, PRICEv2.Variant.CURRENT),
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

    function _getPositionKey(
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
        IUniswapV3Pool pool_,
        address tokenIn_,
        address tokenOut_,
        address recipient_,
        uint256 amountIn_,
        uint256 token1Token0Price
    ) internal returns (uint256) {
        // Approve transfer
        vm.prank(recipient_);
        IERC20(tokenIn_).approve(address(swapRouter), amountIn_);

        // Get the parameters
        ISwapRouter.ExactInputSingleParams memory params = PoolHelper.getSwapParams(
            pool_,
            tokenIn_,
            tokenOut_,
            amountIn_,
            recipient_,
            token1Token0Price,
            500,
            TICK
        );

        // Perform the swap
        vm.prank(recipient_);
        swapRouter.exactInputSingle(params);

        return params.amountOutMinimum;
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
            address(bunniSetup.ROLES()),
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
            address(bunniSetup.MINTR()),
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
        expectedPermissions[0] = Permissions(
            TRSRY_KEYCODE,
            OlympusTreasury.withdrawReserves.selector
        );
        expectedPermissions[1] = Permissions(
            TRSRY_KEYCODE,
            OlympusTreasury.increaseWithdrawApproval.selector
        );
        expectedPermissions[2] = Permissions(
            TRSRY_KEYCODE,
            OlympusTreasury.decreaseWithdrawApproval.selector
        );
        expectedPermissions[3] = Permissions(TRSRY_KEYCODE, OlympusTreasury.addAsset.selector);
        expectedPermissions[4] = Permissions(
            TRSRY_KEYCODE,
            OlympusTreasury.addAssetLocation.selector
        );
        expectedPermissions[5] = Permissions(
            TRSRY_KEYCODE,
            OlympusTreasury.removeAssetLocation.selector
        );
        expectedPermissions[6] = Permissions(TRSRY_KEYCODE, OlympusTreasury.categorize.selector);
        expectedPermissions[7] = Permissions(PRICE_KEYCODE, PRICE.addAsset.selector);
        expectedPermissions[8] = Permissions(PRICE_KEYCODE, PRICE.removeAsset.selector);
        expectedPermissions[9] = Permissions(MINTR_KEYCODE, OlympusMinter.mintOhm.selector);
        expectedPermissions[10] = Permissions(MINTR_KEYCODE, OlympusMinter.burnOhm.selector);
        expectedPermissions[11] = Permissions(
            MINTR_KEYCODE,
            OlympusMinter.increaseMintApproval.selector
        );
        expectedPermissions[12] = Permissions(
            MINTR_KEYCODE,
            OlympusMinter.decreaseMintApproval.selector
        );
        expectedPermissions[13] = Permissions(SPPLY_KEYCODE, SPPLY.execOnSubmodule.selector);

        Permissions[] memory perms = bunniManager.requestPermissions();
        assertEq(perms.length, expectedPermissions.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPermissions[i].keycode));
            assertEq(perms[i].funcSelector, expectedPermissions[i].funcSelector);
        }
    }

    // [X] registerPosition
    //  [X] reverts if caller is unauthorized
    //  [X] reverts if bunniHub not set
    //  [X] reverts if token already managed by the policy
    //  [X] reverts if not a Uniswap V3 pool
    //  [X] reverts if no token deployed
    //  [X] reverts if inactive
    //  [X] deploys and returns token
    //  [X] reverts if either asset price not defined

    function test_registerPosition_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.registerPosition(address(pool), address(0), 0);
    }

    function test_registerPosition_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.registerPosition(address(pool), address(0), 0);
    }

    function test_registerPosition_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.registerPosition(address(pool), address(0), 0);
    }

    function test_registerPosition_invalidPoolReverts() public {
        _expectRevert_poolNotFound(ohmAddress);

        vm.prank(policy);
        bunniManager.registerPosition(ohmAddress, address(0), 0);
    }

    function test_registerPosition_noDeployedTokenReverts() public {
        // Create a new BunniManager policy
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniLens(bunniLensAddress);

        // Expect an error, as no token has been deployed against the old manager
        _expectRevert_positionIdNotFound(address(pool), 0);

        // Register the pool with the new policy
        vm.prank(policy);
        newBunniManager.registerPosition(address(pool), address(bunniManager), 0);
    }

    function test_registerPosition_alreadyDeployedTokenReverts() public {
        // Deploy a full-range position on the old manager
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployFullRangeToken(address(pool));

        // Create a new BunniManager policy
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniLens(bunniLensAddress);

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        newBunniManager.registerPosition(address(pool), address(bunniManager), 0);

        _expectRevert_tokenDeployed(address(deployedToken), address(pool), 0);

        // Register the pool
        vm.prank(policy);
        newBunniManager.registerPosition(address(pool), address(bunniManager), 0);
    }

    function test_registerPosition_usdcPriceUnsetReverts() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

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
        newBunniManager.registerPosition(address(pool), address(bunniManager), 0);
    }

    function test_registerPosition_ohmPriceUnsetReverts() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

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
        newBunniManager.registerPosition(address(pool), address(bunniManager), 0);
    }

    function test_registerPosition() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployFullRangeToken(address(pool));

        // Install a new policy
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniLens(bunniLensAddress);

        BunniKey memory key = bunniManager.getPositionKey(address(pool), 0);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PositionTokenRegistered(
            address(deployedToken),
            address(pool),
            key.tickLower,
            key.tickUpper
        );

        // Register the pool with the new policy
        vm.prank(policy);
        IBunniToken newDeployedToken = newBunniManager.registerPosition(
            address(pool),
            address(bunniManager),
            0
        );

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

    function test_registerPosition_multiple() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployFullRangeToken(address(pool));

        // Create a new pool with an overlapping underlying token
        bunniSetup.mockGetPrice(address(dai), 1e18);
        IUniswapV3Pool newPool = IUniswapV3Pool(
            uniswapFactory.createPool(usdcAddress, address(dai), POOL_FEE)
        );
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Deploy the second token
        vm.prank(policy);
        IBunniToken deployedTokenTwo = bunniManager.deployFullRangeToken(address(newPool));

        // Install a new policy
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniLens(bunniLensAddress);

        BunniKey memory key = bunniManager.getPositionKey(address(pool), 0);
        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PositionTokenRegistered(
            address(deployedToken),
            address(pool),
            key.tickLower,
            key.tickUpper
        );

        // Register the pool with the new policy
        vm.prank(policy);
        newBunniManager.registerPosition(address(pool), address(bunniManager), 0);

        key = bunniManager.getPositionKey(address(newPool), 0);
        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PositionTokenRegistered(
            address(deployedTokenTwo),
            address(newPool),
            key.tickLower,
            key.tickUpper
        );

        // Register the new pool with the new policy
        vm.prank(policy);
        newBunniManager.registerPosition(address(newPool), address(bunniManager), 0);

        // Check that the pools are registered
        uint256 poolCount = newBunniManager.poolCount();
        assertEq(poolCount, 2);
        address poolOne = newBunniManager.pools(0);
        assertEq(poolOne, address(pool));
        address poolTwo = newBunniManager.pools(1);
        assertEq(poolTwo, address(newPool));
    }

    // [X] deployFullRangeToken
    //  [X] caller is unauthorized
    //  [X] bunniHub not set
    //  [X] token already deployed
    //  [X] not a Uniswap V3 pool
    //  [X] deploys and returns token
    //  [X] reverts when inactive
    //  [X] reverts if either asset price not defined
    //  [X] handles different pool fees

    function test_deployFullRangeToken_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.deployFullRangeToken(address(pool));
    }

    function test_deployFullRangeToken_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.deployFullRangeToken(address(pool));
    }

    function test_deployFullRangeToken_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.deployFullRangeToken(address(pool));
    }

    function test_deployFullRangeToken_invalidPoolReverts() public {
        _expectRevert_poolNotFound(ohmAddress);

        vm.prank(policy);
        bunniManager.deployFullRangeToken(ohmAddress);
    }

    function test_deployFullRangeToken_usdcPriceUnsetReverts() public {
        _mockGetPriceReverts(usdcAddress);

        _expectRevert_priceZero(usdcAddress);

        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));
    }

    function test_deployFullRangeToken_ohmPriceUnsetReverts() public {
        _mockGetPriceReverts(ohmAddress);

        _expectRevert_priceZero(ohmAddress);

        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));
    }

    function test_deployFullRangeToken() public {
        // Recognise the emitted event
        vm.expectEmit(false, false, true, false);
        emit NewBunni(IBunniToken(address(0)), bytes32(0), pool, 0, 0);

        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployFullRangeToken(address(pool));

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

    function test_deployFullRangeToken_multiple() public {
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

        // Create a new pool with an overlapping underlying token
        bunniSetup.mockGetPrice(address(dai), 1e18);
        IUniswapV3Pool newPool = IUniswapV3Pool(
            uniswapFactory.createPool(usdcAddress, address(dai), POOL_FEE)
        );
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Deploy the second token
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(newPool));

        // Check that the pools are registered
        uint256 poolCount = bunniManager.poolCount();
        assertEq(poolCount, 2);
        address poolOne = bunniManager.pools(0);
        assertEq(poolOne, address(pool));
        address poolTwo = bunniManager.pools(1);
        assertEq(poolTwo, address(newPool));
    }

    function test_deployFullRangeToken_duplicateReverts() public {
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployFullRangeToken(address(pool));

        _expectRevert_tokenDeployed(address(deployedToken), address(pool), 0);

        // Deploy a second time
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));
    }

    function test_deployFullRangeToken_poolFee3000() public {
        // Create a pool with a different fee
        uint24 poolFee = 3000;
        IUniswapV3Pool poolTwo = IUniswapV3Pool(
            uniswapFactory.createPool(ohmAddress, usdcAddress, poolFee)
        );
        poolTwo.initialize(OHM_USDC_SQRTPRICEX96);

        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployFullRangeToken(address(poolTwo));

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
            0,
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );
    }

    function test_deployFullRangeToken_poolFee100() public {
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
        IBunniToken deployedToken = bunniManager.deployFullRangeToken(address(poolTwo));

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
            0,
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );
    }

    // [X] deployConcentratedPositionToken
    //  [X] caller is unauthorized
    //  [X] bunniHub not set
    //  [X] token already deployed
    //  [X] not a Uniswap V3 pool
    //  [X] deploys and returns token
    //  [X] reverts when inactive
    //  [X] reverts if either asset price not defined
    //  [X] handles different pool fees

    function test_deployConcentratedPositionToken_unauthorizedReverts() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.deployConcentratedToken(address(pool), -444444, 444444);
    }

    function test_deployConcentratedPositionToken_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.deployConcentratedToken(address(pool), -444444, 444444);
    }

    function test_deployConcentratedPositionToken_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.deployConcentratedToken(address(pool), -444444, 444444);
    }

    function test_deployConcentratedPositionToken_invalidPoolReverts() public {
        _expectRevert_poolNotFound(ohmAddress);

        vm.prank(policy);
        bunniManager.deployConcentratedToken(ohmAddress, -444444, 444444);
    }

    function test_deployConcentratedPositionToken_usdcPriceUnsetReverts() public {
        _mockGetPriceReverts(usdcAddress);

        _expectRevert_priceZero(usdcAddress);

        vm.prank(policy);
        bunniManager.deployConcentratedToken(address(pool), -444444, 444444);
    }

    function test_deployConcentratedPositionToken_ohmPriceUnsetReverts() public {
        _mockGetPriceReverts(ohmAddress);

        _expectRevert_priceZero(ohmAddress);

        vm.prank(policy);
        bunniManager.deployConcentratedToken(address(pool), -444444, 444444);
    }

    function test_deployConcentratedPositionToken() public {
        // Recognise the emitted event
        vm.expectEmit(false, false, true, false);
        emit NewBunni(IBunniToken(address(0)), bytes32(0), pool, 0, 0);

        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployConcentratedToken(
            address(pool),
            -444444,
            444444
        );

        int24 tick = (444444 / pool.tickSpacing()) * pool.tickSpacing();

        // Check details of token
        assertEq(address(deployedToken.pool()), address(pool));
        assertEq(deployedToken.tickLower(), -1 * tick);
        assertEq(deployedToken.tickUpper(), tick);

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

    function test_deployConcentratedPositionToken_multiple() public {
        vm.prank(policy);
        bunniManager.deployConcentratedToken(address(pool), -444444, 444444);

        // Create a new pool with an overlapping underlying token
        bunniSetup.mockGetPrice(address(dai), 1e18);
        IUniswapV3Pool newPool = IUniswapV3Pool(
            uniswapFactory.createPool(usdcAddress, address(dai), POOL_FEE)
        );
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Deploy the second token
        vm.prank(policy);
        bunniManager.deployConcentratedToken(address(newPool), -444444, 444444);

        // Check that the pools are registered
        uint256 poolCount = bunniManager.poolCount();
        assertEq(poolCount, 2);
        address poolOne = bunniManager.pools(0);
        assertEq(poolOne, address(pool));
        address poolTwo = bunniManager.pools(1);
        assertEq(poolTwo, address(newPool));
    }

    function test_deployConcentratedPositionToken_duplicateReverts() public {
        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployConcentratedToken(
            address(pool),
            -444444,
            444444
        );

        _expectRevert_tokenDeployed(address(deployedToken), address(pool), 0);

        // Deploy a second time
        vm.prank(policy);
        bunniManager.deployConcentratedToken(address(pool), -444444, 444444);
    }

    function test_deployConcentratedPositionToken_poolFee3000() public {
        // Create a pool with a different fee
        uint24 poolFee = 3000;
        IUniswapV3Pool poolTwo = IUniswapV3Pool(
            uniswapFactory.createPool(ohmAddress, usdcAddress, poolFee)
        );
        poolTwo.initialize(OHM_USDC_SQRTPRICEX96);

        vm.prank(policy);
        IBunniToken deployedToken = bunniManager.deployConcentratedToken(
            address(poolTwo),
            -444444,
            444444
        );

        int24 tick = (444444 / poolTwo.tickSpacing()) * poolTwo.tickSpacing();

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
            0,
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );
    }

    function test_deployConcentratedPositionToken_poolFee100() public {
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
        IBunniToken deployedToken = bunniManager.deployConcentratedToken(
            address(poolTwo),
            -444444,
            444444
        );

        int24 tick = (444444 / poolTwo.tickSpacing()) * poolTwo.tickSpacing();

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
            0,
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
    //  [X] success - registers with TRSRY, PRICE (including moving average), SPPLY

    function testRevert_activatePoolToken_unauthorized() public {
        _expectRevert_unauthorized();

        vm.prank(alice);
        bunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
        );
    }

    function testRevert_activatePoolToken_inactive() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
        );
    }

    function testRevert_activatePoolToken_bunniHubNotSet() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
        );
    }

    function testRevert_activatePoolToken_tokenNotDeployed() public {
        _expectRevert_positionIdNotFound(address(pool), 0);

        vm.prank(policy);
        bunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
        );
    }

    function testRevert_activatePoolToken_noLiquidity() public {
        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_PositionLiquidity_IncorrectState.selector,
            address(pool),
            0
        );
        vm.expectRevert(err);

        vm.prank(policy);
        bunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
        );
    }

    function testRevert_activatePoolToken_registeredWithTrsryLocationsReverts() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployFullRangeToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            0,
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
        _expectRevert_tokenActivated(address(pool), 0, toKeycode("TRSRY"));

        vm.prank(policy);
        bunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
        );
    }

    function testRevert_activatePoolToken_registeredWithPriceReverts() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployFullRangeToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            0,
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Prepare parameters for PRICE
        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        {
            BunniPrice.BunniParams memory params = BunniPrice.BunniParams(address(bunniLens));

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
            uint32(0), // uint32 _reserveMovingAverageDuration_
            uint48(0), // uint48 _reserveLastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds // Component[] memory feeds_
        );

        // Expect a revert
        _expectRevert_tokenActivated(address(pool), 0, toKeycode("PRICE"));

        vm.prank(policy);
        bunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
        );
    }

    function testRevert_activatePoolToken_registeredWithSupplyReverts() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployFullRangeToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            0,
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Register the asset with SPPLY
        vm.prank(address(SPPLY));
        supplySubmoduleBunni.addBunniToken(
            address(poolToken),
            address(bunniLens),
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
        );

        // Expect a revert
        _expectRevert_tokenActivated(address(pool), 0, toKeycode("SPPLY"));

        vm.prank(policy);
        bunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
        );
    }

    function test_activatePoolToken_registeredTreasuryAsset() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployFullRangeToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            0,
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

        BunniKey memory key = bunniManager.getPositionKey(address(pool), 0);
        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PositionTokenStatusChanged(
            address(poolToken),
            address(pool),
            key.tickLower,
            key.tickUpper,
            true
        );

        vm.prank(policy);
        bunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
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
        IBunniToken poolToken = bunniManager.deployFullRangeToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            0,
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

        BunniKey memory key = bunniManager.getPositionKey(address(pool), 0);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PositionTokenStatusChanged(
            address(poolToken),
            address(pool),
            key.tickLower,
            key.tickUpper,
            true
        );

        vm.prank(policy);
        bunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
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

        address[] memory trsryVolatileAssets = TRSRY.getAssetsByCategory(
            toTreasuryCategory("volatile")
        );
        assertEq(trsryVolatileAssets.length, 1);
        assertEq(trsryVolatileAssets[0], address(poolToken));

        address[] memory trsryLiquidAssets = TRSRY.getAssetsByCategory(
            toTreasuryCategory("liquid")
        );
        assertEq(trsryLiquidAssets.length, 1);
        assertEq(trsryLiquidAssets[0], address(poolToken));

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
        IBunniToken poolToken = bunniManager.deployFullRangeToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            0,
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        BunniKey memory key = bunniManager.getPositionKey(address(pool), 0);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PositionTokenStatusChanged(
            address(poolToken),
            address(pool),
            key.tickLower,
            key.tickUpper,
            true
        );

        vm.prank(policy);
        bunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
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
        assertTrue(priceAsset.useMovingAverage);
        assertTrue(priceAsset.storeMovingAverage);
        assertEq(priceAsset.movingAverageDuration, _priceMovingAverageDuration);
        assertEq(priceAsset.lastObservationTime, _priceLastObservationTime);
        assertEq(priceAsset.numObservations, _priceObservations.length);

        // Check that the price feed has the correct parameters
        PRICEv2.Component[] memory priceFeeds = abi.decode(priceAsset.feeds, (PRICEv2.Component[]));
        BunniPrice.BunniParams memory bunniParams = abi.decode(
            priceFeeds[0].params,
            (BunniPrice.BunniParams)
        );
        assertEq(bunniParams.bunniLens, address(bunniLens));

        // Check that the price is non-zero
        assertTrue(PRICE.getPrice(address(poolToken)) > 0);

        // Check that the token is included in SPPLY metrics
        uint256 polo = SPPLY.getSupplyByCategory(toSupplyCategory("protocol-owned-liquidity"));
        assertTrue(polo > 0);

        // Check that the token has been added to the BunniSupply submodule
        (IBunniToken submoduleBunniToken_, BunniLens submoduleBunniLens_) = supplySubmoduleBunni
            .bunniTokens(0);
        assertEq(address(submoduleBunniToken_), address(poolToken));
        assertEq(address(submoduleBunniLens_), address(bunniLens));

        // Check that the token has moving average data stored
        (
            uint16 supplyNextObservationIndex_,
            uint16 supplyNumObservations_,
            uint32 supplyMovingAverageDuration_,
            uint48 supplyLastObservationTime_,
            ,

        ) = supplySubmoduleBunni.tokenMovingAverages(address(poolToken));
        assertEq(supplyNextObservationIndex_, 0);
        assertEq(supplyNumObservations_, _reserveToken0Observations.length);
        assertEq(supplyMovingAverageDuration_, _reserveMovingAverageDuration);
        assertEq(supplyLastObservationTime_, _reserveLastObservationTime);
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
        bunniManager.deactivatePositionToken(address(pool), 0);
    }

    function test_deactivatePoolToken_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.deactivatePositionToken(address(pool), 0);
    }

    function test_deactivatePoolToken_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.deactivatePositionToken(address(pool), 0);
    }

    function test_deactivatePoolToken_tokenNotDeployedReverts() public {
        _expectRevert_positionIdNotFound(address(pool), 0);

        vm.prank(policy);
        bunniManager.deactivatePositionToken(address(pool), 0);
    }

    function test_deactivatePoolToken_hasLiquidityReverts() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            0,
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        bytes memory err = abi.encodeWithSelector(
            BunniManager.BunniManager_PositionLiquidity_IncorrectState.selector,
            address(pool),
            0
        );
        vm.expectRevert(err);

        vm.prank(policy);
        bunniManager.deactivatePositionToken(address(pool), 0);
    }

    function test_deactivatePoolToken() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy a token so that the ERC20 exists
        vm.prank(policy);
        IBunniToken poolToken = bunniManager.deployFullRangeToken(address(pool));

        // Mint tokens to the TRSRY
        vm.prank(policy);
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            0,
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Activate the token
        vm.prank(policy);
        bunniManager.activatePositionToken(
            address(pool),
            0,
            _priceMovingAverageDuration,
            _priceLastObservationTime,
            _priceObservations,
            _reserveMovingAverageDuration,
            _reserveLastObservationTime,
            _reserveToken0Observations,
            _reserveToken1Observations
        );

        // Withdraw
        vm.prank(policy);
        bunniManager.withdraw(address(pool), 0, bunniTokenShares, SLIPPAGE_DEFAULT);

        BunniKey memory key = bunniManager.getPositionKey(address(pool), 0);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PositionTokenStatusChanged(
            address(poolToken),
            address(pool),
            key.tickLower,
            key.tickUpper,
            false
        );

        // Deactivate
        vm.prank(policy);
        bunniManager.deactivatePositionToken(address(pool), 0);

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
        IBunniToken poolToken = bunniManager.deployFullRangeToken(address(pool));

        // Do NOT deposit or activate, so that TRSRY/PRICE/SPPLY are not registered

        BunniKey memory key = bunniManager.getPositionKey(address(pool), 0);

        // Recognise the emitted event
        vm.expectEmit(true, true, false, true);
        emit PositionTokenStatusChanged(
            address(poolToken),
            address(pool),
            key.tickLower,
            key.tickUpper,
            false
        );

        // Deactivate
        vm.prank(policy);
        bunniManager.deactivatePositionToken(address(pool), 0);

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
        bunniManager.deposit(address(pool), 0, ohmAddress, 1e9, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_deposit_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.deposit(address(pool), 0, ohmAddress, 1e9, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_deposit_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.deposit(address(pool), 0, ohmAddress, 1e9, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_deposit_tokenNotDeployedReverts() public {
        _expectRevert_positionIdNotFound(address(pool), 0);

        vm.prank(policy);
        bunniManager.deposit(address(pool), 0, ohmAddress, 1e9, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_deposit_token0InsufficientBalanceReverts(uint256 token0Amount_) public {
        // Create a pool with non-OHM tokens
        bunniSetup.mockGetPrice(address(dai), 1e18);
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
        bunniManager.deployFullRangeToken(address(newPool));

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
        bunniManager.deposit(address(newPool), 0, address(dai), 1e18, 1e6, SLIPPAGE_DEFAULT);
    }

    function test_deposit_token1InsufficientBalanceReverts(uint256 token1Amount_) public {
        // Create a pool with non-OHM tokens
        bunniSetup.mockGetPrice(address(dai), 1e18);
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
        bunniManager.deployFullRangeToken(address(newPool));

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
        bunniManager.deposit(address(newPool), 0, address(dai), 1e18, 1e6, SLIPPAGE_DEFAULT);
    }

    function test_deposit_nonOhmTokens_fuzz(uint256 usdcAmount_) public {
        uint256 usdcAmount = bound(usdcAmount_, 100e6, 1e12);
        uint256 daiAmount = usdcAmount.mulDiv(1e18, 1e6); // Same price, different decimal scale

        // Create a pool with non-OHM tokens
        bunniSetup.mockGetPrice(address(dai), 1e18);
        IUniswapV3Pool newPool = IUniswapV3Pool(
            uniswapFactory.createPool(usdcAddress, address(dai), POOL_FEE)
        );
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployFullRangeToken(address(newPool));

        // Mint tokens to the TRSRY
        dai.mint(treasuryAddress, daiAmount);
        usdc.mint(treasuryAddress, usdcAmount);
        uint256 ohmSupplyBefore = ohm.totalSupply();

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(newPool),
            0,
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

        // Assert approvals
        assertEq(dai.allowance(bunniManagerAddress, bunniHubAddress), 0, "dai allowance");
        assertEq(usdc.allowance(bunniManagerAddress, bunniHubAddress), 0, "usdc allowance");
    }

    function test_deposit_invalidUnderlyingTokenReverts() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

        // Expect a revert
        bytes memory err = abi.encodeWithSelector(UniswapV3PoolLibrary.InvalidParams.selector);
        vm.expectRevert(err);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(address(pool), 0, address(wETH), 1e9, 1e6, SLIPPAGE_DEFAULT);
    }

    function test_deposit_ohmToken_fuzz(uint256 amount_) public {
        uint256 amount = bound(amount_, 100e6, 1e12);
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployFullRangeToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);
        uint256 ohmSupplyBefore = ohm.totalSupply();

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            0,
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
            _getPositionKey(pool, bunniToken)
        );
        uint256 ohmReserve = pool.token0() == ohmAddress ? reserve0 : reserve1;

        // Tolerant of rounding
        assertApproxEqAbs(ohm.totalSupply(), ohmSupplyBefore + ohmReserve, 1);

        // Assert approvals
        assertEq(ohm.allowance(bunniManagerAddress, bunniHubAddress), 0, "dai allowance");
        assertEq(usdc.allowance(bunniManagerAddress, bunniHubAddress), 0, "usdc allowance");
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
        IBunniToken bunniToken = bunniManager.deployFullRangeToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);
        uint256 ohmSupplyBefore = ohm.totalSupply();

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            0,
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
            _getPositionKey(pool, bunniToken)
        );
        uint256 ohmReserve = pool.token0() == ohmAddress ? reserve0 : reserve1;
        uint256 usdcReserve = pool.token0() == usdcAddress ? reserve0 : reserve1;

        // Tolerant of rounding
        assertApproxEqAbs(ohm.totalSupply(), ohmSupplyBefore + ohmReserve, 1);
        assertApproxEqAbs(usdcReserve, USDC_DEPOSIT, 1);

        // Assert approvals
        assertEq(ohm.allowance(bunniManagerAddress, bunniHubAddress), 0, "dai allowance");
        assertEq(usdc.allowance(bunniManagerAddress, bunniHubAddress), 0, "usdc allowance");
    }

    function test_deposit_invalidSlippage() public {
        uint256 OHM_DEPOSIT = 1000e9;
        uint256 USDC_DEPOSIT = OHM_DEPOSIT.mulDiv(1e6, 1e9).mulDiv(OHM_USDC_PRICE, 1e18);

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Set up the invalid slippage
        uint16 slippage = SLIPPAGE_MAX + 1;
        _expectRevert_invalidSlippage(slippage);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(address(pool), 0, ohmAddress, OHM_DEPOSIT, USDC_DEPOSIT, slippage);
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
        bunniManager.withdraw(address(pool), 0, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_withdraw_inactiveReverts() public {
        // Create a new BunniManager policy, but don't install/activate it
        BunniManager newBunniManager = _createNewBunniManager();

        _expectRevert_inactive();

        vm.prank(policy);
        newBunniManager.withdraw(address(pool), 0, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_withdraw_bunniHubNotSetReverts() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        _expectRevert_bunniHubNotSet();

        vm.prank(policy);
        newBunniManager.withdraw(address(pool), 0, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_withdraw_tokenNotDeployedReverts() public {
        _expectRevert_positionIdNotFound(address(pool), 0);

        vm.prank(policy);
        bunniManager.withdraw(address(pool), 0, 1e18, SLIPPAGE_DEFAULT);
    }

    function test_withdraw_insufficientBalanceReverts() public {
        uint256 USDC_DEPOSIT = (10e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
        uint256 OHM_DEPOSIT = 10e9;

        // Deploy the token
        vm.prank(policy);
        IBunniToken token = bunniManager.deployFullRangeToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            0,
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
        bunniManager.withdraw(address(pool), 0, bunniTokenSharesToWithdraw, SLIPPAGE_DEFAULT);
    }

    function test_withdraw_nonOhmTokens(uint256 shareToWithdraw_) public {
        // Create a pool with non-OHM tokens
        bunniSetup.mockGetPrice(address(dai), 1e18);
        IUniswapV3Pool newPool = IUniswapV3Pool(
            uniswapFactory.createPool(usdcAddress, address(dai), POOL_FEE)
        );
        newPool.initialize(DAI_USDC_SQRTPRICEX96);

        // Deploy the token
        vm.prank(policy);
        IBunniToken token = bunniManager.deployFullRangeToken(address(newPool));

        // Mint tokens to the TRSRY
        dai.mint(treasuryAddress, 1e18);
        usdc.mint(treasuryAddress, 1e6);

        uint256 DAI_DEPOSIT = 1e18;
        uint256 USDC_DEPOSIT = 1e6;

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(newPool),
            0,
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
        bunniManager.withdraw(address(newPool), 0, bunniTokenSharesToWithdraw, SLIPPAGE_DEFAULT);

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
        IBunniToken token = bunniManager.deployFullRangeToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            0,
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
        bunniManager.withdraw(address(pool), 0, bunniTokenSharesToWithdraw, SLIPPAGE_DEFAULT);

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
        bunniManager.deployFullRangeToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 shares = bunniManager.deposit(
            address(pool),
            0,
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
        bunniManager.withdraw(address(pool), 0, shares, slippage);
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

        newBunniManager.getPositionToken(address(pool), 0);
    }

    function test_getPoolToken_tokenNotDeployedReverts() public {
        _expectRevert_positionIdNotFound(address(pool), 0);

        bunniManager.getPositionToken(address(pool), 0);
    }

    function test_getPoolToken() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

        // Get the token
        IBunniToken token = bunniManager.getPositionToken(address(pool), 0);

        // Check return value
        assertEq(address(token.pool()), address(pool));
        assertEq(token.tickLower(), int24(-1 * TICK));
        assertEq(token.tickUpper(), TICK);
    }

    function test_getPoolToken_inactive() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

        // Disable the policy
        kernel.executeAction(Actions.DeactivatePolicy, bunniManagerAddress);

        // Get the token
        IBunniToken token = bunniManager.getPositionToken(address(pool), 0);

        // Check return value
        assertEq(address(token.pool()), address(pool));
        assertEq(token.tickLower(), int24(-1 * TICK));
        assertEq(token.tickUpper(), TICK);
    }

    // [X] getPoolToken
    //  [X] token is not deployed
    //  [X] returns token struct
    //  [X] returns even if inactive

    function testRevert_getPositionID_tokenNotDeployed() public {
        // Create a new BunniManager policy, without the BunniHub set
        BunniManager newBunniManager = _setUpNewBunniManager();

        // Shift the BunniHub over to the new policy
        vm.prank(policy);
        bunniManager.setBunniOwner(address(newBunniManager));
        vm.prank(policy);
        newBunniManager.setBunniLens(bunniLensAddress);

        _expectRevert_positionNotFound(address(pool), -TICK, TICK);

        newBunniManager.getPositionId(address(pool), -TICK, TICK);
    }

    function test_getPositionID() public {
        int24 CONC_TICK = ((TICK / 2) / pool.tickSpacing()) * pool.tickSpacing();

        // Deploy the tokens
        vm.startPrank(policy);
        bunniManager.deployFullRangeToken(address(pool));
        bunniManager.deployConcentratedToken(address(pool), -CONC_TICK, CONC_TICK);
        vm.stopPrank();

        // Check return values
        assertEq(bunniManager.getPositionId(address(pool), -TICK, TICK), 0);

        assertEq(bunniManager.getPositionId(address(pool), -CONC_TICK, CONC_TICK), 1);
    }

    function test_getPositionID_inactive() public {
        int24 CONC_TICK = ((TICK / 2) / pool.tickSpacing()) * pool.tickSpacing();

        // Deploy the tokens
        vm.startPrank(policy);
        bunniManager.deployFullRangeToken(address(pool));
        bunniManager.deployConcentratedToken(address(pool), -CONC_TICK, CONC_TICK);
        vm.stopPrank();

        // Disable the policy
        kernel.executeAction(Actions.DeactivatePolicy, bunniManagerAddress);

        // Check return values
        assertEq(bunniManager.getPositionId(address(pool), -TICK, TICK), 0);

        assertEq(bunniManager.getPositionId(address(pool), -CONC_TICK, CONC_TICK), 1);
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

        newBunniManager.getPositionTokenBalance(address(pool), 0);
    }

    function test_getPoolTokenBalance_tokenNotDeployedReverts() public {
        _expectRevert_positionIdNotFound(address(pool), 0);

        bunniManager.getPositionTokenBalance(address(pool), 0);
    }

    function test_getPoolTokenBalance_zeroBalance() public {
        // Deploy the token
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

        // Get the token
        uint256 balance = bunniManager.getPositionTokenBalance(address(pool), 0);

        // Check return value
        assertEq(balance, 0);
    }

    function test_getPoolTokenBalance_fuzz(uint256 amount_) public {
        uint256 amount = bound(amount_, 100e6, 1e12);
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            0,
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Check that the value is consistent
        uint256 balance = bunniManager.getPositionTokenBalance(address(pool), 0);
        assertEq(balance, bunniTokenShares);
    }

    function test_getPoolTokenBalance_inactive() public {
        uint256 amount = 100e6;
        uint256 USDC_DEPOSIT = amount.mulDiv(OHM_USDC_PRICE, 1e18);
        uint256 OHM_DEPOSIT = amount.mulDiv(1e9, 1e6); // Adjust for decimal scale

        // Deploy the token
        vm.prank(policy);
        bunniManager.deployFullRangeToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        uint256 bunniTokenShares = bunniManager.deposit(
            address(pool),
            0,
            ohmAddress,
            OHM_DEPOSIT,
            USDC_DEPOSIT,
            SLIPPAGE_DEFAULT
        );

        // Disable the policy
        kernel.executeAction(Actions.DeactivatePolicy, bunniManagerAddress);

        // Check that the value is consistent
        uint256 balance = bunniManager.getPositionTokenBalance(address(pool), 0);
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
        bunniManager.deployFullRangeToken(address(pool));

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
        bunniManager.deployFullRangeToken(address(pool));

        // Mint the non-OHM token to the TRSRY
        usdc.mint(treasuryAddress, USDC_DEPOSIT);

        // Deposit
        vm.prank(policy);
        bunniManager.deposit(
            address(pool),
            0,
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
            token = bunniManager.deployFullRangeToken(address(pool));

            // Mint the non-OHM token to the TRSRY
            usdc.mint(treasuryAddress, USDC_DEPOSIT);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(pool),
                0,
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

            // Swap USDC for OHM
            uint256 ohmAmountOut = _swap(
                pool,
                usdcAddress,
                ohmAddress,
                alice,
                swapAmountUsdcIn,
                OHM_USDC_PRICE
            );

            // Swap OHM for USDC
            _swap(pool, ohmAddress, usdcAddress, alice, ohmAmountOut, OHM_USDC_PRICE);
        }

        // Store balances for comparison
        _storeTokenBalance(treasuryAddress, usdcAddress);
        _storeTokenBalance(treasuryAddress, ohmAddress);
        _storeTokenBalance(policy, usdcAddress);
        _storeTokenBalance(policy, ohmAddress);
        _storeTokenBalance(alice, usdcAddress);
        _storeTokenBalance(alice, ohmAddress);

        // Warp forward
        vm.warp(block.timestamp + HARVEST_FREQUENCY);

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
        vm.prank(alice);
        bunniManager.harvest();

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

    function test_harvest_afterMinimum_fuzz(uint48 elapsed_) public {
        uint48 elapsed = uint48(bound(elapsed_, 1, HARVEST_FREQUENCY));

        IBunniToken token;
        {
            uint256 USDC_DEPOSIT = (10_000_000e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
            uint256 OHM_DEPOSIT = 10_000_000e9;

            // Deploy the token
            vm.prank(policy);
            token = bunniManager.deployFullRangeToken(address(pool));

            // Mint the non-OHM token to the TRSRY
            usdc.mint(treasuryAddress, USDC_DEPOSIT);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(pool),
                0,
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

            // Swap USDC for OHM
            uint256 ohmAmountOut = _swap(
                pool,
                usdcAddress,
                ohmAddress,
                alice,
                swapAmountUsdcIn,
                OHM_USDC_PRICE
            );

            // Swap OHM for USDC
            _swap(pool, ohmAddress, usdcAddress, alice, ohmAmountOut, OHM_USDC_PRICE);
        }

        // Store balances for comparison
        _storeTokenBalance(treasuryAddress, usdcAddress);
        _storeTokenBalance(treasuryAddress, ohmAddress);
        _storeTokenBalance(policy, usdcAddress);
        _storeTokenBalance(policy, ohmAddress);
        _storeTokenBalance(alice, usdcAddress);
        _storeTokenBalance(alice, ohmAddress);

        // Warp forward
        vm.warp(block.timestamp + HARVEST_FREQUENCY + elapsed);

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

        // Reward should be non-zero
        assertGt(currentReward, 0, "currentReward should be non-zero");

        // Get current liquidity
        uint128 liquidityBefore = pool.liquidity();

        // Harvest
        vm.prank(alice);
        bunniManager.harvest();

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
            token = bunniManager.deployFullRangeToken(address(pool));
            vm.prank(policy);
            tokenTwo = bunniManager.deployFullRangeToken(address(poolTwo));
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
                0,
                ohmAddress,
                OHM_DEPOSIT,
                USDC_DEPOSIT,
                SLIPPAGE_DEFAULT
            );

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(poolTwo),
                0,
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

            // Swap USDC for OHM
            uint256 ohmAmountOut = _swap(
                pool,
                usdcAddress,
                ohmAddress,
                alice,
                swapAmountUsdcIn,
                OHM_USDC_PRICE
            );

            // Swap OHM for USDC
            _swap(pool, ohmAddress, usdcAddress, alice, ohmAmountOut, OHM_USDC_PRICE);
        }

        // Perform the swap on the second pool
        {
            uint256 swapAmountUsdcIn = 1_000_000e6;

            // Mint USDC into another wallet
            usdc.mint(alice, swapAmountUsdcIn);

            // Swap USDC for OHM
            uint256 ohmAmountOut = _swap(
                poolTwo,
                usdcAddress,
                ohmAddress,
                alice,
                swapAmountUsdcIn,
                OHM_USDC_PRICE
            );

            // Swap OHM for USDC
            _swap(poolTwo, ohmAddress, usdcAddress, alice, ohmAmountOut, OHM_USDC_PRICE);
        }

        // Store balances for comparison
        _storeTokenBalance(treasuryAddress, usdcAddress);
        _storeTokenBalance(treasuryAddress, ohmAddress);
        _storeTokenBalance(policy, usdcAddress);
        _storeTokenBalance(policy, ohmAddress);
        _storeTokenBalance(alice, usdcAddress);
        _storeTokenBalance(alice, ohmAddress);

        // Warp forward
        vm.warp(block.timestamp + HARVEST_FREQUENCY);

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
        vm.prank(alice);
        bunniManager.harvest();

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
            token = bunniManager.deployFullRangeToken(address(pool));

            // Mint the non-OHM token to the TRSRY
            usdc.mint(treasuryAddress, USDC_DEPOSIT);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(pool),
                0,
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

            // Swap USDC for OHM
            uint256 ohmAmountOut = _swap(
                pool,
                usdcAddress,
                ohmAddress,
                alice,
                swapAmountUsdcIn,
                OHM_USDC_PRICE
            );

            // Swap OHM for USDC
            _swap(pool, ohmAddress, usdcAddress, alice, ohmAmountOut, OHM_USDC_PRICE);
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

        IBunniToken token;
        {
            uint256 USDC_DEPOSIT = (10_000_000e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
            uint256 OHM_DEPOSIT = 10_000_000e9;

            // Deploy the token
            vm.prank(policy);
            token = bunniManager.deployFullRangeToken(address(pool));

            // Mint the non-OHM token to the TRSRY
            usdc.mint(treasuryAddress, USDC_DEPOSIT);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(pool),
                0,
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

            // Swap USDC for OHM
            uint256 ohmAmountOut = _swap(
                pool,
                usdcAddress,
                ohmAddress,
                alice,
                swapAmountUsdcIn,
                OHM_USDC_PRICE
            );

            // Swap OHM for USDC
            _swap(pool, ohmAddress, usdcAddress, alice, ohmAmountOut, OHM_USDC_PRICE);
        }

        _recalculateFees(pool);

        // Simulate time passing
        vm.warp(block.timestamp + elapsed);

        uint256 currentReward = bunniManager.getCurrentHarvestReward();

        // Should remain 0
        assertEq(currentReward, 0, "current reward");
    }

    function test_getCurrentHarvestReward_noFees() public {
        IBunniToken token;
        {
            uint256 USDC_DEPOSIT = (10_000_000e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
            uint256 OHM_DEPOSIT = 10_000_000e9;

            // Deploy the token
            vm.prank(policy);
            token = bunniManager.deployFullRangeToken(address(pool));

            // Mint the non-OHM token to the TRSRY
            usdc.mint(treasuryAddress, USDC_DEPOSIT);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(pool),
                0,
                ohmAddress,
                OHM_DEPOSIT,
                USDC_DEPOSIT,
                SLIPPAGE_DEFAULT
            );
        }

        // No swap

        // Call
        uint256 currentReward = bunniManager.getCurrentHarvestReward();

        // As no swaps have been done, there are no fees
        assertEq(currentReward, 0, "current reward");
    }

    function test_getCurrentHarvestReward(uint48 elapsed_, uint256 swapAmount_) public {
        uint48 elapsed = uint48(bound(elapsed_, HARVEST_FREQUENCY, HARVEST_FREQUENCY * 2));
        uint256 swapAmountUsdcIn = bound(swapAmount_, 100_000e6, 5_000_000e6);

        IBunniToken token;
        {
            uint256 USDC_DEPOSIT = (10_000_000e6 * OHM_USDC_PRICE) / 1e18; // Ensures that the token amounts are in the correct ratio
            uint256 OHM_DEPOSIT = 10_000_000e9;

            // Deploy the token
            vm.prank(policy);
            token = bunniManager.deployFullRangeToken(address(pool));

            // Mint the non-OHM token to the TRSRY
            usdc.mint(treasuryAddress, USDC_DEPOSIT);

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(pool),
                0,
                ohmAddress,
                OHM_DEPOSIT,
                USDC_DEPOSIT,
                SLIPPAGE_DEFAULT
            );

            // Mint USDC into another wallet
            usdc.mint(alice, swapAmountUsdcIn);
        }

        // Swap USDC for OHM
        uint256 swapOneOhmMinimum;
        {
            swapOneOhmMinimum = _swap(
                pool,
                usdcAddress,
                ohmAddress,
                alice,
                swapAmountUsdcIn,
                OHM_USDC_PRICE
            );
        }

        // Swap OHM for USDC
        {
            _swap(pool, ohmAddress, usdcAddress, alice, swapOneOhmMinimum, OHM_USDC_PRICE);
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

        // Warp forward
        vm.warp(block.timestamp + elapsed);

        // Call
        uint256 currentReward = bunniManager.getCurrentHarvestReward();

        // Check that the value is consistent
        assertEq(currentReward, expectedRewardOhm, "expected reward");
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
        bunniManager.deployFullRangeToken(address(pool));

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
            token = bunniManager.deployFullRangeToken(address(pool));
            vm.prank(policy);
            tokenTwo = bunniManager.deployFullRangeToken(address(poolTwo));
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
                0,
                ohmAddress,
                OHM_DEPOSIT,
                USDC_DEPOSIT,
                SLIPPAGE_DEFAULT
            );

            // Deposit
            vm.prank(policy);
            bunniManager.deposit(
                address(poolTwo),
                0,
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

            // Swap USDC for OHM
            uint256 swapOneOhmMinimum = _swap(
                pool,
                usdcAddress,
                ohmAddress,
                alice,
                swapAmountUsdcIn,
                OHM_USDC_PRICE
            );

            // Swap OHM for USDC
            _swap(pool, ohmAddress, usdcAddress, alice, swapOneOhmMinimum, OHM_USDC_PRICE);
        }

        // Perform the swap on the second pool
        {
            uint256 swapAmountUsdcIn = 1_000_000e6;

            // Mint USDC into another wallet
            usdc.mint(alice, swapAmountUsdcIn);

            // Swap USDC for OHM
            uint256 swapOneOhmMinimum = _swap(
                poolTwo,
                usdcAddress,
                ohmAddress,
                alice,
                swapAmountUsdcIn,
                OHM_USDC_PRICE
            );

            // Swap OHM for USDC
            _swap(poolTwo, ohmAddress, usdcAddress, alice, swapOneOhmMinimum, OHM_USDC_PRICE);
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

    // ---------------------------------
    // BunniHub Access Control Tests
    // ---------------------------------

    //  [X] onlyOwner can call
    //      [X] bunniHub.deposit()
    //      [X] bunniHub.withdraw()
    //      [X] bunniHub.updateSwapFees()
    //      [X] bunniHub.compound()
    //      [X] bunniHub.deployBunniToken()

    function testRevert_bunniHub_deposit_onlyOwner() public {
        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployFullRangeToken(address(pool));

        // Construct the parameters
        IBunniHub.DepositParams memory params = IBunniHub.DepositParams({
            key: _getPositionKey(pool, bunniToken),
            amount0Desired: 0,
            amount1Desired: 0,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp,
            recipient: address(TRSRY)
        });

        // Call as an unauthorized user
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        bunniHub.deposit(params);
    }

    function testRevert_bunniHub_withdraw_onlyOwner() public {
        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployFullRangeToken(address(pool));

        // Construct the parameters
        IBunniHub.WithdrawParams memory params = IBunniHub.WithdrawParams({
            key: _getPositionKey(pool, bunniToken),
            recipient: address(TRSRY),
            shares: 0,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // Call as an unauthorized user
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        bunniHub.withdraw(params);
    }

    function testRevert_bunniHub_updateSwapFees_onlyOwner() public {
        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployFullRangeToken(address(pool));
        BunniKey memory key = _getPositionKey(pool, bunniToken);

        // Call as an unauthorized user
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        bunniHub.updateSwapFees(key);
    }

    function testRevert_bunniHub_compound_onlyOwner() public {
        // Deploy the token
        vm.prank(policy);
        IBunniToken bunniToken = bunniManager.deployFullRangeToken(address(pool));
        BunniKey memory key = _getPositionKey(pool, bunniToken);

        // Call as an unauthorized user
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        bunniHub.compound(key);
    }

    function testRevert_bunniHub_deployBunniToken_onlyOwner() public {
        // Get the appropriate BunniKey representing the position
        BunniKey memory key = BunniHelper.getFullRangeBunniKey(address(pool));

        // Call as an unauthorized user
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        bunniHub.deployBunniToken(key);
    }
}
