// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockUniswapV2Pool} from "test/mocks/MockUniswapV2Pool.sol";
import {MockBalancerPool} from "test/mocks/MockBalancerPool.sol";
import {FullMath} from "libraries/FullMath.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {UniswapV2PoolTokenPrice, IUniswapV2Pool} from "modules/PRICE/submodules/feeds/UniswapV2PoolTokenPrice.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";

contract UniswapV2PoolTokenPriceTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for UniswapV2PoolTokenPrice;

    MockPrice internal mockPrice;
    MockUniswapV2Pool internal mockPool;

    UniswapV2PoolTokenPrice internal uniswapSubmodule;

    address internal WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint8 internal USDC_DECIMALS = 6;
    uint8 internal WETH_DECIMALS = 18;

    uint8 internal PRICE_DECIMALS = 18;

    uint256 internal USDC_PRICE = 10 ** PRICE_DECIMALS;
    uint256 internal WETH_PRICE = 1500 * 10 ** PRICE_DECIMALS;

    uint256 internal POOL_TOTAL_SUPPLY = 317666716043426622;

    uint112 internal POOL_RESERVES_USDC = 28665621757566; // USDC decimals
    uint256 internal POOL_RESERVES_NORMALISED_USDC =
        uint256(POOL_RESERVES_USDC).mulDiv(10 ** PRICE_DECIMALS, 10 ** USDC_DECIMALS);
    uint112 internal POOL_RESERVES_WETH = 16305438433928411610381; // WETH decimals
    uint256 internal POOL_RESERVES_NORMALISED_WETH =
        uint256(POOL_RESERVES_WETH).mulDiv(10 ** PRICE_DECIMALS, 10 ** WETH_DECIMALS);

    uint256 internal POOL_PRICE_EXPECTED =
        (((((uint256(POOL_RESERVES_USDC) * 1e18) / 1e6) * USDC_PRICE) / 1e18) +
            (((POOL_RESERVES_WETH) * WETH_PRICE) / 1e18)).mulDiv(1e18, POOL_TOTAL_SUPPLY);

    // https://cmichel.io/pricing-lp-tokens/
    uint256 internal POOL_FAIR_PRICE_EXPECTED =
        (uint256(2e18)).mulDiv(
            FixedPointMathLib.sqrt(
                USDC_PRICE.mulDiv(WETH_PRICE, 1e18) *
                    (POOL_RESERVES_NORMALISED_USDC.mulDiv(POOL_RESERVES_NORMALISED_WETH, 1e18))
            ),
            POOL_TOTAL_SUPPLY
        );

    // (base reserves / destination reserves) * base rate
    uint256 internal WETH_PRICE_EXPECTED =
        (uint256(POOL_RESERVES_USDC) * 1e12 * 1e18).mulDiv(
            USDC_PRICE,
            (uint256(POOL_RESERVES_WETH) * 1e18)
        );
    uint256 internal USDC_PRICE_EXPECTED =
        (uint256(POOL_RESERVES_WETH) * 1e18).mulDiv(
            WETH_PRICE,
            (uint256(POOL_RESERVES_USDC) * 1e12 * 1e18)
        );

    uint8 MIN_DECIMALS = 6;
    uint8 MAX_DECIMALS = 26;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Set up the mock pool
        {
            mockPool = new MockUniswapV2Pool();
            mockPool.setTotalSupply(POOL_TOTAL_SUPPLY);
            mockPool.setToken0(USDC);
            mockPool.setToken1(WETH);
            mockPool.setReserves(POOL_RESERVES_USDC, POOL_RESERVES_WETH);
        }

        // Set up the UniswapV2 submodule
        {
            Kernel kernel = new Kernel();
            mockPrice = new MockPrice(kernel, uint8(18), uint32(8 hours));
            mockPrice.setTimestamp(uint48(block.timestamp));
            mockPrice.setPriceDecimals(PRICE_DECIMALS);
            uniswapSubmodule = new UniswapV2PoolTokenPrice(mockPrice);
        }

        // Mock prices from PRICE
        {
            mockAssetPrice(USDC, USDC_PRICE);
            mockAssetPrice(WETH, WETH_PRICE);
        }

        // Mock ERC20 decimals
        {
            mockERC20Decimals(USDC, USDC_DECIMALS);
            mockERC20Decimals(WETH, WETH_DECIMALS);
        }
    }

    // =========  HELPER METHODS ========= //

    function mockERC20Decimals(address asset_, uint8 decimals_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }

    function mockAssetPrice(address asset_, uint256 price_) internal {
        mockPrice.setPrice(asset_, price_);
    }

    function encodePoolParams(IUniswapV2Pool pool) internal pure returns (bytes memory params) {
        return abi.encode(pool);
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

    function _assertEqTruncated(
        uint256 expected,
        uint8 expectedDecimals,
        uint256 actual,
        uint8 actualDecimals,
        uint8 decimals,
        uint256 delta
    ) internal {
        // Simpler to check that the price to 2 decimal places (e.g. $10.01) is equal
        uint256 truncatedActual = actual.mulDiv(10 ** decimals, 10 ** actualDecimals);
        uint256 truncatedExpected = expected.mulDiv(10 ** decimals, 10 ** expectedDecimals);

        assertApproxEqAbs(truncatedExpected, truncatedActual, delta);
    }

    // ========= POOL TOKEN PRICE ========= //

    function test_getPoolTokenPrice_revertsOnParamsPoolUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_ParamsPoolInvalid.selector,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(IUniswapV2Pool(address(0)));
        uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPrice_revertsOnPriceZero() public {
        mockAssetPrice(USDC, 0);

        expectRevert_PriceZero(USDC);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPrice_revertsOnCoinBalanceOneZero() public {
        mockPool.setReserves(0, POOL_RESERVES_WETH);

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_PoolTokenBalanceInvalid.selector,
            address(mockPool),
            0,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPrice_revertsOnCoinBalanceTwoZero() public {
        mockPool.setReserves(POOL_RESERVES_USDC, 0);

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_PoolTokenBalanceInvalid.selector,
            address(mockPool),
            1,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPrice_success() public {
        bytes memory params = encodePoolParams(mockPool);
        uint256 price = uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);

        // Uses outputDecimals_ parameter
        assertEq(price, POOL_FAIR_PRICE_EXPECTED);
    }

    function test_getPoolTokenPrice_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));
        mockAssetPrice(WETH, WETH_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));

        bytes memory params = encodePoolParams(mockPool);
        uint256 price = uniswapSubmodule.getPoolTokenPrice(address(0), priceDecimals, params);

        // At low values of priceDecimals, calculations will be imprecise, so keep this check imprecise
        _assertEqTruncated(
            POOL_FAIR_PRICE_EXPECTED,
            PRICE_DECIMALS,
            price,
            priceDecimals,
            2,
            10 ** 5
        );
    }

    function test_getPoolTokenPrice_revertsOnPriceDecimalsMaximum() public {
        // Mock a PRICE implementation with a higher number of decimals
        uint8 priceDecimals = MAX_DECIMALS + 1;

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_OutputDecimalsOutOfBounds.selector,
            priceDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getPoolTokenPrice(address(0), priceDecimals, params);
    }

    function test_getPoolTokenPrice_tokenDecimalsFuzz(
        uint8 token0Decimals_,
        uint8 token1Decimals_
    ) public {
        uint8 token0Decimals = uint8(bound(token0Decimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint8 token1Decimals = uint8(bound(token1Decimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockERC20Decimals(USDC, token0Decimals);
        mockERC20Decimals(WETH, token1Decimals);
        mockPool.setReserves(
            uint112(uint256(POOL_RESERVES_USDC).mulDiv(10 ** token0Decimals, 10 ** USDC_DECIMALS)),
            uint112(uint256(POOL_RESERVES_WETH).mulDiv(10 ** token1Decimals, 10 ** WETH_DECIMALS))
        );

        bytes memory params = encodePoolParams(mockPool);
        uint256 price = uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);

        // At low values of priceDecimals, calculations will be imprecise, so keep this check imprecise
        _assertEqTruncated(POOL_FAIR_PRICE_EXPECTED, PRICE_DECIMALS, price, PRICE_DECIMALS, 2, 1);
    }

    function test_getPoolTokenPrice_fuzz(
        uint8 token0Decimals_,
        uint8 token1Decimals_,
        uint8 priceDecimals_
    ) public {
        uint8 token0Decimals = uint8(bound(token0Decimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint8 token1Decimals = uint8(bound(token1Decimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockERC20Decimals(USDC, token0Decimals);
        mockERC20Decimals(WETH, token1Decimals);
        mockPool.setReserves(
            uint112(uint256(POOL_RESERVES_USDC).mulDiv(10 ** token0Decimals, 10 ** USDC_DECIMALS)),
            uint112(uint256(POOL_RESERVES_WETH).mulDiv(10 ** token1Decimals, 10 ** WETH_DECIMALS))
        );

        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));
        mockAssetPrice(WETH, WETH_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));

        bytes memory params = encodePoolParams(mockPool);
        uint256 price = uniswapSubmodule.getPoolTokenPrice(address(0), priceDecimals, params);

        // At low values of priceDecimals, calculations will be imprecise, so keep this check imprecise
        _assertEqTruncated(
            POOL_FAIR_PRICE_EXPECTED,
            PRICE_DECIMALS,
            price,
            priceDecimals,
            2,
            10 ** 5
        );
    }

    function test_getPoolTokenPrice_revertsOnToken0DecimalsMaximum() public {
        mockERC20Decimals(USDC, 100);

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_AssetDecimalsOutOfBounds.selector,
            address(USDC),
            100,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPrice_revertsOnToken1DecimalsMaximum() public {
        mockERC20Decimals(WETH, 100);

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_AssetDecimalsOutOfBounds.selector,
            address(WETH),
            100,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPrice_revertsOnToken0AddressZero() public {
        mockPool.setToken0(address(0));

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_PoolTokensInvalid.selector,
            address(mockPool),
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPrice_revertsOnToken1AddressZero() public {
        mockPool.setToken1(address(0));

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_PoolTokensInvalid.selector,
            address(mockPool),
            1,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPrice_revertsOnPoolTokenSupplyZero() public {
        mockPool.setTotalSupply(0);

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_PoolSupplyInvalid.selector,
            address(mockPool),
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPrice_revertsOnIncorrectPoolType() public {
        mockAssetPrice(WETH, 0); // Stops lookup

        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        expectRevert_address(
            UniswapV2PoolTokenPrice.UniswapV2_PoolTypeInvalid.selector,
            address(mockNonWeightedPool)
        );

        bytes memory params = abi.encode(mockNonWeightedPool);
        uniswapSubmodule.getPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    // ========= TOKEN PRICE ========= //

    function test_getTokenPrice_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));
        mockAssetPrice(WETH, 0); // Stops lookup

        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));

        bytes memory params = encodePoolParams(mockPool);
        uint256 price = uniswapSubmodule.getTokenPrice(WETH, priceDecimals, params);

        // Will be normalised to outputDecimals_
        uint8 decimalDiff = priceDecimals > 18 ? priceDecimals - 18 : 18 - priceDecimals;
        assertApproxEqAbs(
            price,
            WETH_PRICE_EXPECTED.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS),
            10 ** decimalDiff
        );
    }

    function test_getTokenPrice_revertsOnParamsPoolUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_ParamsPoolInvalid.selector,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(IUniswapV2Pool(address(0)));
        uniswapSubmodule.getTokenPrice(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPrice_revertsOnPriceDecimalsMaximum() public {
        mockAssetPrice(WETH, 0); // Stops lookup

        mockAssetPrice(USDC, (USDC_PRICE * 1e21) / 1e18);

        uint8 priceDecimals = MAX_DECIMALS + 1;

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_OutputDecimalsOutOfBounds.selector,
            priceDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getTokenPrice(WETH, priceDecimals, params);
    }

    function test_getTokenPrice_tokenDecimalsFuzz(uint8 tokenDecimals_) public {
        uint8 tokenDecimals = uint8(bound(tokenDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockAssetPrice(WETH, 0); // Stops lookup

        mockERC20Decimals(USDC, tokenDecimals);
        mockPool.setReserves(
            uint112(uint256(POOL_RESERVES_USDC).mulDiv(10 ** tokenDecimals, 10 ** USDC_DECIMALS)),
            POOL_RESERVES_WETH
        );

        bytes memory params = encodePoolParams(mockPool);
        uint256 price = uniswapSubmodule.getTokenPrice(WETH, PRICE_DECIMALS, params);

        // Will be normalised to outputDecimals_
        assertEq(price, WETH_PRICE_EXPECTED);
    }

    function test_getTokenPrice_revertsOnTokenDecimalsMaximum() public {
        mockAssetPrice(WETH, 0); // Stops lookup

        mockERC20Decimals(USDC, 100);

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_AssetDecimalsOutOfBounds.selector,
            address(USDC),
            100,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getTokenPrice(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPrice_revertsOnUnknownToken() public {
        mockAssetPrice(WETH, 0); // Stops lookup

        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_LookupTokenNotFound.selector,
            address(mockPool),
            DAI
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getTokenPrice(DAI, PRICE_DECIMALS, params);
    }

    function test_getTokenPrice_revertsOnPriceZero() public {
        mockAssetPrice(WETH, 0); // Stops lookup

        // PRICE not configured to handle the asset, returns 0
        mockAssetPrice(USDC, 0);

        expectRevert_PriceZero(USDC);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getTokenPrice(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPrice_revertsOnCoinOneZero() public {
        mockAssetPrice(WETH, 0); // Stops lookup

        mockPool.setToken0(address(0));

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_PoolTokensInvalid.selector,
            address(mockPool),
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getTokenPrice(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPrice_revertsOnCoinTwoZero() public {
        mockAssetPrice(WETH, 0); // Stops lookup

        mockPool.setToken1(address(0));

        bytes memory err = abi.encodeWithSelector(
            UniswapV2PoolTokenPrice.UniswapV2_PoolTokensInvalid.selector,
            address(mockPool),
            1,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodePoolParams(mockPool);
        uniswapSubmodule.getTokenPrice(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPrice_inverse() public {
        mockAssetPrice(USDC, 0);
        mockAssetPrice(WETH, WETH_PRICE);

        bytes memory params = encodePoolParams(mockPool);
        uint256 price = uniswapSubmodule.getTokenPrice(USDC, PRICE_DECIMALS, params);

        assertEq(price, USDC_PRICE_EXPECTED);
    }

    function test_getTokenPrice_revertsOnIncorrectPoolType() public {
        mockAssetPrice(WETH, 0); // Stops lookup

        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        expectRevert_address(
            UniswapV2PoolTokenPrice.UniswapV2_PoolTypeInvalid.selector,
            address(mockNonWeightedPool)
        );

        bytes memory params = abi.encode(mockNonWeightedPool);
        uniswapSubmodule.getTokenPrice(WETH, PRICE_DECIMALS, params);
    }
}
