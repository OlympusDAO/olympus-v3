// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

// Test
import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

// Mocks
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockUniV3Pair} from "test/mocks/MockUniV3Pair.sol";

// Libraries
import {FullMath} from "libraries/FullMath.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

// Uniswap V3
import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

// Bophades Modules
import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";
import "src/modules/SPPLY/OlympusSupply.sol";

// SPPLY Submodules
import {BunniSupply} from "src/modules/SPPLY/submodules/BunniSupply.sol";

// Bunni external contracts
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {BunniToken} from "src/external/bunni/BunniToken.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";

contract BunniSupplyTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockERC20 internal usdc;
    MockERC20 internal wETH;
    MockGohm internal gOhm;
    address internal ohmAddress;
    address internal usdcAddress;

    Kernel internal kernel;

    OlympusSupply internal moduleSupply;

    BunniSupply internal submoduleBunniSupply;

    MockUniV3Pair internal uniswapPool;
    BunniHub internal bunniHub;
    BunniLens internal bunniLens;
    IBunniToken internal poolToken;
    BunniKey internal poolTokenKey;
    address internal bunniLensAddress;
    address internal poolTokenAddress;

    address internal writer;
    address internal policy;

    UserFactory public userFactory;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 0; // 0 OHM

    // OHM-USDC Uni V3 pool, based on: 0x893f503fac2ee1e5b78665db23f9c94017aae97d
    // token0: OHM, token1: USDC
    uint128 internal constant OHM_USDC_POOL_LIQUIDITY = 349484367626548;
    // Current tick: -44579
    uint160 internal constant OHM_USDC_SQRTPRICEX96 = 8529245188595251053303005012; // From OHM-USDC, 1 OHM = 11.5897 USDC
    // NOTE: these numbers are fudged to match the current tick and default observation window from BunniManager
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_0 = -2463052984970;
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_1 = -2463079732370;

    uint128 internal constant OHM_WETH_POOL_LIQUIDITY = 602219599341335870;
    // Current tick: 156194
    uint160 internal constant OHM_WETH_SQRTPRICEX96 = 195181081174522229204497247535278;
    // NOTE: these numbers are fudged to match the current tick and default observation window from BunniManager
    int56 internal constant OHM_WETH_TICK_CUMULATIVE_0 = -2463078395000;
    int56 internal constant OHM_WETH_TICK_CUMULATIVE_1 = -2462984678600;

    // DO NOT change these salt values, as they are used to ensure that the addresses are deterministic, and the SQRTPRICEX96 values depend on the ordering
    bytes32 private constant OHM_SALT =
        0x0000000000000000000000000000000000000000000000000000000000000010;
    bytes32 private constant USDC_SALT =
        0x0000000000000000000000000000000000000000000000000000000000000020;
    bytes32 private constant WETH_SALT =
        0x0000000000000000000000000000000000000000000000000000000000000002;

    uint16 internal constant TWAP_MAX_DEVIATION_BPS = 100; // 1%
    uint32 internal constant TWAP_OBSERVATION_WINDOW = 600; // 10 minutes

    // Events
    event BunniTokenAdded(address token_, address bunniLens_);
    event BunniTokenRemoved(address token_);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            // Use salt to ensure that the addresses are deterministic, otherwise changing variables above will change the addresses and mess with the UniV3 pool
            // Source: https://docs.soliditylang.org/en/v0.8.19/control-structures.html#salted-contract-creations-create2
            ohm = new MockERC20{salt: OHM_SALT}("Olympus", "OHM", 9);
            usdc = new MockERC20{salt: USDC_SALT}("USDC", "USDC", 6);
            wETH = new MockERC20{salt: WETH_SALT}("Wrapped Ether", "wETH", 18);
            gOhm = new MockGohm(GOHM_INDEX);

            ohmAddress = address(ohm);
            usdcAddress = address(usdc);
        }

        // Locations
        {
            userFactory = new UserFactory();
            address[] memory users = userFactory.create(1);
            policy = users[0];
        }

        // Bophades
        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy SPPLY module
            address[2] memory tokens = [address(ohm), address(gOhm)];
            moduleSupply = new OlympusSupply(kernel, tokens, INITIAL_CROSS_CHAIN_SUPPLY);

            // Deploy mock module writer
            writer = moduleSupply.generateGodmodeFixture(type(OlympusSupply).name);
        }

        // Deploy BunniHub/BunniLens
        {
            UniswapV3Factory uniswapFactory = new UniswapV3Factory();
            bunniHub = new BunniHub(
                uniswapFactory,
                policy,
                0 // No protocol fee
            );
            bunniLens = new BunniLens(bunniHub);
            bunniLensAddress = address(bunniLens);
        }

        // Deploy Bunni submodule
        {
            submoduleBunniSupply = new BunniSupply(moduleSupply);
        }

        // Initialize
        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(moduleSupply));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));

            // Install submodules on SPPLY module
            vm.prank(writer);
            moduleSupply.installSubmodule(submoduleBunniSupply);
        }

        // Deploy Uniswap V3 pool and tokens
        {
            (
                MockUniV3Pair uniswapPool_,
                BunniKey memory poolTokenKey_,
                BunniToken poolToken_
            ) = _setUpPool(
                    ohmAddress,
                    usdcAddress,
                    OHM_USDC_POOL_LIQUIDITY,
                    OHM_USDC_SQRTPRICEX96,
                    OHM_USDC_TICK_CUMULATIVE_0,
                    OHM_USDC_TICK_CUMULATIVE_1
                );

            uniswapPool = uniswapPool_;
            poolTokenKey = poolTokenKey_;
            poolToken = poolToken_;
            poolTokenAddress = address(poolToken);
        }
    }

    function _setUpPool(
        address token0_,
        address token1_,
        uint128 liquidity_,
        uint160 sqrtPriceX96_,
        int56 sqrtPriceX96Cumulative0_,
        int56 sqrtPriceX96Cumulative1_
    ) internal returns (MockUniV3Pair, BunniKey memory, BunniToken) {
        MockUniV3Pair pool = new MockUniV3Pair();
        pool.setToken0(token0_);
        pool.setToken1(token1_);
        pool.setLiquidity(liquidity_);
        pool.setSqrtPrice(sqrtPriceX96_);

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = sqrtPriceX96Cumulative0_;
        tickCumulatives[1] = sqrtPriceX96Cumulative1_;
        pool.setTickCumulatives(tickCumulatives);

        BunniKey memory key = BunniKey({
            pool: IUniswapV3Pool(address(pool)),
            tickLower: -887272,
            tickUpper: 887272
        });

        BunniToken token = new BunniToken(bunniHub, key);

        return (pool, key, token);
    }

    function _getOhmReserves(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        if (key_.pool.token0() == ohmAddress) {
            return reserve0;
        } else {
            return reserve1;
        }
    }

    function _getReserves(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (uint256, uint256) {
        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        return (reserve0, reserve1);
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
        OlympusPricev2 modulePrice = new OlympusPricev2(kernel, 18, 8 hours);

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        new BunniSupply(modulePrice);
    }

    // =========  getCollateralizedOhm ========= //

    // [X] getCollateralizedOhm

    function test_getCollateralizedOhm() public {
        // Register the pool with the submodule
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Will always be zero
        assertEq(submoduleBunniSupply.getCollateralizedOhm(), 0);
    }

    // =========  getProtocolOwnedBorrowableOhm ========= //

    // [X] getProtocolOwnedBorrowableOhm

    function test_getProtocolOwnedBorrowableOhm() public {
        // Register the pool with the submodule
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Will always be zero
        assertEq(submoduleBunniSupply.getProtocolOwnedBorrowableOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityOhm ========= //

    // [X] getProtocolOwnedLiquidityOhm
    //  [X] no tokens
    //  [X] single token
    //  [X] multiple tokens
    //  [X] reverts on TWAP deviation
    //  [X] respects observation window
    //  [X] respects deviation

    function test_getProtocolOwnedLiquidityOhm_noTokens() public {
        // Don't add the token

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), 0);
    }

    function test_getProtocolOwnedLiquidityOhm_singleToken() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of OHM in the pool, which should be consistent with the lens value
        uint256 ohmReserves = _getOhmReserves(poolTokenKey, bunniLens);

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), ohmReserves);
    }

    function test_getProtocolOwnedLiquidityOhm_singleToken_observationWindow() public {
        uint32 observationWindow = 60;

        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            observationWindow
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        // 11421651 = 11.42 USD/OHM
        uint256 reservesRatio = usdcReserves_.mulDiv(1e9, ohmReserves_); // USDC decimals: 6

        // Calculate the expected TWAP price
        int56 timeWeightedTick = (OHM_USDC_TICK_CUMULATIVE_1 - OHM_USDC_TICK_CUMULATIVE_0) /
            int32(observationWindow);
        uint256 twapRatio = OracleLibrary.getQuoteAtTick(
            int24(timeWeightedTick),
            uint128(10 ** 9), // token0 (OHM) decimals
            ohmAddress,
            usdcAddress
        ); // USDC decimals: 6

        // Set up revert
        // Will revert as the TWAP deviates from the reserves ratio
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_PriceMismatch.selector,
            address(uniswapPool),
            twapRatio,
            reservesRatio
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityOhm();
    }

    function test_getProtocolOwnedLiquidityOhm_singleToken_deviationBps() public {
        uint16 deviationBps = 1000; // 10%

        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            deviationBps, // Wider deviation
            TWAP_OBSERVATION_WINDOW
        );

        // Mock the pool returning a TWAP that would normally deviate enough to revert
        int56 tickCumulative0_ = -2463052904970;
        int56 tickCumulative1_ = OHM_USDC_TICK_CUMULATIVE_1;
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0_;
        tickCumulatives[1] = tickCumulative1_;
        uniswapPool.setTickCumulatives(tickCumulatives);

        // Determine the amount of OHM in the pool, which should be consistent with the lens value
        uint256 ohmReserves = _getOhmReserves(poolTokenKey, bunniLens);

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), ohmReserves);
    }

    function test_getProtocolOwnedLiquidityOhm_multipleToken() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (, BunniKey memory poolTokenKeyTwo, BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            OHM_WETH_POOL_LIQUIDITY,
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            address(poolTokenTwo),
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of OHM in the pool, which should be consistent with the lens value
        uint256 ohmReserves = _getOhmReserves(poolTokenKey, bunniLens);
        uint256 ohmReservesTwo = _getOhmReserves(poolTokenKeyTwo, bunniLens);

        // Call
        uint256 polo = submoduleBunniSupply.getProtocolOwnedLiquidityOhm();

        assertTrue(polo > 0, "should be non-zero");
        assertEq(polo, ohmReserves + ohmReservesTwo);
    }

    function test_getProtocolOwnedLiquidityOhm_reentrancyReverts() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set the UniV3 pair to be locked, which indicates re-entrancy
        uniswapPool.setUnlocked(false);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniLens.BunniLens_Reentrant.selector,
            address(uniswapPool)
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityOhm();
    }

    function test_getProtocolOwnedLiquidityOhm_twapDeviationReverts() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        // 11421651 = 11.42 USD/OHM
        uint256 reservesRatio = usdcReserves_.mulDiv(1e9, ohmReserves_); // USDC decimals: 6

        // Mock the pool returning a TWAP that deviates enough to revert
        int56 tickCumulative0_ = -2463052904970;
        int56 tickCumulative1_ = OHM_USDC_TICK_CUMULATIVE_1;
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0_;
        tickCumulatives[1] = tickCumulative1_;
        uniswapPool.setTickCumulatives(tickCumulatives);

        // Calculate the expected TWAP price
        // 11436143
        int56 timeWeightedTick = (tickCumulative1_ - tickCumulative0_) /
            int32(TWAP_OBSERVATION_WINDOW);
        uint256 twapRatio = OracleLibrary.getQuoteAtTick(
            int24(timeWeightedTick),
            uint128(10 ** 9), // token0 (OHM) decimals
            ohmAddress,
            usdcAddress
        ); // USDC decimals: 6

        // Set up revert
        // Will revert as the TWAP deviates from the reserves ratio by more than TWAP_MAX_DEVIATION_BPS
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_PriceMismatch.selector,
            address(uniswapPool),
            twapRatio,
            reservesRatio
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityOhm();
    }

    // =========  getProtocolOwnedTreasuryOhm  ========= //

    function test_getProtocolOwnedTreasuryOhm() public {
        // Register the pool with the submodule
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
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

    function test_getProtocolOwnedLiquidityReserves_noTokens() public {
        // Don't add the token

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 0);
    }

    function test_getProtocolOwnedLiquidityReserves_singleToken() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], ohmReserves_);
        assertEq(reserves[0].balances[1], usdcReserves_);
    }

    function test_getProtocolOwnedLiquidityReserves_singleToken_observationWindow() public {
        uint32 observationWindow = 60;

        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            observationWindow
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        // 11421651 = 11.42 USD/OHM
        uint256 reservesRatio = usdcReserves_.mulDiv(1e9, ohmReserves_); // USDC decimals: 6

        // Calculate the expected TWAP price
        int56 timeWeightedTick = (OHM_USDC_TICK_CUMULATIVE_1 - OHM_USDC_TICK_CUMULATIVE_0) /
            int32(observationWindow);
        uint256 twapRatio = OracleLibrary.getQuoteAtTick(
            int24(timeWeightedTick),
            uint128(10 ** 9), // token0 (OHM) decimals
            ohmAddress,
            usdcAddress
        ); // USDC decimals: 6

        // Set up revert
        // Will revert as the TWAP deviates from the reserves ratio
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_PriceMismatch.selector,
            address(uniswapPool),
            twapRatio,
            reservesRatio
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityReserves();
    }

    function test_getProtocolOwnedLiquidityReserves_singleToken_deviationBps() public {
        uint16 deviationBps = 1000; // 10%

        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            deviationBps, // Wider deviation
            TWAP_OBSERVATION_WINDOW
        );

        // Mock the pool returning a TWAP that would normally deviate enough to revert
        // 11436143
        int56 tickCumulative0_ = -2463052904970;
        int56 tickCumulative1_ = OHM_USDC_TICK_CUMULATIVE_1;
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0_;
        tickCumulatives[1] = tickCumulative1_;
        uniswapPool.setTickCumulatives(tickCumulatives);

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], ohmReserves_);
        assertEq(reserves[0].balances[1], usdcReserves_);
    }

    function test_getProtocolOwnedLiquidityReserves_multipleToken() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (, BunniKey memory poolTokenKeyTwo, BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            OHM_WETH_POOL_LIQUIDITY,
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            address(poolTokenTwo),
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        (uint256 ohmReservesTwo_, uint256 wethReservesTwo_) = _getReserves(
            poolTokenKeyTwo,
            bunniLens
        );

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 2);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], ohmReserves_);
        assertEq(reserves[0].balances[1], usdcReserves_);

        assertEq(reserves[1].source, address(poolTokenTwo));
        assertEq(reserves[1].tokens.length, 2);
        assertEq(reserves[1].tokens[0], ohmAddress);
        assertEq(reserves[1].tokens[1], address(wETH));
        assertEq(reserves[1].balances.length, 2);
        assertEq(reserves[1].balances[0], ohmReservesTwo_);
        assertEq(reserves[1].balances[1], wethReservesTwo_);
    }

    function test_getProtocolOwnedLiquidityReserves_reentrancyReverts() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set the UniV3 pair to be locked, which indicates re-entrancy
        uniswapPool.setUnlocked(false);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniLens.BunniLens_Reentrant.selector,
            address(uniswapPool)
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityReserves();
    }

    function test_getProtocolOwnedLiquidityReserves_twapDeviationReverts() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        // 11421651 = 11.42 USD/OHM
        uint256 reservesRatio = usdcReserves_.mulDiv(1e9, ohmReserves_); // USDC decimals: 6

        // Mock the pool returning a TWAP that deviates enough to revert
        int56 tickCumulative0_ = -2416639538393;
        int56 tickCumulative1_ = -2416640880953;
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0_;
        tickCumulatives[1] = tickCumulative1_;
        uniswapPool.setTickCumulatives(tickCumulatives);

        // Calculate the expected TWAP price
        int56 timeWeightedTick = (tickCumulative1_ - tickCumulative0_) /
            int32(TWAP_OBSERVATION_WINDOW);
        uint256 twapRatio = OracleLibrary.getQuoteAtTick(
            int24(timeWeightedTick),
            uint128(10 ** 9), // token0 (OHM) decimals
            ohmAddress,
            usdcAddress
        ); // USDC decimals: 6

        // Set up revert
        // Will revert as the TWAP deviates from the reserves ratio
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_PriceMismatch.selector,
            address(uniswapPool),
            twapRatio,
            reservesRatio
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityReserves();
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

    function test_addBunniToken_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.prank(writer);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_tokenAddressZero_reverts() public {
        _expectRevert_invalidBunniToken(address(0));

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            address(0),
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_lensAddressZero_reverts() public {
        _expectRevert_invalidBunniLens(address(0));

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            address(0),
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_alreadyAdded_reverts() public {
        // Register one token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        _expectRevert_invalidBunniToken(poolTokenAddress);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_invalidTokenReverts() public {
        _expectRevert_invalidBunniToken(ohmAddress);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            ohmAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_invalidLensReverts() public {
        _expectRevert_invalidBunniLens(ohmAddress);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            ohmAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_hubMismatchReverts() public {
        // Deploy a new hub
        UniswapV3Factory uniswapFactory = new UniswapV3Factory();
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

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            address(newBunniLens),
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_twapMaxDeviationOutOfBoundsReverts(
        uint256 twapMaxDeviationBps_
    ) public {
        uint16 twapMaxDeviationBps = uint16(bound(twapMaxDeviationBps_, 10001, type(uint16).max));

        // Expect error
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidTwapMaxDeviationBps.selector,
            address(poolTokenAddress),
            10000,
            twapMaxDeviationBps
        );
        vm.expectRevert(err);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            twapMaxDeviationBps,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_twapObservationWindowBelowMinimum(
        uint256 twapObservationWindow_
    ) public {
        uint32 twapObservationWindow = uint32(bound(twapObservationWindow_, 0, 18));

        // Expect error
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidTwapObservationWindow.selector,
            address(poolTokenAddress),
            19,
            twapObservationWindow
        );
        vm.expectRevert(err);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            twapObservationWindow
        );
    }

    function test_addBunniToken() public {
        // Expect an event
        vm.expectEmit(true, true, false, true);
        emit BunniTokenAdded(poolTokenAddress, bunniLensAddress);

        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Check that the token was added
        (
            BunniToken bunniToken_,
            BunniLens bunniLens_,
            uint16 twapMaxDeviationBps_,
            uint32 twapObservationWindow_
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenAddress);
        assertEq(address(bunniLens_), bunniLensAddress);
        assertEq(twapMaxDeviationBps_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindow_, TWAP_OBSERVATION_WINDOW);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
    }

    function test_addBunniToken_fuzz(
        uint256 twapMaxDeviationBps_,
        uint256 twapObservationWindow_
    ) public {
        uint16 twapMaxDeviationBps = uint16(bound(twapMaxDeviationBps_, 0, 10000));
        uint32 twapObservationWindow = uint32(bound(twapObservationWindow_, 19, type(uint32).max));

        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            twapMaxDeviationBps,
            twapObservationWindow
        );

        // Check that the token was added
        (
            BunniToken _bunniToken,
            BunniLens _bunniLens,
            uint16 _twapMaxDeviationBps,
            uint32 _twapObservationWindow
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(_bunniToken), poolTokenAddress);
        assertEq(address(_bunniLens), bunniLensAddress);
        assertEq(_twapMaxDeviationBps, twapMaxDeviationBps);
        assertEq(_twapObservationWindow, twapObservationWindow);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
    }

    function test_addBunniToken_multipleTokens_singleLens() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (, , BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            OHM_WETH_POOL_LIQUIDITY,
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Expect an event
        vm.expectEmit(true, true, false, true);
        emit BunniTokenAdded(poolTokenTwoAddress, bunniLensAddress);

        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Check that the token was added
        (
            BunniToken bunniToken_,
            BunniLens bunniLens_,
            uint16 twapMaxDeviationBps_,
            uint32 twapObservationWindow_
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenAddress);
        assertEq(address(bunniLens_), bunniLensAddress);
        assertEq(twapMaxDeviationBps_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindow_, TWAP_OBSERVATION_WINDOW);

        (
            BunniToken bunniTokenTwo_,
            BunniLens bunniLensTwo_,
            uint16 twapMaxDeviationBpsTwo_,
            uint32 twapObservationWindowTwo_
        ) = submoduleBunniSupply.bunniTokens(1);
        assertEq(address(bunniTokenTwo_), poolTokenTwoAddress);
        assertEq(address(bunniLensTwo_), bunniLensAddress);
        assertEq(twapMaxDeviationBpsTwo_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindowTwo_, TWAP_OBSERVATION_WINDOW);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 2);
    }

    function test_addBunniToken_multipleTokens_multipleLenses() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (, , BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            OHM_WETH_POOL_LIQUIDITY,
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
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensTwoAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Check that the token was added
        (
            BunniToken bunniToken_,
            BunniLens bunniLens_,
            uint16 twapMaxDeviationBps_,
            uint32 twapObservationWindow_
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenAddress);
        assertEq(address(bunniLens_), bunniLensAddress);
        assertEq(twapMaxDeviationBps_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindow_, TWAP_OBSERVATION_WINDOW);

        (
            BunniToken bunniTokenTwo_,
            BunniLens bunniLensTwo_,
            uint16 twapMaxDeviationBpsTwo_,
            uint32 twapObservationWindowTwo_
        ) = submoduleBunniSupply.bunniTokens(1);
        assertEq(address(bunniTokenTwo_), poolTokenTwoAddress);
        assertEq(address(bunniLensTwo_), bunniLensTwoAddress);
        assertEq(twapMaxDeviationBpsTwo_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindowTwo_, TWAP_OBSERVATION_WINDOW);

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

    function test_removeBunniToken_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.prank(writer);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken_addressZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            address(0)
        );
        vm.expectRevert(err);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.removeBunniToken(address(0));
    }

    function test_removeBunniToken_notAdded_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            poolTokenAddress
        );
        vm.expectRevert(err);

        vm.prank(address(moduleSupply));
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove token
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        assertEq(submoduleBunniSupply.bunniTokenCount(), 0);
        assertEq(submoduleBunniSupply.getCollateralizedOhm(), 0);
    }

    function test_removeBunniToken_multipleTokens_singleLens() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (, , BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            OHM_WETH_POOL_LIQUIDITY,
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove one of the tokens
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        (
            BunniToken bunniToken_,
            BunniLens bunniLens_,
            uint16 twapMaxDeviationBps_,
            uint32 twapObservationWindow_
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenTwoAddress);
        assertEq(address(bunniLens_), bunniLensAddress);
        assertEq(twapMaxDeviationBps_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindow_, TWAP_OBSERVATION_WINDOW);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
    }

    function test_removeBunniToken_multipleTokens_multipleLenses() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (, , BunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wETH),
            OHM_WETH_POOL_LIQUIDITY,
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Set up a new Lens
        BunniLens bunniLensTwo = new BunniLens(bunniHub);
        address bunniLensTwoAddress = address(bunniLensTwo);

        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensTwoAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove one of the tokens
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        (
            BunniToken bunniToken_,
            BunniLens bunniLens_,
            uint16 twapMaxDeviationBps_,
            uint32 twapObservationWindow_
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenTwoAddress);
        assertEq(address(bunniLens_), bunniLensTwoAddress);
        assertEq(twapMaxDeviationBps_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindow_, TWAP_OBSERVATION_WINDOW);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
    }

    // =========  hasBunniToken ========= //

    // [X] hasBunniToken
    //  [X] false if address(0)
    //  [X] false if not added
    //  [X] true if added

    function test_hasBunniToken_addressZero() public {
        // Add bunni token to BunniSupply
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
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
        vm.prank(address(moduleSupply));
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Call
        bool hasToken = submoduleBunniSupply.hasBunniToken(poolTokenAddress);

        // Check
        assertTrue(hasToken);
    }
}
