// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockCurvePool, MockCurvePoolTwoCrypto} from "test/mocks/MockCurvePool.sol";
import {FullMath} from "libraries/FullMath.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {CurvePoolTokenPrice, ICurvePoolTwoCrypto} from "modules/PRICE/submodules/feeds/CurvePoolTokenPrice.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";

contract CurvePoolTokenPriceTwoCryptoTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for CurvePoolTokenPrice;

    MockPrice internal mockPrice;
    MockCurvePoolTwoCrypto internal mockPool;

    CurvePoolTokenPrice internal curveSubmodule;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant  USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant  USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant  WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant  BTRFLY = 0xc55126051B22eBb829D00368f4B12Bde432de5Da;
    address internal constant  STG = 0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6;

    uint256 internal constant  USDT_PRICE = 1 * 1e18;
    uint256 internal constant  WETH_PRICE = 1_500 * 1e18;

    uint8 internal constant  USDT_DECIMALS = 6;
    uint8 internal constant  WETH_DECIMALS = 18;

    uint256 internal constant  USDT_BALANCE = 50_000_000 * 1e6;
    uint256 internal constant  WETH_BALANCE = 3_000 * 1e18;

    uint8 internal constant  PRICE_DECIMALS = 18;

    address internal constant  TWO_CRYPTO_TOKEN = 0xc4AD29ba4B3c580e6D59105FFf484999997675Ff;
    uint256 internal constant  TWO_CRYPTO_SUPPLY = 181486344521982698524711;
    uint256 internal constant  TWO_CRYPTO_PRICE =
        (USDT_BALANCE * 1e12 * USDT_PRICE + WETH_BALANCE * WETH_PRICE) / TWO_CRYPTO_SUPPLY;
    uint8 internal constant  TWO_CRYPTO_TOKEN_DECIMALS = 18;

    uint8 internal constant MIN_DECIMALS = 6;
    uint8 internal constant MAX_DECIMALS = 60;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Set up the Curve submodule
        {
            Kernel kernel = new Kernel();
            mockPrice = new MockPrice(kernel, uint8(18), uint32(8 hours));
            mockPrice.setTimestamp(uint48(block.timestamp));
            mockPrice.setPriceDecimals(PRICE_DECIMALS);
            curveSubmodule = new CurvePoolTokenPrice(mockPrice);
        }

        // Set up the mock curve pool
        {
            mockPool = new MockCurvePoolTwoCrypto();

            mockPool.setCoinsTwo(USDT, WETH);
            mockPool.setBalancesTwo(USDT_BALANCE, WETH_BALANCE);
            mockPool.setToken(TWO_CRYPTO_TOKEN);
        }

        // Mock prices from PRICE
        {
            mockPrice.setPrice(USDT, USDT_PRICE);
            mockPrice.setPrice(WETH, WETH_PRICE);
        }

        // Mock ERC20 decimals
        {
            mockERC20Decimals(USDT, USDT_DECIMALS);
            mockERC20Decimals(WETH, WETH_DECIMALS);
            mockERC20Decimals(TWO_CRYPTO_TOKEN, TWO_CRYPTO_TOKEN_DECIMALS);

            mockERC20TotalSupply(TWO_CRYPTO_TOKEN, TWO_CRYPTO_SUPPLY);
        }
    }

    // =========  HELPER METHODS ========= //

    function mockERC20Decimals(address asset_, uint8 decimals_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }

    function mockERC20TotalSupply(address asset_, uint256 totalSupply_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("totalSupply()"), abi.encode(totalSupply_));
    }

    function mockAssetPrice(address asset_, uint256 price_) internal {
        mockPrice.setPrice(asset_, price_);
    }

    function encodeCurvePoolTwoCryptoParams(
        ICurvePoolTwoCrypto pool
    ) internal pure returns (bytes memory params) {
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

    // ========= LP TOKEN PRICE - TWO-CRYPTO POOL ========= //

    // Notes:
    // - Pool decimals can't be set, so there's no point in testing them

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnParamsPoolUndefined() public {
        expectRevert_address(CurvePoolTokenPrice.Curve_PoolTypeNotTwoCrypto.selector, address(0));

        bytes memory params = encodeCurvePoolTwoCryptoParams(ICurvePoolTwoCrypto(address(0)));
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnPriceZero() public {
        mockAssetPrice(USDT, 0);

        // Passes revert from PRICE as the LP token price cannot be calculated without it
        expectRevert_PriceZero(USDT);

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnCoinBalanceOneZero() public {
        mockPool.setBalancesTwo(0, WETH_BALANCE);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolBalancesInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnCoinBalanceTwoZero() public {
        mockPool.setBalancesTwo(USDT_BALANCE, 0);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolBalancesInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnCoinBalanceCountDifferent() public {
        // Two coins, one balance
        uint256[] memory balances = new uint256[](1);
        balances[0] = USDT_BALANCE;
        mockPool.setBalances(balances);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokenBalancesMismatch.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_lpTokenDecimalsFuzz(
        uint8 lpTokenDecimals_
    ) public {
        uint8 lpTokenDecimals = uint8(bound(lpTokenDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockERC20Decimals(TWO_CRYPTO_TOKEN, lpTokenDecimals);
        mockERC20TotalSupply(
            TWO_CRYPTO_TOKEN,
            TWO_CRYPTO_SUPPLY.mulDiv(10 ** lpTokenDecimals, 10 ** TWO_CRYPTO_TOKEN_DECIMALS)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);

        uint8 decimalDiff = lpTokenDecimals > PRICE_DECIMALS
            ? lpTokenDecimals - PRICE_DECIMALS
            : PRICE_DECIMALS - lpTokenDecimals;
        assertApproxEqAbs(price, TWO_CRYPTO_PRICE, 10 ** decimalDiff);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnLpTokenDecimalsMaximum() public {
        mockERC20Decimals(TWO_CRYPTO_TOKEN, 100);
        mockERC20TotalSupply(TWO_CRYPTO_TOKEN, TWO_CRYPTO_SUPPLY);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokenDecimalsOutOfBounds.selector,
            address(TWO_CRYPTO_TOKEN)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_priceDecimalsFuzz(
        uint8 priceDecimals_
    ) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        // Mock a PRICE implementation with a higher number of decimals
        mockPrice.setPrice(USDT, USDT_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));
        mockPrice.setPrice(WETH, WETH_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), priceDecimals, params);

        // Uses outputDecimals_
        uint8 decimalDiff = priceDecimals > PRICE_DECIMALS
            ? priceDecimals - PRICE_DECIMALS
            : PRICE_DECIMALS - priceDecimals;
        assertApproxEqAbs(
            price,
            TWO_CRYPTO_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS),
            10 ** decimalDiff
        );
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnPriceDecimalsMaximum() public {
        // Mock a PRICE implementation with a higher number of decimals
        uint8 priceDecimals = MAX_DECIMALS + 1;
        expectRevert_uint8(
            CurvePoolTokenPrice.Curve_OutputDecimalsOutOfBounds.selector,
            priceDecimals
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), priceDecimals, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_Fuzz(
        uint8 priceDecimals_,
        uint8 lpTokenDecimals_
    ) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint8 lpTokenDecimals = uint8(bound(lpTokenDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        // Mock a PRICE implementation with a higher number of decimals
        mockPrice.setPrice(USDT, USDT_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));
        mockPrice.setPrice(WETH, WETH_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));

        mockERC20Decimals(TWO_CRYPTO_TOKEN, lpTokenDecimals);
        mockERC20TotalSupply(
            TWO_CRYPTO_TOKEN,
            TWO_CRYPTO_SUPPLY.mulDiv(10 ** lpTokenDecimals, 10 ** TWO_CRYPTO_TOKEN_DECIMALS)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), priceDecimals, params);

        // Simpler to check that the price to 2 decimal places (e.g. $10.01) is equal
        uint256 truncatedPrice = price.mulDiv(10 ** 2, 10 ** priceDecimals);
        uint256 truncatedExpectedPrice = TWO_CRYPTO_PRICE.mulDiv(10 ** 2, 10 ** PRICE_DECIMALS);
        assertEq(truncatedPrice, truncatedExpectedPrice);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnZeroCoins() public {
        // Mock 0 coins
        address[] memory coins = new address[](0);
        mockPool.setCoins(coins);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnCoinOneAddressZero() public {
        mockPool.setCoinsTwo(address(0), WETH);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnCoinTwoAddressZero() public {
        mockPool.setCoinsTwo(USDT, address(0));

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnMissingLpToken() public {
        mockPool.setToken(address(0));

        expectRevert_address(CurvePoolTokenPrice.Curve_PoolTokenNotSet.selector, address(mockPool));

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnLpTokenSupplyZero() public {
        mockERC20TotalSupply(TWO_CRYPTO_TOKEN, 0);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolSupplyInvalid.selector,
            address(TWO_CRYPTO_TOKEN)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromTwoCryptoPool_revertsOnIncorrectPoolType() public {
        MockCurvePool mockStablePool = new MockCurvePool();

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTypeNotTwoCrypto.selector,
            address(mockStablePool)
        );

        bytes memory params = abi.encode(mockStablePool);
        curveSubmodule.getPoolTokenPriceFromTwoCryptoPool(address(0), PRICE_DECIMALS, params);
    }

    // ========= TOKEN PRICE LOOKUP - TWO-CRYPTO POOL ========= //

    uint256 internal priceOracleEthBtrfly = 187339411560870503; // Decimals: 18
    uint256 internal priceOracleStgUsdc = 1457965683083856087; // Decimals: 18

    function setUpWethBtrfly() public {
        mockPool = new MockCurvePoolTwoCrypto();
        mockPool.set_price_oracle(priceOracleEthBtrfly);

        mockPool.setCoinsTwo(WETH, BTRFLY);

        mockAssetPrice(WETH, WETH_PRICE);

        mockERC20Decimals(WETH, WETH_DECIMALS);
        mockERC20Decimals(BTRFLY, 18);
    }

    function setUpStgUsdc() public {
        mockPool = new MockCurvePoolTwoCrypto();
        mockPool.set_price_oracle(priceOracleStgUsdc);

        mockPool.setCoinsTwo(STG, USDC);

        mockAssetPrice(USDC, 10 ** PRICE_DECIMALS);

        mockERC20Decimals(USDC, 6);
        mockERC20Decimals(STG, 18);
    }

    function test_getTokenPriceFromTwoCryptoPool_success() public {
        setUpWethBtrfly();

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromTwoCryptoPool(BTRFLY, PRICE_DECIMALS, params);

        // 187339411560870503*1500*10^18 / 10^18
        // 281009117341305754500
        // $281.0091173413
        assertEq(price, priceOracleEthBtrfly.mulDiv(WETH_PRICE, 10 ** PRICE_DECIMALS));
    }

    function test_getTokenPriceFromTwoCryptoPool_revertsOnParamsPoolUndefined() public {
        setUpWethBtrfly();

        expectRevert_address(CurvePoolTokenPrice.Curve_PoolTypeNotTwoCrypto.selector, address(0));

        bytes memory params = encodeCurvePoolTwoCryptoParams(ICurvePoolTwoCrypto(address(0)));
        curveSubmodule.getTokenPriceFromTwoCryptoPool(BTRFLY, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromTwoCryptoPool_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, 2, MAX_DECIMALS));

        setUpWethBtrfly();

        uint256 wethPrice = WETH_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS);
        mockPrice.setPrice(WETH, wethPrice);

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromTwoCryptoPool(BTRFLY, priceDecimals, params);

        // Will be normalised to outputDecimals_
        assertEq(price, priceOracleEthBtrfly.mulDiv(wethPrice, 10 ** PRICE_DECIMALS));
    }

    function test_getTokenPriceFromTwoCryptoPool_revertsOnPriceDecimalsMaximum() public {
        setUpWethBtrfly();

        uint8 priceDecimals = MAX_DECIMALS + 1;
        mockAssetPrice(WETH, (WETH_PRICE * 1e21) / 10 ** PRICE_DECIMALS);

        expectRevert_uint8(
            CurvePoolTokenPrice.Curve_OutputDecimalsOutOfBounds.selector,
            priceDecimals
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTwoCryptoPool(BTRFLY, priceDecimals, params);
    }

    function test_getTokenPriceFromTwoCryptoPool_revertsOnUnknownToken() public {
        setUpWethBtrfly();

        expectRevert_address(CurvePoolTokenPrice.Curve_LookupTokenNotFound.selector, DAI);

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTwoCryptoPool(DAI, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromTwoCryptoPool_revertsOnNoPrice() public {
        setUpWethBtrfly();

        // PRICE not configured to handle the asset, returns 0
        mockAssetPrice(WETH, 0);

        expectRevert_address(CurvePoolTokenPrice.Curve_PriceNotFound.selector, address(mockPool));

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTwoCryptoPool(BTRFLY, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromTwoCryptoPool_revertsOnCoinOneZero() public {
        setUpWethBtrfly();
        mockPool.setCoinsTwo(address(0), BTRFLY);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTwoCryptoPool(BTRFLY, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromTwoCryptoPool_revertsOnCoinTwoZero() public {
        setUpWethBtrfly();
        mockPool.setCoinsTwo(WETH, address(0));

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTwoCryptoPool(BTRFLY, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromTwoCryptoPool_inverseOrientation() public {
        setUpStgUsdc();

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromTwoCryptoPool(STG, PRICE_DECIMALS, params);

        // price_oracle = 1457965683083856087 = 1.4579656831
        // 1 USDC = 1.4579656831 STG
        // 1 USDC = $1
        // 1 STG = 1 / 1.4579656831 = 0.6858871999 USDC
        // 1 STG = 0.6858871999 * $1 = $0.6858871999
        assertEq(price, ((10 ** PRICE_DECIMALS * 10 ** PRICE_DECIMALS) / priceOracleStgUsdc));
    }

    function test_getTokenPriceFromTwoCryptoPool_inverseOrientationRespectsPrice() public {
        setUpStgUsdc();
        mockAssetPrice(USDC, 1.01 * 1e18);

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromTwoCryptoPool(STG, PRICE_DECIMALS, params);

        // price_oracle = 1457965683083856087 = 1.4579656831
        // 1 USDC = 1.4579656831 STG
        // 1 USDC = $1.01
        // 1 STG = 1 / 1.4579656831 = 0.6858871999 USDC
        // 1 STG = 0.6858871999 * $1.01 = $0.69
        assertEq(price, ((1.01 * 1e18 * 1e18) / priceOracleStgUsdc));
    }

    function test_getTokenPriceFromTwoCryptoPool_revertsOnPriceOracleZero() public {
        setUpWethBtrfly();
        mockPool.set_price_oracle(0);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolPriceOracleInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTwoCryptoPool(BTRFLY, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromTwoCryptoPool_inverseOrientation_priceOracleZero() public {
        setUpStgUsdc();
        mockPool.set_price_oracle(0);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolPriceOracleInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTwoCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTwoCryptoPool(STG, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromTwoCryptoPool_incorrectPoolType() public {
        setUpWethBtrfly();
        MockCurvePool mockStablePool = new MockCurvePool();

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTypeNotTwoCrypto.selector,
            address(mockStablePool)
        );

        bytes memory params = abi.encode(mockStablePool);
        curveSubmodule.getTokenPriceFromTwoCryptoPool(BTRFLY, PRICE_DECIMALS, params);
    }
}
