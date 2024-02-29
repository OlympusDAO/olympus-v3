// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

// Test
import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

// Mocks
import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";

// Libraries
import {FullMath} from "libraries/FullMath.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {ComputeAddress} from "test/libraries/ComputeAddress.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Uniswap V3
import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolState} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import {UniswapV3Pool} from "test/lib/UniswapV3/UniswapV3Pool.sol";
import {SwapRouter} from "test/lib/UniswapV3/SwapRouter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {PoolHelper} from "test/policies/UniswapV3/PoolHelper.sol";

// Bophades Modules
import "src/modules/SPPLY/OlympusSupply.sol";

// SPPLY Submodules
import {BunniSupply} from "src/modules/SPPLY/submodules/BunniSupply.sol";

// Bunni external contracts
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {BunniToken} from "src/external/bunni/BunniToken.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {BunniManager} from "policies/UniswapV3/BunniManager.sol";

import {BunniSetup} from "test/policies/UniswapV3/BunniSetup.sol";

contract BunniSupplyTest is Test {
    using FullMath for uint256;

    MockOhm internal ohmToken;
    MockERC20 internal usdcToken;
    MockERC20 internal wethToken;
    MockGohm internal gohmToken;
    address internal ohmAddress;
    address internal usdcAddress;

    BunniSupply internal submoduleBunniSupply;

    BunniSetup internal bunniSetup;
    BunniManager internal bunniManager;
    IUniswapV3Pool internal uniswapPool;
    BunniHub internal bunniHub;
    BunniLens internal bunniLens;
    IBunniToken internal poolToken;
    BunniKey internal poolTokenKey;
    UniswapV3Factory internal uniswapFactory;
    SwapRouter internal swapRouter;
    address internal bunniLensAddress;
    address internal poolTokenAddress;

    address writePRICE;
    address writeSPPLY;

    address moduleSPPLY;

    address internal policy;

    UserFactory public userFactory;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 0; // 0 OHM

    // OHM-USDC Uni V3 pool, based on: 0x893f503fac2ee1e5b78665db23f9c94017aae97d
    // token0: OHM, token1: USDC
    // Current tick: -44579
    uint160 internal constant OHM_USDC_SQRTPRICEX96 = 8529245188595251053303005012; // From OHM-USDC, 1 OHM = 11.5897 USDC
    // NOTE: these numbers are fudged to match the current tick and default observation window from BunniManager
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_0 = -2463052984970;
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_1 = -2463079732370;

    // OHM-wETH Uni V3 pool, based on: 0x88051b0eea095007d3bef21ab287be961f3d8598
    // Current tick: 156194
    uint160 internal constant OHM_WETH_SQRTPRICEX96 = 195181081174522229204497247535278;

    // OHM-wETH Uni V3 position data based of owner: 0x245cc372c84b3645bf0ffe6538620b04a217988b, NFT Manager ID: 562564
    // Uncollected fees when the snapshot was taken: 150.56 OHM + 0.624 WETH
    int24 internal constant OHM_WETH_POSITION_MAX_TICK = 887270;
    int24 internal constant OHM_WETH_POSITION_MIN_TICK = -887270;
    int24 internal constant OHM_WETH_POSITION_POOL_TICK = 154454;
    uint128 internal constant OHM_WETH_POSITION_LIQUIDITY = 346355586036686019;
    uint256 internal constant OHM_WETH_FEEGROWTH_GLOBAL0X128 =
        11205701999445687247298792212672750145;
    uint256 internal constant OHM_WETH_FEEGROWTH_GLOBAL1X128 =
        22287716690451654021580462247134799297569;
    uint256 internal constant OHM_WETH_FEEGROWTH_INSIDE0X128 = 577885472509760262258387687384625;
    uint256 internal constant OHM_WETH_FEEGROWTH_INSIDE1X128 =
        3680400243297613902976664298891513135263;
    uint256 internal constant OHM_WETH_FEEGROWTH_OUTSIDE0X128 =
        11204976190952130408142737433836235164;
    uint256 internal constant OHM_WETH_FEEGROWTH_OUTSIDE1X128 =
        17993877063330825207041302430485256261193;

    // NOTE: these numbers are fudged to match the current tick and default observation window from BunniManager
    int56 internal constant OHM_WETH_TICK_CUMULATIVE_0 = -2463078395000;
    int56 internal constant OHM_WETH_TICK_CUMULATIVE_1 = -2462984678600;
    uint256 internal constant OHM_WETH_RATIO = 164785850452; // OHM per ETH

    uint8 internal constant PRICE_DECIMALS = 18;

    uint256 internal constant USDC_PRICE = 1 * 10 ** PRICE_DECIMALS;
    uint256 internal constant OHM_PRICE = 115897 * 1e14; // 11.5897 USDC per OHM in 18 decimal places
    uint256 internal constant WETH_PRICE = 2000 * 1e18; // 2000 USDC per WETH in 18 decimal places

    uint256 internal constant OHM_AMOUNT = 100_000e9;
    uint256 internal USDC_AMOUNT = OHM_AMOUNT.mulDiv(OHM_PRICE, 1e18).mulDiv(1e6, 1e9);

    int24 private constant TICK = 887270; // (887272/(500/50))*(500/50)

    uint16 private constant SLIPPAGE_DEFAULT = 100; // 1%

    uint24 private constant POOL_FEE = 500;

    // Events
    event BunniTokenAdded(address token_, address bunniLens_);
    event BunniTokenRemoved(address token_);

    // Moving average data
    uint256 internal constant RESERVES_OHM = 100e9;
    uint256 internal constant RESERVES_USDC = 1000e6;
    uint48 internal lastObservationTime;
    uint32 internal movingAverageDuration = (8 hours) * 3;
    uint256[] internal token0Observations;
    uint256[] internal token1Observations;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            ohmToken = new MockOhm("Olympus", "OHM", 9);

            // The USDC address needs to be higher than ohm, so generate a salt to ensure that
            bytes32 usdcSalt = ComputeAddress.generateSalt(
                address(ohmToken),
                true,
                type(MockERC20).creationCode,
                abi.encode("USDC", "USDC", 6),
                address(this)
            );
            usdcToken = new MockERC20{salt: usdcSalt}("USDC", "USDC", 6);

            // The WETH address needs to be higher than ohm, so generate a salt to ensure that
            bytes32 wethSalt = ComputeAddress.generateSalt(
                address(ohmToken),
                true,
                type(MockERC20).creationCode,
                abi.encode("Wrapped Ether", "wETH", 18),
                address(this)
            );
            wethToken = new MockERC20{salt: wethSalt}("Wrapped Ether", "wETH", 18);

            // The address of gOHM does not need to be deterministic
            gohmToken = new MockGohm(GOHM_INDEX);

            ohmAddress = address(ohmToken);
            usdcAddress = address(usdcToken);
        }

        // Locations
        {
            userFactory = new UserFactory();
            address[] memory users = userFactory.create(1);
            policy = users[0];
        }

        // Deploy BunniSetup
        {
            bunniSetup = new BunniSetup(ohmAddress, address(gohmToken), address(this), policy);

            bunniManager = bunniSetup.bunniManager();
            bunniHub = bunniSetup.bunniHub();
            bunniLens = bunniSetup.bunniLens();
            bunniLensAddress = address(bunniLens);
            uniswapFactory = bunniSetup.uniswapFactory();
            swapRouter = new SwapRouter(address(uniswapFactory), address(wethToken));
            moduleSPPLY = address(bunniSetup.SPPLY());
        }

        // Deploy writer policies
        {
            (address writePRICE_, address writeSPPLY_, ) = bunniSetup.createWriterPolicies();

            writePRICE = writePRICE_;
            writeSPPLY = writeSPPLY_;
        }

        // Set up the submodule(s)
        {
            (, address supply_) = bunniSetup.createSubmodules(writePRICE, writeSPPLY);

            submoduleBunniSupply = BunniSupply(supply_);
        }

        // Mock values, to avoid having to set up all of PRICEv2 and submodules
        {
            bunniSetup.mockGetPrice(ohmAddress, OHM_PRICE);
            bunniSetup.mockGetPrice(usdcAddress, USDC_PRICE);
            bunniSetup.mockGetPrice(address(wethToken), WETH_PRICE);
        }

        // Set up the UniV3 pool
        {
            (IUniswapV3Pool pool_, BunniKey memory key_, IBunniToken poolToken_) = _setUpPool(
                ohmAddress,
                usdcAddress,
                OHM_USDC_SQRTPRICEX96,
                OHM_USDC_TICK_CUMULATIVE_0,
                OHM_USDC_TICK_CUMULATIVE_1
            );

            uniswapPool = pool_;
            poolToken = poolToken_;
            poolTokenAddress = address(poolToken_);
            poolTokenKey = key_;
        }

        // Deposit into the pool
        {
            // Mint USDC
            usdcToken.mint(address(bunniSetup.TRSRY()), USDC_AMOUNT);

            // Deposit
            vm.startPrank(policy);
            bunniManager.deposit(
                address(uniswapPool),
                ohmAddress,
                OHM_AMOUNT,
                USDC_AMOUNT,
                SLIPPAGE_DEFAULT
            );
            vm.stopPrank();
        }

        // Moving average
        {
            lastObservationTime = uint48(block.timestamp) - (8 hours) + 1; // Ensures that it is not yet stale
            // 3 observations required
            token0Observations = new uint256[](3);
            token0Observations[0] = RESERVES_OHM;
            token0Observations[1] = RESERVES_OHM;
            token0Observations[2] = RESERVES_OHM;
            token1Observations = new uint256[](3);
            token1Observations[0] = RESERVES_USDC;
            token1Observations[1] = RESERVES_USDC;
            token1Observations[2] = RESERVES_USDC;
        }
    }

    function _getOhmReserves(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        if (key_.pool.token0() == ohmAddress) {
            return reserve0;
        } else if (key_.pool.token1() == ohmAddress) {
            return reserve1;
        } else {
            return 0;
        }
    }

    function _getReserves(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (uint256, uint256) {
        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        return (reserve0, reserve1);
    }

    function _getUncollectedFees(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (uint256, uint256) {
        (uint256 fee0, uint256 fee1) = lens_.getUncollectedFees(key_);
        return (fee0, fee1);
    }

    function _expectRevert_invalidBunniToken(address token_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            token_
        );
        vm.expectRevert(err);
    }

    function _expectRevert_invalidBunniLens(address lens_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniLens.selector,
            lens_
        );
        vm.expectRevert(err);
    }

    function _getBunniKey(
        IUniswapV3Pool pool_,
        IBunniToken token_
    ) internal view returns (BunniKey memory) {
        return
            BunniKey({pool: pool_, tickLower: token_.tickLower(), tickUpper: token_.tickUpper()});
    }

    function _setUpPool(
        address token0_,
        address token1_,
        uint160 sqrtPriceX96_,
        int56 sqrtPriceX96Cumulative0_,
        int56 sqrtPriceX96Cumulative1_
    ) internal returns (IUniswapV3Pool, BunniKey memory, IBunniToken) {
        address poolAddress_ = bunniSetup.setUpPool(token0_, token1_, POOL_FEE, sqrtPriceX96_);

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress_);

        // Mock observations for the Uniswap V3 pool
        bunniSetup.mockPoolObservations(
            address(pool),
            600, // TODO remove?
            sqrtPriceX96Cumulative0_,
            sqrtPriceX96Cumulative1_
        );

        // Deploy a pool token
        vm.prank(policy);
        IBunniToken poolToken_ = bunniManager.deployPoolToken(address(pool));

        return (pool, _getBunniKey(pool, poolToken_), poolToken_);
    }

    function _depositIntoPool(
        IUniswapV3Pool uniswapPool_,
        MockERC20 otherToken_,
        uint256 otherAmount_,
        uint256 ohmAmount_
    ) internal {
        // Mint USDC
        otherToken_.mint(address(bunniSetup.TRSRY()), otherAmount_);

        // Deposit
        vm.startPrank(policy);
        bunniManager.deposit(
            address(uniswapPool_),
            ohmAddress,
            ohmAmount_,
            otherAmount_,
            SLIPPAGE_DEFAULT
        );
        vm.stopPrank();
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

    function _mockPoolUnlocked(IUniswapV3Pool pool_, bool unlocked_) internal {
        // Get the current values for slot0
        UniswapV3Pool.Slot0 memory slot0;
        {
            (
                uint160 sqrtPriceX96,
                int24 tick,
                uint16 obsIndex,
                uint16 obsCard,
                uint16 obsCardNext,
                uint8 feeProtocol,

            ) = pool_.slot0();

            slot0 = UniswapV3Pool.Slot0({
                sqrtPriceX96: sqrtPriceX96,
                tick: tick,
                observationIndex: obsIndex,
                observationCardinality: obsCard,
                observationCardinalityNext: obsCardNext,
                feeProtocol: feeProtocol,
                unlocked: unlocked_
            });
        }

        vm.mockCall(
            address(pool_),
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(slot0)
        );
    }

    // =========  TESTS ========= //

    // =========  Module Information ========= //

    // [X] Submodule
    //  [X] Version
    //  [X] Subkeycode

    function test_submodule_version() public {
        uint8 major;
        uint8 minor;
        (major, minor) = submoduleBunniSupply.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_submodule_parent() public {
        assertEq(fromKeycode(submoduleBunniSupply.PARENT()), "SPPLY");
    }

    function test_submodule_subkeycode() public {
        assertEq(fromSubKeycode(submoduleBunniSupply.SUBKEYCODE()), "SPPLY.BNI");
    }

    // [X] Constructor
    //  [X] Incorrect parent

    function test_submodule_parent_notModule_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // There's no error message, so just check that a revert happens when attempting to call the module
        vm.expectRevert();

        new BunniSupply(Module(newLocations[0]));
    }

    function test_submodule_parent_notSpply_reverts() public {
        // Pass the PRICEv2 module as the parent
        Module modulePrice = bunniSetup.PRICE();

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        new BunniSupply(modulePrice);
    }

    // =========  getCollateralizedOhm ========= //

    // [X] getCollateralizedOhm

    function test_getCollateralizedOhm() public {
        // Register the pool with the submodule
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Will always be zero
        assertEq(submoduleBunniSupply.getCollateralizedOhm(), 0);
    }

    // =========  getProtocolOwnedBorrowableOhm ========= //

    // [X] getProtocolOwnedBorrowableOhm

    function test_getProtocolOwnedBorrowableOhm() public {
        // Register the pool with the submodule
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Will always be zero
        assertEq(submoduleBunniSupply.getProtocolOwnedBorrowableOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityOhm ========= //

    // [X] getProtocolOwnedLiquidityOhm
    //  [X] no tokens
    //  [X] single token
    //  [X] multiple tokens
    // [X] uses the average of the reserves
    // [X] given the last observation is stale
    //  [X] it reverts

    function test_getProtocolOwnedLiquidityOhm_stale_reverts() public {
        lastObservationTime = uint48(block.timestamp) - (8 hours) - 1; // Ensures that it is stale

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_MovingAverageStale.selector,
            poolTokenAddress,
            lastObservationTime
        );
        vm.expectRevert(err);

        submoduleBunniSupply.getProtocolOwnedLiquidityOhm();
    }

    function test_getProtocolOwnedLiquidityOhm_noTokens() public {
        // Don't add the token

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), 0);
    }

    function test_getProtocolOwnedLiquidityOhm_singleToken() public {
        // There should not be any uncollected fees
        (uint256 fee0, uint256 fee1) = bunniLens.getUncollectedFees(poolTokenKey);
        assertEq(fee0, 0);
        assertEq(fee1, 0);

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), RESERVES_OHM);
    }

    function test_getProtocolOwnedLiquidityOhm_singleToken_usesAverage() public {
        // There should not be any uncollected fees
        (uint256 fee0, uint256 fee1) = bunniLens.getUncollectedFees(poolTokenKey);
        assertEq(fee0, 0);
        assertEq(fee1, 0);

        // Adjust the reserves
        token0Observations = new uint256[](3);
        token0Observations[0] = 100e9;
        token0Observations[1] = 115e9;
        token0Observations[2] = 160e9;
        uint256 expectedReserves = (100e9 + 115e9 + 160e9) / 3;

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), expectedReserves);
    }

    function test_getProtocolOwnedLiquidityOhm_singleToken_nonOhm() public {
        // Create a pool for USDC-wETH
        uint160 sqrtPriceX96 = 1651110453284116999273880031420733;
        int56 tickCumulative0 = 16747065014315;
        int56 tickCumulative1 = 16747184355551;
        (IUniswapV3Pool pool_, , IBunniToken poolToken_) = _setUpPool(
            usdcAddress,
            address(wethToken),
            sqrtPriceX96,
            tickCumulative0,
            tickCumulative1
        );

        // Deposit into the pool
        uint256 wethPrice = 2303e18;
        uint256 usdcAmount = 100_000e6;
        uint256 wethAmount = usdcAmount.mulDiv(1e18, 1e6).mulDiv(1e18, wethPrice);
        usdcToken.mint(address(bunniSetup.TRSRY()), usdcAmount);
        wethToken.mint(address(bunniSetup.TRSRY()), wethAmount);

        vm.startPrank(policy);
        bunniManager.deposit(
            address(pool_),
            address(wethToken),
            wethAmount,
            usdcAmount,
            SLIPPAGE_DEFAULT
        );
        vm.stopPrank();

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            address(poolToken_),
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), 0);
    }

    // =========  getProtocolOwnedTreasuryOhm  ========= //

    function test_getProtocolOwnedTreasuryOhm() public {
        // Register the pool with the submodule
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Will always be zero
        assertEq(submoduleBunniSupply.getProtocolOwnedTreasuryOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityReserves ========= //

    // [X] getProtocolOwnedLiquidityReserves
    //  [X] no tokens
    //  [X] single token
    //  [X] multiple tokens
    //  [X] reverts on TWAP deviation
    //  [X] respects observation window
    //  [X] respects deviation
    // [X] uses the average of the reserves
    // [X] given the last observation is stale
    //  [X] it reverts

    function test_getProtocolOwnedLiquidityReserves_stale_reverts() public {
        lastObservationTime = uint48(block.timestamp) - (8 hours) - 1; // Ensures that it is stale

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_MovingAverageStale.selector,
            poolTokenAddress,
            lastObservationTime
        );
        vm.expectRevert(err);

        submoduleBunniSupply.getProtocolOwnedLiquidityReserves();
    }

    function test_getProtocolOwnedLiquidityReserves_noTokens() public {
        // Don't add the token

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 0);
    }

    function test_getProtocolOwnedLiquidityReserves_singleToken() public {
        // There should not be any uncollected fees
        (uint256 fee0, uint256 fee1) = bunniLens.getUncollectedFees(poolTokenKey);
        assertEq(fee0, 0);
        assertEq(fee1, 0);

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], RESERVES_OHM);
        assertEq(reserves[0].balances[1], RESERVES_USDC);
    }

    function test_getProtocolOwnedLiquidityReserves_singleToken_usesAverage() public {
        // There should not be any uncollected fees
        (uint256 fee0, uint256 fee1) = bunniLens.getUncollectedFees(poolTokenKey);
        assertEq(fee0, 0);
        assertEq(fee1, 0);

        // Adjust the reserves
        token0Observations = new uint256[](3);
        token0Observations[0] = 100e9;
        token0Observations[1] = 115e9;
        token0Observations[2] = 160e9;
        uint256 expectedReservesOHM = (100e9 + 115e9 + 160e9) / 3;

        token1Observations = new uint256[](3);
        token1Observations[0] = 1000e6;
        token1Observations[1] = 1150e6;
        token1Observations[2] = 1600e6;
        uint256 expectedReservesUSDC = (1000e6 + 1150e6 + 1600e6) / 3;

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], expectedReservesOHM);
        assertEq(reserves[0].balances[1], expectedReservesUSDC);
    }

    function test_getProtocolOwnedLiquidityReserves_multipleToken() public {
        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Set up a second pool and token
        (, , IBunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wethToken),
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        // _depositIntoPool(poolTwo, wethToken, 10e18, (10e18 * OHM_WETH_RATIO) / 1e18);

        uint256[] memory poolTwoToken0Observations = new uint256[](3);
        poolTwoToken0Observations[0] = 10e18;
        poolTwoToken0Observations[1] = 10e18;
        poolTwoToken0Observations[2] = 10e18;
        uint256[] memory poolTwoToken1Observations = new uint256[](3);
        poolTwoToken1Observations[0] = 11e18;
        poolTwoToken1Observations[1] = 11e18;
        poolTwoToken1Observations[2] = 11e18;

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            address(poolTokenTwo),
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            poolTwoToken0Observations,
            poolTwoToken1Observations
        );

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 2);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], RESERVES_OHM);
        assertEq(reserves[0].balances[1], RESERVES_USDC);

        assertEq(reserves[1].source, address(poolTokenTwo));
        assertEq(reserves[1].tokens.length, 2);
        assertEq(reserves[1].tokens[0], ohmAddress);
        assertEq(reserves[1].tokens[1], address(wethToken));
        assertEq(reserves[1].balances.length, 2);
        assertEq(reserves[1].balances[0], 10e18);
        assertEq(reserves[1].balances[1], 11e18);
    }

    // =========  getUncollectedFees ========= //

    // [X] matches the values that the Uniswap UI and revert.finance show

    function test_bunniLens_uncollectedFees() public {
        // Register one token
        vm.prank(address(moduleSPPLY));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Mock the pool state to match the data from when the uncollected fee snapshot was taken
        bunniSetup.mockPoolTick(address(uniswapPool), OHM_WETH_POSITION_POOL_TICK);
        bunniSetup.mockPoolTicks(
            address(uniswapPool),
            OHM_WETH_POSITION_MIN_TICK,
            OHM_WETH_FEEGROWTH_OUTSIDE0X128,
            OHM_WETH_FEEGROWTH_OUTSIDE1X128
        );
        bunniSetup.mockPoolPosition(
            address(uniswapPool),
            OHM_WETH_POSITION_MIN_TICK,
            OHM_WETH_POSITION_MAX_TICK,
            OHM_WETH_POSITION_LIQUIDITY,
            OHM_WETH_FEEGROWTH_INSIDE0X128,
            OHM_WETH_FEEGROWTH_INSIDE1X128,
            0,
            0
        );
        bunniSetup.mockPoolFeeGrowthGlobal(
            address(uniswapPool),
            OHM_WETH_FEEGROWTH_GLOBAL0X128,
            OHM_WETH_FEEGROWTH_GLOBAL1X128
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmFee_, uint256 wethFee_) = _getUncollectedFees(poolTokenKey, bunniLens);
        assertEq(ohmFee_ / 1e7, 15056); // 150.56 OHM
        assertEq(wethFee_ / 1e15, 624); // 0.624 WETH
    }

    // =========  addBunniToken ========= //

    // [X] addBunniToken
    //  [X] reverts if not parent
    //  [X] reverts if token is address(0)
    //  [X] reverts if lens is address(0)
    //  [X] reverts if token already added
    //  [X] reverts if invalid token
    //  [X] reverts if invalid lens
    //  [X] reverts if token and lens hub addresses don't match
    //  [X] reverts in TWAP deviation is invalid
    //  [X] reverts if observation window is invalid
    //  [X] single token
    //  [X] multiple tokens, single lens
    //  [X] multiple tokens, multiple lenses
    // [X] when the last observation time is in the future
    //  [X] it reverts
    // [X] when the moving average duration is 0
    //  [X] it reverts
    // [X] when the moving average duration is not a multiple of the observation frequency
    //  [X] it reverts
    // [X] when the required number of observations is < 2
    //  [X] it reverts
    // [X] when the number of token0 observations is not equal to the number of required observations
    //  [X] it reverts
    // [X] when the number of token1 observations is not equal to the number of required observations
    //  [X] it reverts
    // [X] when a token0 observation is 0
    //  [X] it reverts
    // [X] when a token1 observation is 0
    //  [X] it reverts
    // [X] the moving average is updated correctly

    function test_addBunniToken_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writeSPPLY)
        );
        vm.expectRevert(err);

        vm.prank(writeSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_tokenAddressZero_reverts() public {
        _expectRevert_invalidBunniToken(address(0));

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            address(0),
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_lensAddressZero_reverts() public {
        _expectRevert_invalidBunniLens(address(0));

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            address(0),
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_alreadyAdded_reverts() public {
        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        _expectRevert_invalidBunniToken(poolTokenAddress);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_invalidTokenReverts() public {
        _expectRevert_invalidBunniToken(ohmAddress);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            ohmAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_invalidLensReverts() public {
        _expectRevert_invalidBunniLens(ohmAddress);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            ohmAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_hubMismatchReverts() public {
        // Deploy a new hub
        BunniHub newBunniHub = new BunniHub(
            uniswapFactory,
            policy,
            0 // No protocol fee
        );

        // Deploy a new lens
        BunniLens newBunniLens = new BunniLens(newBunniHub);

        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_HubMismatch.selector,
            address(bunniHub),
            address(newBunniHub)
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            address(newBunniLens),
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_lastObservationTime_inFuture_reverts() public {
        lastObservationTime = uint48(block.timestamp) + 1; // Ensures that it is in the future

        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidLastObservationTime.selector,
            poolTokenAddress,
            lastObservationTime
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_movingAverageDuration_zero_reverts() public {
        movingAverageDuration = 0;

        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidMovingAverageDuration.selector,
            movingAverageDuration
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_movingAverageDuration_notMultipleOfObservationFrequency_reverts()
        public
    {
        movingAverageDuration = 9 hours;

        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidMovingAverageDuration.selector,
            movingAverageDuration
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_requiredObservations_lessThanTwo_reverts() public {
        movingAverageDuration = 8 hours;
        token0Observations = new uint256[](1);
        token0Observations[0] = RESERVES_OHM;
        token1Observations = new uint256[](1);
        token1Observations[0] = RESERVES_USDC;

        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidObservationsLength.selector,
            1
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_token0ObservationMismatch_reverts() public {
        token0Observations = new uint256[](2);
        token0Observations[0] = 100e9;
        token0Observations[1] = 115e9;

        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidObservationsLength.selector,
            3
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_token1ObservationMismatch_reverts() public {
        token1Observations = new uint256[](2);
        token1Observations[0] = 1000e6;
        token1Observations[1] = 1150e6;

        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidObservationsLength.selector,
            3
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_token0ObservationZero_reverts(uint8 index_) public {
        uint8 index = uint8(bound(index_, 0, 2));

        token0Observations = new uint256[](3);
        token0Observations[0] = index == 0 ? 0 : RESERVES_OHM;
        token0Observations[1] = index == 1 ? 0 : RESERVES_OHM;
        token0Observations[2] = index == 2 ? 0 : RESERVES_OHM;

        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidObservation.selector,
            poolTokenAddress,
            index
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken_token1ObservationZero_reverts(uint8 index_) public {
        uint8 index = uint8(bound(index_, 0, 2));

        token1Observations = new uint256[](3);
        token1Observations[0] = index == 0 ? 0 : RESERVES_USDC;
        token1Observations[1] = index == 1 ? 0 : RESERVES_USDC;
        token1Observations[2] = index == 2 ? 0 : RESERVES_USDC;

        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidObservation.selector,
            poolTokenAddress,
            index
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_addBunniToken() public {
        // Expect an event
        vm.expectEmit(true, true, false, true);
        emit BunniTokenAdded(poolTokenAddress, bunniLensAddress);

        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Check that the token was added
        (BunniToken bunniToken_, BunniLens bunniLens_) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenAddress);
        assertEq(address(bunniLens_), bunniLensAddress);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);

        // Check that the moving average was updated
        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), RESERVES_OHM);
    }

    function test_addBunniToken_multipleTokens_singleLens() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Set up a second pool and token
        (, , IBunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wethToken),
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Expect an event
        vm.expectEmit(true, true, false, true);
        emit BunniTokenAdded(poolTokenTwoAddress, bunniLensAddress);

        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Check that the token was added
        (BunniToken bunniToken_, BunniLens bunniLens_) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenAddress);
        assertEq(address(bunniLens_), bunniLensAddress);

        (BunniToken bunniTokenTwo_, BunniLens bunniLensTwo_) = submoduleBunniSupply.bunniTokens(1);
        assertEq(address(bunniTokenTwo_), poolTokenTwoAddress);
        assertEq(address(bunniLensTwo_), bunniLensAddress);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 2);
    }

    function test_addBunniToken_multipleTokens_multipleLenses() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Set up a second pool and token
        (, , IBunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wethToken),
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Set up a new Lens
        BunniLens bunniLensTwo = new BunniLens(bunniHub);
        address bunniLensTwoAddress = address(bunniLensTwo);

        // Expect an event
        vm.expectEmit(true, true, false, true);
        emit BunniTokenAdded(poolTokenTwoAddress, bunniLensTwoAddress);

        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensTwoAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Check that the token was added
        (BunniToken bunniToken_, BunniLens bunniLens_) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenAddress);
        assertEq(address(bunniLens_), bunniLensAddress);

        (BunniToken bunniTokenTwo_, BunniLens bunniLensTwo_) = submoduleBunniSupply.bunniTokens(1);
        assertEq(address(bunniTokenTwo_), poolTokenTwoAddress);
        assertEq(address(bunniLensTwo_), bunniLensTwoAddress);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 2);
    }

    // =========  removeBunniToken ========= //

    // [X] removeBunniToken
    //  [X] reverts if not parent
    //  [X] reverts if address(0)
    //  [X] reverts if not added
    //  [X] single token
    //  [X] multiple tokens, single lens
    //  [X] multiple tokens, multiple lenses
    //  [X] it removes the moving average data

    function test_removeBunniToken_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writeSPPLY)
        );
        vm.expectRevert(err);

        vm.prank(writeSPPLY);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken_addressZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            address(0)
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.removeBunniToken(address(0));
    }

    function test_removeBunniToken_notAdded_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            poolTokenAddress
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        assertEq(submoduleBunniSupply.bunniTokenCount(), 0);
        assertEq(submoduleBunniSupply.getCollateralizedOhm(), 0);

        // Check that the moving average data was removed
        (
            ,
            ,
            uint32 movingAverageDuration_,
            uint48 lastObservationTime_,
            uint256 token0CumulativeObservations_,
            uint256 token1CumulativeObservations_
        ) = submoduleBunniSupply.tokenMovingAverages(poolTokenAddress);
        assertEq(movingAverageDuration_, 0);
        assertEq(lastObservationTime_, 0);
        assertEq(token0CumulativeObservations_, 0);
        assertEq(token1CumulativeObservations_, 0);
    }

    function test_removeBunniToken_multipleTokens_singleLens() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Set up a second pool and token
        (, , IBunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wethToken),
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove one of the tokens
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        (BunniToken bunniToken_, BunniLens bunniLens_) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenTwoAddress);
        assertEq(address(bunniLens_), bunniLensAddress);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
    }

    function test_removeBunniToken_multipleTokens_multipleLenses() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Set up a second pool and token
        (, , IBunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wethToken),
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Set up a new Lens
        BunniLens bunniLensTwo = new BunniLens(bunniHub);
        address bunniLensTwoAddress = address(bunniLensTwo);

        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensTwoAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove one of the tokens
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        (BunniToken bunniToken_, BunniLens bunniLens_) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenTwoAddress);
        assertEq(address(bunniLens_), bunniLensTwoAddress);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
    }

    // =========  hasBunniToken ========= //

    // [X] hasBunniToken
    //  [X] false if address(0)
    //  [X] false if not added
    //  [X] true if added

    function test_hasBunniToken_addressZero() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Call
        bool hasToken = submoduleBunniSupply.hasBunniToken(address(0));

        // Check
        assertFalse(hasToken);
    }

    function test_hasBunniToken_differentAddress() public {
        // Do NOT add Bunni Token to BunniSupply

        // Call
        bool hasToken = submoduleBunniSupply.hasBunniToken(poolTokenAddress);

        // Check
        assertFalse(hasToken);
    }

    function test_hasBunniToken() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Call
        bool hasToken = submoduleBunniSupply.hasBunniToken(poolTokenAddress);

        // Check
        assertTrue(hasToken);
    }

    // =========  updateTokenMovingAverage ========= //

    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the token cannot be found
    //  [X] it reverts
    // [X] when the last observation time is in the future
    //  [X] it reverts
    // [X] when the moving average duration is 0
    //  [X] it reverts
    // [X] when the moving average duration is not a multiple of the observation frequency
    //  [X] it reverts
    // [X] when the required number of observations is < 2
    //  [X] it reverts
    // [X] when the number of token0 observations is not equal to the number of required observations
    //  [X] it reverts
    // [X] when the number of token1 observations is not equal to the number of required observations
    //  [X] it reverts
    // [X] when a token0 observation is 0
    //  [X] it reverts
    // [X] when a token1 observation is 0
    //  [X] it reverts
    // [X] the moving average is updated correctly

    function test_updateTokenMovingAverage_notParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        // Call the function
        submoduleBunniSupply.updateTokenMovingAverage(
            poolTokenAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_updateTokenMovingAverage_tokenNotFound_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            poolTokenAddress
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.updateTokenMovingAverage(
            poolTokenAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_updateTokenMovingAverage_lastObservationTime_inFuture_reverts() public {
        // Add the token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        lastObservationTime = uint48(block.timestamp) + 1; // Ensures that it is in the future

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidLastObservationTime.selector,
            poolTokenAddress,
            lastObservationTime
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.updateTokenMovingAverage(
            poolTokenAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_updateTokenMovingAverage_movingAverageDuration_zero_reverts() public {
        // Add the token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        movingAverageDuration = 0;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidMovingAverageDuration.selector,
            movingAverageDuration
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.updateTokenMovingAverage(
            poolTokenAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_updateTokenMovingAverage_movingAverageDuration_notMultipleOfObservationFrequency_reverts()
        public
    {
        // Add the token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        movingAverageDuration = 9 hours;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidMovingAverageDuration.selector,
            movingAverageDuration
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.updateTokenMovingAverage(
            poolTokenAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_updateTokenMovingAverage_requiredObservations_lessThanTwo_reverts() public {
        // Add the token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        movingAverageDuration = 8 hours;
        token0Observations = new uint256[](1);
        token0Observations[0] = RESERVES_OHM;
        token1Observations = new uint256[](1);
        token1Observations[0] = RESERVES_USDC;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidObservationsLength.selector,
            1
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.updateTokenMovingAverage(
            poolTokenAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_updateTokenMovingAverage_token0ObservationMismatch_reverts() public {
        // Add the token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        token0Observations = new uint256[](2);
        token0Observations[0] = 100e9;
        token0Observations[1] = 115e9;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidObservationsLength.selector,
            3
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.updateTokenMovingAverage(
            poolTokenAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_updateTokenMovingAverage_token1ObservationMismatch_reverts() public {
        // Add the token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        token1Observations = new uint256[](2);
        token1Observations[0] = 1000e6;
        token1Observations[1] = 1150e6;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidObservationsLength.selector,
            3
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.updateTokenMovingAverage(
            poolTokenAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_updateTokenMovingAverage_token0ObservationZero_reverts(uint8 index_) public {
        uint8 index = uint8(bound(index_, 0, 2));

        // Add the token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        token0Observations = new uint256[](3);
        token0Observations[0] = index == 0 ? 0 : RESERVES_OHM;
        token0Observations[1] = index == 1 ? 0 : RESERVES_OHM;
        token0Observations[2] = index == 2 ? 0 : RESERVES_OHM;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidObservation.selector,
            poolTokenAddress,
            index
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.updateTokenMovingAverage(
            poolTokenAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_updateTokenMovingAverage_token1ObservationZero_reverts(uint8 index_) public {
        uint8 index = uint8(bound(index_, 0, 2));

        // Add the token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        token1Observations = new uint256[](3);
        token1Observations[0] = index == 0 ? 0 : RESERVES_USDC;
        token1Observations[1] = index == 1 ? 0 : RESERVES_USDC;
        token1Observations[2] = index == 2 ? 0 : RESERVES_USDC;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidObservation.selector,
            poolTokenAddress,
            index
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.updateTokenMovingAverage(
            poolTokenAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );
    }

    function test_updateTokenMovingAverage() public {
        // Add the token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Amend the parameters
        movingAverageDuration = 2 days;
        lastObservationTime = uint48(block.timestamp) - 1;
        token0Observations = new uint256[](6);
        token0Observations[0] = 101e9;
        token0Observations[1] = 101e9;
        token0Observations[2] = 101e9;
        token0Observations[3] = 101e9;
        token0Observations[4] = 101e9;
        token0Observations[5] = 101e9;
        token1Observations = new uint256[](6);
        token1Observations[0] = 1010e6;
        token1Observations[1] = 1010e6;
        token1Observations[2] = 1010e6;
        token1Observations[3] = 1010e6;
        token1Observations[4] = 1010e6;
        token1Observations[5] = 1010e6;

        // Call the function
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.updateTokenMovingAverage(
            poolTokenAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Check that the moving average was updated
        (
            uint16 nextObservationIndex_,
            uint16 numObservations_,
            uint32 movingAverageDuration_,
            uint48 lastObservationTime_,
            uint256 token0CumulativeObservations_,
            uint256 token1CumulativeObservations_
        ) = submoduleBunniSupply.tokenMovingAverages(poolTokenAddress);
        assertEq(nextObservationIndex_, 0);
        assertEq(numObservations_, 6);
        assertEq(movingAverageDuration_, 2 days);
        assertEq(lastObservationTime_, lastObservationTime);
        assertEq(token0CumulativeObservations_, 101e9 * 6);
        assertEq(token1CumulativeObservations_, 1010e6 * 6);

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), 101e9);
    }

    // =========  storeObservations ========= //

    // [X] when the caller is not the parent
    //  [X] it reverts
    // [ ] given not enough time has elapsed
    //  [ ] it reverts
    // [X] it stores the current reserves and uncollected fees and updates the moving average

    function test_storeObservations_notParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        // Call the function
        submoduleBunniSupply.storeObservations();
    }

    function test_storeObservations_singleToken_uncollectedFeesDuzz(
        uint256 usdcSwapAmount_
    ) public {
        // Swap enough to generate fees, but not enough to trigger a TWAP deviation
        uint256 usdcSwapAmount = uint256(bound(usdcSwapAmount_, 1_000e6, 10_000e6));

        // Swap USDC for OHM
        uint256 swapOneAmountOut;
        {
            // Mint the USDC
            usdcToken.mint(address(this), usdcSwapAmount);

            // Swap
            swapOneAmountOut = _swap(
                uniswapPool,
                usdcAddress,
                ohmAddress,
                address(this),
                usdcSwapAmount,
                OHM_PRICE
            );
        }

        // Update the swap fees, so that fees are re-calculated
        vm.prank(policy);
        bunniManager.updateSwapFees();

        // Swap OHM for USDC
        {
            // Swap
            _swap(uniswapPool, ohmAddress, usdcAddress, address(this), swapOneAmountOut, OHM_PRICE);
        }

        // There should now be fees that are not yet calculated

        // There should now be uncollected fees
        // If getUncollectedFees() does not include the calculated fees, then this will fail
        (uint256 fee0, uint256 fee1) = bunniLens.getUncollectedFees(poolTokenKey);
        assertGt(fee0, 0);
        assertGt(fee1, 0);

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);

        // Store the observations
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.storeObservations();

        // Calculate new averages
        uint256 expectedReservesOhm = (token0Observations[1] +
            token0Observations[2] +
            ohmReserves_ +
            fee0) / 3;
        uint256 expectedReservesUsdc = (token1Observations[1] +
            token1Observations[2] +
            usdcReserves_ +
            fee1) / 3;

        // Check the values stored
        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], expectedReservesOhm);
        assertEq(reserves[0].balances[1], expectedReservesUsdc);

        // Check that the reserves and OHM values are consistent
        assertEq(reserves[0].balances[0], submoduleBunniSupply.getProtocolOwnedLiquidityOhm());
    }

    function test_getUncollectedFees_uncollectedFeesInvariant(uint256 usdcSwapAmount_) public {
        // CASE 1: BEFORE SWAP
        // No fees have been earned, so there shouldn't be any uncollected or cached fees.
        (uint256 uncollected0_c1, uint256 uncollected1_c1) = bunniLens.getUncollectedFees(
            poolTokenKey
        );
        assertEq(uncollected0_c1, 0, "uncollected0_c1");
        assertEq(uncollected1_c1, 0, "uncollected1_c1");
        (, , , uint128 cached0_c1, uint128 cached1_c1) = poolTokenKey.pool.positions(
            keccak256(
                abi.encodePacked(address(bunniHub), poolTokenKey.tickLower, poolTokenKey.tickUpper)
            )
        );
        assertEq(cached0_c1, 0, "cached0_c1");
        assertEq(cached1_c1, 0, "cached1_c1");

        // Swap enough to generate fees, but not enough to trigger a TWAP deviation
        uint256 usdcSwapAmount = uint256(bound(usdcSwapAmount_, 1_000e6, 10_000e6));

        // Swap USDC for OHM
        uint256 swapOneAmountOut;
        {
            // Mint the USDC
            usdcToken.mint(address(this), usdcSwapAmount);

            // Swap
            swapOneAmountOut = _swap(
                uniswapPool,
                usdcAddress,
                ohmAddress,
                address(this),
                usdcSwapAmount,
                OHM_PRICE
            );
        }

        // Swap OHM for USDC
        {
            // Swap
            _swap(uniswapPool, ohmAddress, usdcAddress, address(this), swapOneAmountOut, OHM_PRICE);
        }

        // CASE 2: AFTER THE SWAP + BEFORE THE FEE UPDATE
        // Fees have been earned, but not yet updated. There should be uncollected fees, but no cached fees.
        (uint256 uncollected0_c2, uint256 uncollected1_c2) = bunniLens.getUncollectedFees(
            poolTokenKey
        );
        assertGt(uncollected0_c2, 0, "uncollected0_c2");
        assertGt(uncollected1_c2, 0, "uncollected1_c2");
        (, , , uint128 cached0_c2, uint128 cached1_c2) = poolTokenKey.pool.positions(
            keccak256(
                abi.encodePacked(address(bunniHub), poolTokenKey.tickLower, poolTokenKey.tickUpper)
            )
        );
        assertEq(cached0_c2, 0, "cached0_c2");
        assertEq(cached1_c2, 0, "cached1_c2");

        vm.prank(address(bunniManager));
        (uint256 collected0, uint256 collected1) = bunniHub.updateSwapFees(poolTokenKey);
        assertEq(collected0, uncollected0_c2, "updateSwapFees0");
        assertEq(collected1, uncollected1_c2, "updateSwapFees1");

        // CASE 3: AFTER THE SWAP + AFTER THE FEE UPDATE
        // Fees have been earned and updated. Cached fees should now be equal to uncollected fees.
        (uint256 uncollected0_c3, uint256 uncollected1_c3) = bunniLens.getUncollectedFees(
            poolTokenKey
        );
        // Check fee invariant between CASE 2 and CASE 3.
        assertEq(uncollected0_c3, uncollected0_c2, "uncollected0_c3");
        assertEq(uncollected1_c3, uncollected1_c2, "uncollected1_c3");
        (, , , uint128 cached0_c3, uint128 cached1_c3) = poolTokenKey.pool.positions(
            keccak256(
                abi.encodePacked(address(bunniHub), poolTokenKey.tickLower, poolTokenKey.tickUpper)
            )
        );
        // Check fee invariant between cached fees and uncollected fees.
        assertEq(cached0_c3, uncollected0_c3, "cached0_c3");
        assertEq(cached1_c3, uncollected1_c3, "cached1_c3");
    }

    function test_storeObservations_reentrancy() public {
        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            movingAverageDuration,
            lastObservationTime,
            token0Observations,
            token1Observations
        );

        // Set the UniV3 pair to be locked, which indicates re-entrancy
        _mockPoolUnlocked(uniswapPool, false);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniLens.BunniLens_Reentrant.selector,
            address(uniswapPool)
        );
        vm.expectRevert(err);

        // Store the observations
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.storeObservations();
    }
}
