// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Uniswap V3
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

// Libraries
import {UniswapV3OracleHelper as OracleHelper} from "libraries/UniswapV3/Oracle.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "libraries/FullMath.sol";

// Test
import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

// Mocks
import {MockBalancerPool} from "test/mocks/MockBalancerPool.sol";
import {MockUniswapV2Pool} from "test/mocks/MockUniswapV2Pool.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockUniV3Pair} from "test/mocks/MockUniV3Pair.sol";

// Bophades
import "src/Kernel.sol";
import {UniswapV3Price} from "modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";

contract UniswapV3PriceTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for UniswapV3Price;

    MockPrice internal mockPrice;
    MockUniV3Pair internal mockUniPair;

    UniswapV3Price internal uniSubmodule;

    address internal DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address internal UNI = 0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801;
    address internal USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint8 internal PRICE_DECIMALS = 18;

    uint256 internal USDC_PRICE = 10 ** PRICE_DECIMALS;

    uint32 internal OBSERVATION_SECONDS = 60;
    uint16 internal DEVIATION_BASE = 10_000;

    // Live value taken from https://etherscan.io/address/0x4e0924d3a751be199c426d52fb1f2337fa96f736#readContract
    uint160 internal uniSqrtPrice = 79406181270273404968401;
    // 60 seconds
    int56[] internal uniTickCumulatives = [-15895885013372, -15895901590172];

    uint8 internal MIN_DECIMALS = 6;
    uint8 internal MAX_DECIMALS = 30;
    // Mirror of TWAP_MINIMUM_OBSERVATION_SECONDS
    uint32 internal MIN_OBSERVATION_SECONDS = 19;

    // Uniswap V3 ticks
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Set up the submodule
        {
            Kernel kernel = new Kernel();
            mockPrice = new MockPrice(kernel, uint8(18), uint32(8 hours));
            mockPrice.setTimestamp(uint48(block.timestamp));
            mockPrice.setPriceDecimals(PRICE_DECIMALS);
            uniSubmodule = new UniswapV3Price(mockPrice);
        }

        // Set up the mock UniV3 pool
        {
            mockUniPair = new MockUniV3Pair();
            mockUniPair.setToken0(LUSD);
            mockUniPair.setToken1(USDC);
            mockUniPair.setSqrtPrice(uniSqrtPrice);
            mockUniPair.setTickCumulatives(uniTickCumulatives);
        }

        // Mock prices from PRICE
        {
            mockAssetPrice(USDC, USDC_PRICE);
        }

        // Mock ERC20 decimals
        {
            mockERC20Decimals(DAI, 18);
            mockERC20Decimals(LUSD, 18);
            mockERC20Decimals(UNI, 18);
            mockERC20Decimals(USDC, 6);
            mockERC20Decimals(WETH, 18);
        }
    }

    // =========  HELPER METHODS ========= //

    function encodeParams(
        IUniswapV3Pool pool,
        uint32 observationWindowSeconds,
        uint16 maxDeviationBps
    ) internal pure returns (bytes memory params) {
        return abi.encode(pool, observationWindowSeconds, maxDeviationBps);
    }

    function mockAssetPrice(address asset_, uint256 price_) internal {
        mockPrice.setPrice(asset_, price_);
    }

    function mockERC20Decimals(address asset_, uint8 decimals_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }

    function expectRevert_PriceZero(address asset_) internal {
        bytes memory err = abi.encodeWithSelector(PRICEv2.PRICE_PriceZero.selector, asset_);
        vm.expectRevert(err);
    }

    function expectRevert_address(bytes4 selector_, address asset_) internal {
        bytes memory err = abi.encodeWithSelector(selector_, asset_);
        vm.expectRevert(err);
    }

    function expectRevert_uint8(bytes4 selector_, uint8 number_) internal {
        bytes memory err = abi.encodeWithSelector(selector_, number_);
        vm.expectRevert(err);
    }

    // ========= TESTS ========= //

    // [X] getTokenTWAP
    //  [X] Reverts if params.pool is is not a valid Uniswap V3 pool
    //  [X] Reverts if params.observationWindowSeconds is less than TWAP_MINIMUM_OBSERVATION_SECONDS
    //  [X] Reverts if lookupToken is not a one of the pool tokens
    //  [X] Reverts if any of the pool tokens are not defined as assets in PRICE
    //  [X] Reverts if the calculated time-weighted tick is outside the bounds of int24
    //  [X] Correctly calculates the TWAP
    //  [X] Correctly handles different output decimals

    function test_getTokenTWAP_success_token0() public {
        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uint256 price = uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);

        // Calculate the return value
        // From: https://tienshaoku.medium.com/a-guide-on-uniswap-v3-twap-oracle-2aa74a4a97c5
        // tick = (uniTickCumulatives[1] - uniTickCumulatives[0]) / 60;
        // = (-15895901590172 - -15895885013372) / 60
        // quote price = 1.0001 ^ tick
        // $1.004412 USDC
        // For this to match, the decimal conversion will have been handled too
        assertEq(price, 1.004412 * 1e18);
    }

    function test_getTokenTWAP_success_token1() public {
        // Mock LUSD as $1 exactly
        mockAssetPrice(LUSD, 1e18);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uint256 price = uniSubmodule.getTokenTWAP(USDC, PRICE_DECIMALS, params);

        // Calculate the return value
        // From: https://tienshaoku.medium.com/a-guide-on-uniswap-v3-twap-oracle-2aa74a4a97c5
        // tick = (uniTickCumulatives[1] - uniTickCumulatives[0]) / 60;
        // = (-15895901590172 - -15895885013372) / 60
        // quote price = 1.0001 ^ tick
        // 1 / $1.004412 USDC = 0.995607252620550200 = 995607252620550200 * 10^-18
        // For this to match, the decimal conversion will have been handled too
        assertEq(price, 995607252620550200);
    }

    function testRevert_getTokenTWAPOnParamsPoolUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_ParamsPoolInvalid.selector,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(IUniswapV3Pool(address(0)), OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenTWAPOnBalancerPoolType() public {
        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        expectRevert_address(
            UniswapV3Price.UniswapV3_PoolTypeInvalid.selector,
            address(mockNonWeightedPool)
        );

        bytes memory params = abi.encode(mockNonWeightedPool, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenTWAPOnUniswapV2PoolType() public {
        // Set up a Uniswap V2 pool
        MockUniswapV2Pool mockUniPool = new MockUniswapV2Pool();
        mockUniPool.setTotalSupply(10e18);
        mockUniPool.setToken0(USDC);
        mockUniPool.setToken1(WETH);
        mockUniPool.setReserves(1e9, 1e18);

        expectRevert_address(
            UniswapV3Price.UniswapV3_PoolTypeInvalid.selector,
            address(mockUniPool)
        );

        bytes memory params = abi.encode(mockUniPool, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenTWAP_usesPrice() public {
        // Mock USDC as $1.01
        mockAssetPrice(USDC, 1.01 * 1e18);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uint256 price = uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);

        // $1.004412 USDC = $1.004412 * 1.01 = 1.01445612
        assertEq(price, 1.004412 * 1.01 * 1e18);
    }

    function testFuzz_getTokenTWAP_priceDecimals(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uint256 price = uniSubmodule.getTokenTWAP(LUSD, priceDecimals, params);

        // Calculate the return value
        // From: https://tienshaoku.medium.com/a-guide-on-uniswap-v3-twap-oracle-2aa74a4a97c5
        // tick = (uniTickCumulatives[1] - uniTickCumulatives[0]) / 60;
        // = (-15895901590172 - -15895885013372) / 60
        // quote price = 1.0001 ^ tick
        // $1.004412 USDC
        // For this to match, the decimal conversion will have been handled too
        assertEq(price, uint256(1004412).mulDiv(10 ** priceDecimals, 10 ** 6));
    }

    function testRevert_getTokenTWAPOnPriceDecimalsMaximum() public {
        uint8 priceDecimals = MAX_DECIMALS + 1;
        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** MAX_DECIMALS, 10 ** PRICE_DECIMALS));

        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_OutputDecimalsOutOfBounds.selector,
            priceDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(LUSD, priceDecimals, params);
    }

    // The other tests use LUSD and USDC, which have different token decimals. This tests tokens with the same decimals.
    function test_getTokenTWAP_tokenDecimalsSame() public {
        // Mock the UNI-wETH pool
        mockUniPair.setToken0(UNI);
        mockUniPair.setToken1(WETH);
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = -3080970025126;
        tickCumulatives[1] = -3080973330766;
        mockUniPair.setTickCumulatives(tickCumulatives);

        // Mock wETH as $1500 exactly
        mockAssetPrice(WETH, 1500 * 1e18);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uint256 price = uniSubmodule.getTokenTWAP(UNI, PRICE_DECIMALS, params);

        // Calculate the return value
        // From: https://tienshaoku.medium.com/a-guide-on-uniswap-v3-twap-oracle-2aa74a4a97c5
        // tick = (-3080973330766 - -3080970025126) / 60
        // quote price = 1.0001 ^ tick = 0.0040496511 ETH
        // quote price = 0.0040496511 * 1500 =~ 6.07447665
        assertEq(price, 6074476658258328000);
    }

    /**
     * Fuzz testing the token decimals proves to be difficult, due to the complexities of calculating
     * the ticks and sqrtPriceX96.
     */

    function testRevert_getTokenTWAPOnLookupTokenDecimalsMaximum() public {
        // Mock a high number of decimals for the lookup token, which will result in an overflow
        mockERC20Decimals(LUSD, 120);

        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_AssetDecimalsOutOfBounds.selector,
            LUSD,
            120,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenTWAPOnQuoteTokenDecimalsMaximum() public {
        // Mock a high number of decimals for the quote token, which will result in an overflow
        mockERC20Decimals(USDC, 120);

        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_AssetDecimalsOutOfBounds.selector,
            USDC,
            120,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenTWAPOnObservationWindowInvalidFuzz(
        uint32 observationWindow_
    ) public {
        uint32 observationWindow = uint32(
            bound(observationWindow_, 0, MIN_OBSERVATION_SECONDS - 1)
        );

        bytes memory err = abi.encodeWithSelector(
            OracleHelper.UniswapV3OracleHelper_ObservationTooShort.selector,
            address(mockUniPair),
            observationWindow,
            MIN_OBSERVATION_SECONDS
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, observationWindow, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenTWAPOnObservationWindowGreaterThanOldest() public {
        uint32 observationWindow = 1800;

        // Set up the pool to revert as the observation window is too long
        mockUniPair.setObserveReverts(true);

        bytes memory err = abi.encodeWithSelector(
            OracleHelper.UniswapV3OracleHelper_InvalidObservation.selector,
            address(mockUniPair),
            observationWindow
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, observationWindow, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function testFuzz_getTokenTWAP_observationWindowValid(uint32 observationWindow_) public view {
        uint32 observationWindow = uint32(bound(observationWindow_, MIN_OBSERVATION_SECONDS, 1800));

        bytes memory params = encodeParams(mockUniPair, observationWindow, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);

        // Can't test price
    }

    function testRevert_getTokenTWAPOnTickMaximumFuzz(int56 tick0_, int56 tick1_) public {
        /**
         * Generate an invalid cumulative tick.
         *
         * Invalid if:
         * (tick1 - tick0) / window > MAX_TICK
         * tick1 - tick0 > MAX_TICK * window = 887272 * 60 = 53,236,320
         *
         * As vm.assume has a limited number of possible rejections, we narrow
         * the field by implementing the following:
         * - tick1 very positive
         * - tick0 very negative
         * - within bounds of int32 (as they are two int56 added together)
         */
        int256 maxValue = type(int32).max;
        int256 minValue = type(int32).min;
        int256 obsSec = int256(uint256(OBSERVATION_SECONDS));
        int56 tick0 = int56(bound(tick0_, minValue, 0));
        int56 tick1 = int56(bound(tick1_, (obsSec + 1) * MAX_TICK, maxValue));
        vm.assume(int256(tick1) - int256(tick0) > MAX_TICK * obsSec);

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tick0;
        tickCumulatives[1] = tick1;
        mockUniPair.setTickCumulatives(tickCumulatives);

        bytes memory err = abi.encodeWithSelector(
            OracleHelper.UniswapV3OracleHelper_TickOutOfBounds.selector,
            address(mockUniPair),
            (tick1 - tick0) / int56(int32(OBSERVATION_SECONDS)),
            MIN_TICK,
            MAX_TICK
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenTWAPOnTickMinimumFuzz(int56 tick0_, int56 tick1_) public {
        /**
         * Generate an invalid cumulative tick.
         *
         * Invalid if:
         * (tick1 - tick0) / window < MIN_TICK
         * tick1 - tick0 < MIN_TICK * window = -887272 * 60 = -53,236,320
         *
         * As vm.assume has a limited number of possible rejections, we narrow
         * the field by implementing the following:
         * - tick1 very negative
         * - tick0 very positive
         * - within bounds of int32 (as they are two int56 added together)
         */
        int256 maxValue = type(int32).max;
        int256 minValue = type(int32).min;
        int256 obsSec = int256(uint256(OBSERVATION_SECONDS));
        int56 tick0 = int56(bound(tick0_, (obsSec + 1) * MAX_TICK, maxValue));
        int56 tick1 = int56(bound(tick1_, minValue, 0));
        vm.assume(int256(tick1) - int256(tick0) < MIN_TICK * obsSec);

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tick0;
        tickCumulatives[1] = tick1;
        mockUniPair.setTickCumulatives(tickCumulatives);

        bytes memory err = abi.encodeWithSelector(
            OracleHelper.UniswapV3OracleHelper_TickOutOfBounds.selector,
            address(mockUniPair),
            (tick1 - tick0) / int56(int32(OBSERVATION_SECONDS)),
            MIN_TICK,
            MAX_TICK
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function testFuzz_getTokenTWAP_tickValid(int56 tick0_, int56 tick1_) public {
        /**
         * Generate an valid cumulative tick.
         *
         * (tick1 - tick0) / window <= MAX_TICK = 887272
         * tick1 - tick0 <= MAX_TICK * window = 887272 * 60 = 53,236,320
         *
         * As vm.assume has a limited number of possible rejections, we narrow
         * the field by implementing the following:
         * - tick1 positive and large, bounded by MAX_TICK
         * - tick0 positive and small, bounded by MAX_TICK
         * - within bounds of int32 (as they are two int56 added together)
         */
        int256 obsSec = int256(uint256(OBSERVATION_SECONDS));
        int56 tick0 = int56(bound(tick0_, 0, obsSec * MAX_TICK));
        int56 tick1 = int56(bound(tick1_, 0, obsSec * MAX_TICK));
        vm.assume(int256(tick1) - int256(tick0) <= MAX_TICK * obsSec);

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tick0;
        tickCumulatives[1] = tick1;
        mockUniPair.setTickCumulatives(tickCumulatives);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);

        // Can't test the price
    }

    function testRevert_getTokenTWAPOnZeroPrice() public {
        mockAssetPrice(USDC, 0);

        expectRevert_PriceZero(USDC);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenTWAPOnInvalidToken() public {
        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_LookupTokenNotFound.selector,
            address(mockUniPair),
            DAI
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(DAI, PRICE_DECIMALS, params); // DAI is not in the pair
    }

    function testRevert_getTokenTWAPOnInvalidToken0() public {
        mockUniPair.setToken0(address(0));

        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_PoolTokensInvalid.selector,
            address(mockUniPair),
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenTWAPOnInvalidToken1() public {
        mockUniPair.setToken1(address(0));

        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_PoolTokensInvalid.selector,
            address(mockUniPair),
            1,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uniSubmodule.getTokenTWAP(USDC, PRICE_DECIMALS, params);
    }

    // [X] getTokenPrice
    //  [X] Reverts if params.pool is is not a valid Uniswap V3 pool
    //  [X] Reverts if lookupToken is not a one of the pool tokens
    //  [X] Reverts if any of the pool tokens are not defined as assets in PRICE
    //  [X] Reverts if the pool is locked
    //  [X] Reverts if the current price deviates from the TWAP by more than maxDeviationBps
    //  [X] Correctly calculates the current pool price
    //  [X] Correctly handles different output decimals

    function testRevert_getTokenPrice_OnParamsPoolUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_ParamsPoolInvalid.selector,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(IUniswapV3Pool(address(0)), OBSERVATION_SECONDS, 100);
        uniSubmodule.getTokenPrice(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenPrice_OnBalancerPoolType() public {
        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        expectRevert_address(
            UniswapV3Price.UniswapV3_PoolTypeInvalid.selector,
            address(mockNonWeightedPool)
        );

        bytes memory params = abi.encode(mockNonWeightedPool, OBSERVATION_SECONDS, 100);
        uniSubmodule.getTokenPrice(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenPrice_OnUniswapV2PoolType() public {
        // Set up a Uniswap V2 pool
        MockUniswapV2Pool mockUniPool = new MockUniswapV2Pool();
        mockUniPool.setTotalSupply(10e18);
        mockUniPool.setToken0(USDC);
        mockUniPool.setToken1(WETH);
        mockUniPool.setReserves(1e9, 1e18);

        expectRevert_address(
            UniswapV3Price.UniswapV3_PoolTypeInvalid.selector,
            address(mockUniPool)
        );

        bytes memory params = abi.encode(mockUniPool, OBSERVATION_SECONDS, 100);
        uniSubmodule.getTokenPrice(WETH, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenPrice_OnPriceDecimalsMaximum() public {
        uint8 priceDecimals = MAX_DECIMALS + 1;
        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** MAX_DECIMALS, 10 ** PRICE_DECIMALS));

        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_OutputDecimalsOutOfBounds.selector,
            priceDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 100);
        uniSubmodule.getTokenPrice(LUSD, priceDecimals, params);
    }

    function testRevert_getTokenPrice_OnLookupTokenDecimalsMaximum() public {
        // Mock a high number of decimals for the lookup token, which will result in an overflow
        mockERC20Decimals(LUSD, 120);

        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_AssetDecimalsOutOfBounds.selector,
            LUSD,
            120,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 100);
        uniSubmodule.getTokenPrice(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenPrice_OnQuoteTokenDecimalsMaximum() public {
        // Mock a high number of decimals for the quote token, which will result in an overflow
        mockERC20Decimals(USDC, 120);

        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_AssetDecimalsOutOfBounds.selector,
            USDC,
            120,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 100);
        uniSubmodule.getTokenPrice(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenPrice_OnInvalidToken() public {
        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_LookupTokenNotFound.selector,
            address(mockUniPair),
            DAI
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 100);
        uniSubmodule.getTokenPrice(DAI, PRICE_DECIMALS, params); // DAI is not in the pair
    }

    function testRevert_getTokenPrice_OnInvalidToken0() public {
        mockUniPair.setToken0(address(0));

        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_PoolTokensInvalid.selector,
            address(mockUniPair),
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 100);
        uniSubmodule.getTokenPrice(LUSD, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenPrice_OnInvalidToken1() public {
        mockUniPair.setToken1(address(0));

        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_PoolTokensInvalid.selector,
            address(mockUniPair),
            1,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 100);
        uniSubmodule.getTokenPrice(USDC, PRICE_DECIMALS, params);
    }

    function testRevert_getTokenPrice_reentrancy() public {
        // Set the UniV3 pair to be locked, which indicates re-entrancy
        mockUniPair.setUnlocked(false);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_PoolReentrancy.selector,
            address(mockUniPair)
        );
        vm.expectRevert(err);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 100);
        uniSubmodule.getTokenPrice(USDC, PRICE_DECIMALS, params);
    }

    function test_getTokenPrice_usesPrice() public {
        // Mock USDC as $1.01
        mockAssetPrice(USDC, 1.01 * 1e18);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 100);
        uint256 price = uniSubmodule.getTokenPrice(LUSD, PRICE_DECIMALS, params);

        // $1.004412 USDC = $1.004412 * 1.01 = 1.01445612
        assertEq(price, 1.004412 * 1.01 * 1e18);
    }

    function testFuzz_getTokenPrice_priceDecimals(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 100);
        uint256 price = uniSubmodule.getTokenPrice(LUSD, priceDecimals, params);

        // Calculate the return value
        // tick = -276280
        // quote price = 1.0001 ^ tick
        // $1.004412 USDC
        // For this to match, the decimal conversion will have been handled too
        assertEq(price, uint256(1004412).mulDiv(10 ** priceDecimals, 10 ** 6));
    }

    function test_getTokenPrice_success_token0() public {
        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uint256 price = uniSubmodule.getTokenPrice(LUSD, PRICE_DECIMALS, params);

        // Calculate the return value
        // tick = -276280
        // quote price = 1.0001 ^ tick
        // $1.004412 USDC
        // For this to match, the decimal conversion will have been handled too
        assertEq(price, 1.004412 * 1e18);
    }

    function test_getTokenPrice_success_token1() public {
        // Mock LUSD as $1 exactly
        mockAssetPrice(LUSD, 1e18);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uint256 price = uniSubmodule.getTokenPrice(USDC, PRICE_DECIMALS, params);

        // Calculate the return value
        // tick = -276280
        // quote price = 1.0001 ^ tick
        // 1 / $1.004412 USDC = 0.995607252620550200 = 995607252620550200 * 10^-18
        // For this to match, the decimal conversion will have been handled too
        assertEq(price, 995607252620550200);
    }

    // The other tests use LUSD and USDC, which have different token decimals. This tests tokens with the same decimals.
    function test_getTokenPrice_tokenDecimalsSame() public {
        // Mock the UNI-wETH pool
        mockUniPair.setToken0(UNI);
        mockUniPair.setToken1(WETH);
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = -3080970025126;
        tickCumulatives[1] = -3080973330766;
        mockUniPair.setTickCumulatives(tickCumulatives);
        mockUniPair.setTick(int24(-55094));

        // Mock wETH as $1500 exactly
        mockAssetPrice(WETH, 1500 * 1e18);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 0);
        uint256 price = uniSubmodule.getTokenPrice(UNI, PRICE_DECIMALS, params);

        // Calculate the return value
        // tick = -55094
        // quote price = 1.0001 ^ tick = 0.0040496511 ETH
        // quote price = 0.0040496511 * 1500 =~ 6.07447665
        assertEq(price, 6074476658258328000);
    }

    function testRevert_getTokenPrice_deviationOutOfBounds() public {
        // Mock the UNI-wETH pool
        mockUniPair.setToken0(UNI);
        mockUniPair.setToken1(WETH);
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = -3080970025126;
        tickCumulatives[1] = -3080973330766;
        mockUniPair.setTickCumulatives(tickCumulatives);
        mockUniPair.setTick(int24(-55094));

        // Mock wETH as $1500 exactly
        mockAssetPrice(WETH, 1500 * 1e18);

        // Allow 1% deviation vs TWAP
        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS, 100);

        // Calculate the return value
        // tick = -55094
        // quote price = 1.0001 ^ tick = 0.0040496511 ETH
        // quote price = 0.0040496511 * 1500 =~ 6.07447665
        uint256 initPrice = uniSubmodule.getTokenPrice(UNI, PRICE_DECIMALS, params);
        assertEq(initPrice, 6074476658258328000);

        // Update pool price within deviation bounds
        mockUniPair.setTick(int24(-55195));

        // Calculate the return value
        // tick = -55195
        // quote price = 1.0001 ^ tick = 0.0040089575 ETH
        // quote price = 0.0040089575 * 1500 =~ 6.01343625
        // deviation = (6.01343625 / 6.07447665) - 1 = 1.00%
        uint256 newPriceWithinBounds = uniSubmodule.getTokenPrice(UNI, PRICE_DECIMALS, params);
        assertEq(newPriceWithinBounds, 6013436268812580000);

        // // Update pool price outside deviation bounds
        mockUniPair.setTickCumulatives(tickCumulatives);
        mockUniPair.setTick(int24(-55196));

        // Calculate the return value
        // tick = -55196
        // quote price = 1.0001 ^ tick = 0.0040085566 ETH
        // quote price = 0.0040085566 * 1500 =~ 6.013436
        // deviation = (6.01283498 / 6.07447665) - 1 = 1.01%
        bytes memory err = abi.encodeWithSelector(
            UniswapV3Price.UniswapV3_PriceMismatch.selector,
            address(mockUniPair),
            4049651105505552, // TWAP price in ETH terms
            4008556656876033 // Slot0 price in ETH terms
        );
        vm.expectRevert(err);
        uniSubmodule.getTokenPrice(UNI, PRICE_DECIMALS, params);
    }
}
