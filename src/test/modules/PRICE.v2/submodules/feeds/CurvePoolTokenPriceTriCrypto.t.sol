// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockCurvePool, MockCurvePoolTriCrypto} from "test/mocks/MockCurvePool.sol";
import {FullMath} from "libraries/FullMath.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {CurvePoolTokenPrice, ICurvePoolTriCrypto} from "modules/PRICE/submodules/feeds/CurvePoolTokenPrice.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";

contract CurvePoolTokenPriceTriCryptoTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for CurvePoolTokenPrice;

    MockPrice internal mockPrice;
    MockCurvePoolTriCrypto internal mockPool;

    CurvePoolTokenPrice internal curveSubmodule;

    address internal USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal USDT_PRICE = 1 * 1e18;
    uint256 internal WETH_PRICE = 1_500 * 1e18;
    uint256 internal WBTC_PRICE = 20_000 * 1e18;

    uint8 internal USDT_DECIMALS = 6;
    uint8 internal WETH_DECIMALS = 18;
    uint8 internal WBTC_DECIMALS = 18;

    uint256 internal USDT_BALANCE = 50_000_000 * 1e6;
    uint256 internal WETH_BALANCE = 3_000 * 1e18;
    uint256 internal WBTC_BALANCE = 40_000 * 1e18;

    uint8 internal PRICE_DECIMALS = 18;

    address internal TRI_CRYPTO_TOKEN = 0xc4AD29ba4B3c580e6D59105FFf484999997675Ff;
    uint8 internal TRI_CRYPTO_DECIMALS = 18;
    uint256 internal TRI_CRYPTO_SUPPLY = 181486344521982698524711;
    uint256 internal TRI_CRYPTO_PRICE =
        (USDT_BALANCE * 1e12 * USDT_PRICE + WETH_BALANCE * WETH_PRICE + WBTC_BALANCE * WBTC_PRICE) /
            TRI_CRYPTO_SUPPLY;

    uint256 internal priceOracleWbtcUsdt = 21657103424510020784247; // Decimals: 18
    uint256 internal priceOracleWethUsdt = 1530492432190963892950; // Decimals: 18

    uint8 MIN_DECIMALS = 6;
    uint8 MAX_DECIMALS = 60;

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
            mockPool = new MockCurvePoolTriCrypto();
            mockPool.setCoinsThree(USDT, WBTC, WETH);
            mockPool.setBalancesThree(USDT_BALANCE, WBTC_BALANCE, WETH_BALANCE);
            mockPool.setToken(TRI_CRYPTO_TOKEN);

            uint256[] memory price_oracle = new uint256[](2);
            price_oracle[0] = priceOracleWbtcUsdt;
            price_oracle[1] = priceOracleWethUsdt;
            mockPool.set_price_oracle(price_oracle);
        }

        // Mock prices from PRICE
        {
            mockPrice.setPrice(USDT, USDT_PRICE);
            mockPrice.setPrice(WETH, WETH_PRICE);
            mockPrice.setPrice(WBTC, WBTC_PRICE);
        }

        // Mock ERC20 decimals
        {
            mockERC20Decimals(USDT, USDT_DECIMALS);
            mockERC20Decimals(WETH, WETH_DECIMALS);
            mockERC20Decimals(WBTC, WBTC_DECIMALS);
            mockERC20Decimals(TRI_CRYPTO_TOKEN, TRI_CRYPTO_DECIMALS);

            mockERC20TotalSupply(TRI_CRYPTO_TOKEN, TRI_CRYPTO_SUPPLY);
        }
    }

    // =========  HELPER METHODS ========= //

    function mockERC20Decimals(address asset_, uint8 decimals_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }

    function mockERC20TotalSupply(address asset_, uint256 totalSupply_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("totalSupply()"), abi.encode(totalSupply_));
    }

    function encodeCurvePoolTriCryptoParams(
        ICurvePoolTriCrypto pool
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

    // ========= LP TOKEN PRICE - TRI-CRYPTO POOL ========= //

    // Notes:
    // - Pool decimals can't be set, so there's no point in testing them

    function test_getPoolTokenPriceFromTriCryptoPool_threeCoins() public {
        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);

        assertApproxEqAbs(price, TRI_CRYPTO_PRICE, 1e9);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_revertsOnPriceZero() public {
        mockPrice.setPrice(USDT, 0);

        // Passes revert from PRICE as the LP token price cannot be calculated without it
        expectRevert_PriceZero(USDT);

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_revertsOnCoinBalanceOneZero() public {
        mockPool.setBalancesThree(0, WETH_BALANCE, WBTC_BALANCE);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolBalancesInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_revertsOnCoinBalanceTwoZero() public {
        mockPool.setBalancesThree(USDT_BALANCE, 0, WBTC_BALANCE);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolBalancesInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_revertsOnCoinBalanceThreeZero() public {
        mockPool.setBalancesThree(USDT_BALANCE, WETH_BALANCE, 0);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolBalancesInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_revertsOnCoinBalanceCountDifferent() public {
        // Three coins, two balances
        mockPool.setBalancesTwo(USDT_BALANCE, WETH_BALANCE);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokenBalancesMismatch.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_lpTokenDecimalsFuzz(
        uint8 lpTokenDecimals_
    ) public {
        uint8 lpTokenDecimals = uint8(bound(lpTokenDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockERC20Decimals(TRI_CRYPTO_TOKEN, lpTokenDecimals);
        mockERC20TotalSupply(
            TRI_CRYPTO_TOKEN,
            TRI_CRYPTO_SUPPLY.mulDiv(10 ** lpTokenDecimals, 10 ** TRI_CRYPTO_DECIMALS)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);

        // Simpler to check that the price to 2 decimal places (e.g. $10.01) is equal
        uint256 truncatedPrice = price.mulDiv(10 ** 2, 10 ** PRICE_DECIMALS);
        uint256 truncatedExpectedPrice = TRI_CRYPTO_PRICE.mulDiv(10 ** 2, 10 ** PRICE_DECIMALS);
        assertEq(truncatedPrice, truncatedExpectedPrice);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_revertsOnLpTokenDecimalsMaximum() public {
        mockERC20Decimals(TRI_CRYPTO_TOKEN, 100);
        mockERC20TotalSupply(TRI_CRYPTO_TOKEN, TRI_CRYPTO_SUPPLY);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokenDecimalsOutOfBounds.selector,
            TRI_CRYPTO_TOKEN
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_priceDecimalsFuzz(
        uint8 priceDecimals_
    ) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        // Mock a PRICE implementation with a fewer number of decimals
        mockPrice.setPriceDecimals(priceDecimals);
        mockPrice.setPrice(USDT, USDT_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));
        mockPrice.setPrice(WETH, WETH_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));
        mockPrice.setPrice(WBTC, WBTC_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);

        // Uses price decimals
        uint8 decimalDiff = priceDecimals > 18 ? priceDecimals - 18 : 18 - priceDecimals;
        assertApproxEqAbs(
            price,
            TRI_CRYPTO_PRICE.mulDiv(10 ** priceDecimals, 1e18),
            10 ** decimalDiff
        );
    }

    function test_getPoolTokenPriceFromTriCryptoPool_priceDecimalsMaximum() public {
        // Mock a PRICE implementation with a higher number of decimals
        mockPrice.setPriceDecimals(100);
        mockPrice.setPrice(USDT, USDT_PRICE);
        mockPrice.setPrice(WETH, WETH_PRICE);
        mockPrice.setPrice(WBTC, WBTC_PRICE);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PRICEDecimalsOutOfBounds.selector,
            address(mockPrice)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_fuzz(
        uint8 lpTokenDecimals_,
        uint8 priceDecimals_
    ) public {
        uint8 lpTokenDecimals = uint8(bound(lpTokenDecimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockERC20Decimals(TRI_CRYPTO_TOKEN, lpTokenDecimals);
        mockERC20TotalSupply(
            TRI_CRYPTO_TOKEN,
            TRI_CRYPTO_SUPPLY.mulDiv(10 ** lpTokenDecimals, 10 ** TRI_CRYPTO_DECIMALS)
        );

        mockPrice.setPriceDecimals(priceDecimals);
        mockPrice.setPrice(USDT, USDT_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));
        mockPrice.setPrice(WETH, WETH_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));
        mockPrice.setPrice(WBTC, WBTC_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS));

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);

        // Simpler to check that the price to 2 decimal places (e.g. $10.01) is equal
        uint256 truncatedPrice = price.mulDiv(10 ** 2, 10 ** priceDecimals);
        uint256 truncatedExpectedPrice = TRI_CRYPTO_PRICE.mulDiv(10 ** 2, 10 ** PRICE_DECIMALS);
        assertEq(truncatedPrice, truncatedExpectedPrice);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_revertsOnZeroCoins() public {
        // Mock 0 coins
        address[] memory coins = new address[](0);
        mockPool.setCoins(coins);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_revertsOnCoinOneAddressZero() public {
        mockPool.setCoinsThree(address(0), WETH, WBTC);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_revertsOnCoinTwoAddressZero() public {
        mockPool.setCoinsThree(USDT, address(0), WBTC);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_revertsOnCoinThreeAddressZero() public {
        mockPool.setCoinsThree(USDT, WETH, address(0));

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_revertsOnMissingLpToken() public {
        mockPool.setToken(address(0));

        expectRevert_address(CurvePoolTokenPrice.Curve_PoolTokenNotSet.selector, address(mockPool));

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_lpTokenSupplyZero() public {
        mockERC20TotalSupply(TRI_CRYPTO_TOKEN, 0);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolSupplyInvalid.selector,
            TRI_CRYPTO_TOKEN
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    function test_getPoolTokenPriceFromTriCryptoPool_incorrectPoolType() public {
        MockCurvePool mockStablePool = new MockCurvePool();

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTypeNotTriCrypto.selector,
            address(mockStablePool)
        );

        bytes memory params = abi.encode(mockStablePool);
        curveSubmodule.getPoolTokenPriceFromTriCryptoPool(params);
    }

    // ========= TOKEN PRICE LOOKUP - TRI-CRYPTO POOL ========= //

    function test_getTokenPriceFromTriCryptoPool_coinTwo() public {
        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromTriCryptoPool(WBTC, params);

        // 21657103424510020784247 * 1*10^18 / 10^18
        // 21657103424510020784247
        // $21,657.10342451
        assertEq(price, priceOracleWbtcUsdt.mulDiv(USDT_PRICE, 1e18));
    }

    function test_getTokenPriceFromTriCryptoPool_coinThree() public {
        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromTriCryptoPool(WETH, params);

        // 1530492432190963892950 * 1*10^18 / 10^18
        // 1530492432190963892950
        // $1,530.492432191
        assertEq(price, priceOracleWethUsdt.mulDiv(USDT_PRICE, 1e18));
    }

    function test_getTokenPriceFromTriCryptoPool_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockPrice.setPriceDecimals(priceDecimals);

        uint256 usdtPrice = USDT_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS);
        mockPrice.setPrice(USDT, usdtPrice);

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromTriCryptoPool(WBTC, params);

        // Will be normalised to price decimals
        assertEq(price, priceOracleWbtcUsdt.mulDiv(usdtPrice, 1e18));
    }

    function test_getTokenPriceFromTriCryptoPool_revertsOnPriceDecimalsMaximum() public {
        mockPrice.setPriceDecimals(100);
        mockPrice.setPrice(USDT, (USDT_PRICE * 1e21) / 1e18);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PRICEDecimalsOutOfBounds.selector,
            address(mockPrice)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTriCryptoPool(WBTC, params);
    }

    function test_getTokenPriceFromTriCryptoPool_revertsOnUnknownToken() public {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        expectRevert_address(CurvePoolTokenPrice.Curve_LookupTokenNotFound.selector, DAI);

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTriCryptoPool(DAI, params);
    }

    function test_getTokenPriceFromTriCryptoPool_otherPriceZero() public {
        // Base token price is defined
        // No price for a different token
        mockPrice.setPrice(WETH, 0);

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromTriCryptoPool(WBTC, params);

        assertEq(price, priceOracleWbtcUsdt);
    }

    function test_getTokenPriceFromTriCryptoPool_revertsOnBasePriceZero() public {
        // The base token (index = 0) has no price defined, which prevents a lookup
        mockPrice.setPrice(USDT, 0);
        mockPrice.setPrice(WETH, 1500 * 1e18);

        expectRevert_address(CurvePoolTokenPrice.Curve_PriceNotFound.selector, address(mockPool));

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTriCryptoPool(WBTC, params);
    }

    function test_getTokenPriceFromTriCryptoPool_revertsOnCoinOneZero() public {
        mockPool.setCoinsThree(address(0), WBTC, WETH);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTriCryptoPool(WBTC, params);
    }

    function test_getTokenPriceFromTriCryptoPool_revertsOnCoinTwoZero() public {
        mockPool.setCoinsThree(USDT, address(0), WETH);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTriCryptoPool(WETH, params);
    }

    function test_getTokenPriceFromTriCryptoPool_inverseOrientation() public {
        uint256 wbtcPrice = 20000 * 1e18;
        mockPrice.setPrice(WBTC, wbtcPrice);

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromTriCryptoPool(USDT, params);

        // price_oracle = 21657103424510020784247 = 21,657.10342451
        // 1 WBTC = 21,657.10342451 USDT
        // 1 WBTC = $20000
        // 1 USDT = 1 / 21,657.10342451 = 0.0000461742 WBTC
        // 1 USDT = 0.0000461742 * $20000 = $0.92
        assertApproxEqAbs(price, ((1e18 * wbtcPrice) / priceOracleWbtcUsdt), 1e5);
    }

    function test_getTokenPriceFromTriCryptoPool_revertsOnPriceOracleZero() public {
        uint256[] memory price_oracle = new uint256[](2);
        price_oracle[0] = 0;
        price_oracle[1] = 0;
        mockPool.set_price_oracle(price_oracle);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolPriceOracleInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTriCryptoPool(WETH, params);
    }

    function test_getTokenPriceFromTriCryptoPool_inverseOrientation_revertsOnPriceOracleZero()
        public
    {
        uint256 wbtcPrice = 20000 * 1e18;
        mockPrice.setPrice(WBTC, wbtcPrice);

        uint256[] memory price_oracle = new uint256[](2);
        price_oracle[0] = 0;
        price_oracle[1] = 0;
        mockPool.set_price_oracle(price_oracle);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolPriceOracleInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolTriCryptoParams(mockPool);
        curveSubmodule.getTokenPriceFromTriCryptoPool(USDT, params);
    }

    function test_getTokenPriceFromTriCryptoPool_revertsOnIncorrectPoolType() public {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        MockCurvePool mockStablePool = new MockCurvePool();
        mockPrice.setPrice(DAI, 10 ** PRICE_DECIMALS);
        mockStablePool.setCoinsThree(DAI, USDC, WETH);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTypeNotTriCrypto.selector,
            address(mockStablePool)
        );

        bytes memory params = abi.encode(mockStablePool);
        curveSubmodule.getTokenPriceFromTriCryptoPool(WETH, params);
    }
}
