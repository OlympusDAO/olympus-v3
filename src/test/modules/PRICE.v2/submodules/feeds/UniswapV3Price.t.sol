// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {FullMath} from "libraries/FullMath.sol";
import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockUniV3Pair} from "test/mocks/MockUniV3Pair.sol";

import {UniswapV3Price} from "modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {IUniswapV3Pool} from "src/interfaces/UniswapV3/IUniswapV3Pool.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";
import {TickMath} from "src/libraries/UniswapV3/TickMath.sol";
import {MockBalancerPool} from "test/mocks/MockBalancerPool.sol";

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

    // Live value taken from https://etherscan.io/address/0x4e0924d3a751be199c426d52fb1f2337fa96f736#readContract
    uint160 internal uniSqrtPrice = 79406181270273404968401;
    // 60 seconds
    int56[] internal uniTickCumulatives = [-15895885013372, -15895901590172];

    uint8 internal MIN_DECIMALS = 6;
    uint8 internal MAX_DECIMALS = 50;
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
        uint32 observationWindowSeconds
    ) internal pure returns (bytes memory params) {
        return abi.encode(pool, observationWindowSeconds);
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

    function test_tokenTWAP_success_token0() public {
        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
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

    function test_tokenTWAP_success_token1() public {
        // Mock LUSD as $1 exactly
        mockAssetPrice(LUSD, 1e18);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
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

    function test_tokenTWAP_revertsOnParamsPoolUndefined() public {
        expectRevert_address(UniswapV3Price.UniswapV3_PoolTypeInvalid.selector, address(0));

        bytes memory params = encodeParams(IUniswapV3Pool(address(0)), OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function test_tokenTWAP_revertsOnIncorrectPoolType() public {
        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        expectRevert_address(UniswapV3Price.UniswapV3_PoolTypeInvalid.selector, address(mockNonWeightedPool));

        bytes memory params = abi.encode(mockNonWeightedPool, OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function test_tokenTWAP_usesPrice() public {
        // Mock USDC as $1.01
        mockAssetPrice(USDC, 1.01 * 1e18);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
        uint256 price = uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);

        // $1.004412 USDC = $1.004412 * 1.01 = 1.01445612
        assertEq(price, 1.004412 * 1.01 * 1e18);
    }

    function test_tokenTWAP_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
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

    function test_tokenTWAP_revertsOnPriceDecimalsMaximum() public {
        uint8 priceDecimals = MAX_DECIMALS + 1;
        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** MAX_DECIMALS, 10 ** PRICE_DECIMALS));

        expectRevert_uint8(
            UniswapV3Price.UniswapV3_OutputDecimalsOutOfBounds.selector,
            priceDecimals
        );

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(LUSD, priceDecimals, params);
    }

    // The other tests use LUSD and USDC, which have different token decimals. This tests tokens with the same decimals.
    function test_tokenTWAP_tokenDecimalsSame() public {
        // Mock the UNI-wETH pool
        mockUniPair.setToken0(UNI);
        mockUniPair.setToken1(WETH);
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = -3080970025126;
        tickCumulatives[1] = -3080973330766;
        mockUniPair.setTickCumulatives(tickCumulatives);

        // Mock wETH as $1500 exactly
        mockAssetPrice(WETH, 1500 * 1e18);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
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

    function test_tokenTWAP_revertsOnLookupTokenDecimalsMaximum() public {
        // Mock a high number of decimals for the lookup token, which will result in an overflow
        mockERC20Decimals(LUSD, 120);

        expectRevert_address(UniswapV3Price.UniswapV3_AssetDecimalsOutOfBounds.selector, LUSD);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function test_tokenTWAP_revertsOnQuoteTokenDecimalsMaximum() public {
        // Mock a high number of decimals for the quote token, which will result in an overflow
        mockERC20Decimals(USDC, 120);

        expectRevert_address(UniswapV3Price.UniswapV3_AssetDecimalsOutOfBounds.selector, USDC);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function test_tokenTWAP_revertsOnObservationWindowInvalidFuzz(
        uint32 observationWindow_
    ) public {
        uint32 observationWindow = uint32(
            bound(observationWindow_, 0, MIN_OBSERVATION_SECONDS - 1)
        );

        expectRevert_address(
            UniswapV3Price.UniswapV3_TWAPObservationWindowTooShort.selector,
            address(mockUniPair)
        );

        bytes memory params = encodeParams(mockUniPair, observationWindow);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function test_tokenTWAP_observationWindowValidFuzz(uint32 observationWindow_) public {
        uint32 observationWindow = uint32(bound(observationWindow_, MIN_OBSERVATION_SECONDS, 1800));

        bytes memory params = encodeParams(mockUniPair, observationWindow);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);

        // Can't test price
    }

    function test_tokenTWAP_revertsOnTickMaximumFuzz(int56 tick0_, int56 tick1_) public {
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

        expectRevert_address(
            UniswapV3Price.UniswapV3_TickOutOfBounds.selector,
            address(mockUniPair)
        );

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function test_tokenTWAP_revertsOnTickMinimumFuzz(int56 tick0_, int56 tick1_) public {
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

        expectRevert_address(
            UniswapV3Price.UniswapV3_TickOutOfBounds.selector,
            address(mockUniPair)
        );

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function test_tokenTWAP_tickValidFuzz(int56 tick0_, int56 tick1_) public {
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

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);

        // Can't test the price
    }

    function test_tokenTWAP_revertsOnZeroPrice() public {
        mockAssetPrice(USDC, 0);

        expectRevert_PriceZero(USDC);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function test_tokenTWAP_revertsOnInvalidToken() public {
        expectRevert_address(UniswapV3Price.UniswapV3_LookupTokenNotFound.selector, DAI);

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(DAI, PRICE_DECIMALS, params); // DAI is not in the pair
    }

    function test_tokenTWAP_revertsOnInvalidToken0() public {
        mockUniPair.setToken0(address(0));

        expectRevert_address(
            UniswapV3Price.UniswapV3_PoolTokensInvalid.selector,
            address(mockUniPair)
        );

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(LUSD, PRICE_DECIMALS, params);
    }

    function test_tokenTWAP_revertsOnInvalidToken1() public {
        mockUniPair.setToken1(address(0));

        expectRevert_address(
            UniswapV3Price.UniswapV3_PoolTokensInvalid.selector,
            address(mockUniPair)
        );

        bytes memory params = encodeParams(mockUniPair, OBSERVATION_SECONDS);
        uniSubmodule.getTokenTWAP(USDC, PRICE_DECIMALS, params);
    }
}
