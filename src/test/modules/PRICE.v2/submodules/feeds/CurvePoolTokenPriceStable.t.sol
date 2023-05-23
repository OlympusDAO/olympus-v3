// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockCurvePool} from "test/mocks/MockCurvePool.sol";
import {FullMath} from "libraries/FullMath.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {CurvePoolTokenPrice, ICurvePool} from "modules/PRICE/submodules/feeds/CurvePoolTokenPrice.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";
import {MockBalancerPool} from "test/mocks/MockBalancerPool.sol";

contract CurvePoolTokenPriceStableTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for CurvePoolTokenPrice;

    MockPrice internal mockPrice;
    MockCurvePool internal mockPool;

    CurvePoolTokenPrice internal curveSubmodule;

    uint8 internal constant PRICE_DECIMALS = 18;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint8 internal constant DAI_DECIMALS = 18;
    uint8 internal constant USDC_DECIMALS = 6;
    uint8 internal constant USDT_DECIMALS = 6;

    uint256 internal constant DAI_PRICE = 1e18;
    uint256 internal constant USDC_PRICE = 1e18;
    uint256 internal constant USDT_PRICE = 1e18;

    uint256 internal constant VIRTUAL_PRICE = 1023911043689987591;
    uint8 internal constant POOL_DECIMALS = 18;

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
            mockPool = new MockCurvePool();
            // Values taken from the live 3Pool: https://etherscan.io/address/0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7
            mockPool.setVirtualPrice(VIRTUAL_PRICE);

            mockPool.setCoinsThree(DAI, USDC, USDT);
        }

        // Mock prices from PRICE
        {
            mockPrice.setPrice(DAI, DAI_PRICE);
            mockPrice.setPrice(USDC, USDC_PRICE);
            mockPrice.setPrice(USDT, USDT_PRICE);
        }

        // Mock ERC20 decimals
        {
            mockERC20Decimals(DAI, DAI_DECIMALS);
            mockERC20Decimals(USDC, USDC_DECIMALS);
            mockERC20Decimals(USDT, USDT_DECIMALS);
        }
    }

    // =========  HELPER METHODS ========= //

    function mockERC20Decimals(address asset_, uint8 decimals_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }

    function encodeCurvePoolParams(ICurvePool pool) internal pure returns (bytes memory params) {
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

    /// @notice Mocks the record for get_dy
    /// @dev get_dy returns the quantity q2 of t2 for the given quantity q1 of t1
    ///
    /// This function handles decimal conversion
    function mockSwap(address t1, address t2, uint256 q2) internal {
        // Convert q2 to the native decimals
        ERC20 t2Contract = ERC20(t2);
        uint256 q2Native = q2.mulDiv(10 ** t2Contract.decimals(), 1e18);

        ERC20 t1Contract = ERC20(t1);
        uint256 t1QuantityNative = 10 ** t1Contract.decimals();

        // Indexes
        address[] memory coins = mockPool.getCoins();
        uint128 t1Index = type(uint128).max;
        uint128 t2Index = type(uint128).max;
        for (uint256 i = 0; i < coins.length; i++) {
            if (coins[i] == t1) {
                t1Index = uint128(i);
            }
            if (coins[i] == t2) {
                t2Index = uint128(i);
            }
        }

        if (t1Index == type(uint128).max || t2Index == type(uint128).max) {
            revert("mockSwap: invalid indexes");
        }

        mockPool.setSwap(t1Index, t2Index, t1QuantityNative, q2Native);
    }

    // ========= STABLE POOL - LP TOKEN PRICE ========= //

    // Notes:
    // - Pool decimals can't be set, so there's no point in testing them

    function test_getPoolTokenPriceFromStablePool_threeCoins() public {
        bytes memory params = encodeCurvePoolParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromStablePool(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(price, VIRTUAL_PRICE);
    }

    function test_getPoolTokenPriceFromStablePool_twoCoins() public {
        // Mock coins
        mockPool.setCoinsTwo(DAI, USDC);

        bytes memory params = encodeCurvePoolParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromStablePool(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(price, VIRTUAL_PRICE);
    }

    function test_getPoolTokenPriceFromStablePool_revertsOnParamsPoolUndefined() public {
        expectRevert_address(CurvePoolTokenPrice.Curve_PoolTypeNotStable.selector, address(0));

        bytes memory params = encodeCurvePoolParams(ICurvePool(address(0)));
        curveSubmodule.getPoolTokenPriceFromStablePool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromStablePool_revertsOnIncorrectPoolType() public {
        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTypeNotStable.selector,
            address(mockNonWeightedPool)
        );

        bytes memory params = abi.encode(mockNonWeightedPool);
        curveSubmodule.getPoolTokenPriceFromStablePool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromStablePool_revertsOnPriceZero() public {
        mockPrice.setPrice(USDC, 0);

        // Passes revert from PRICE as the LP token price cannot be calculated without it
        expectRevert_PriceZero(USDC);

        bytes memory params = encodeCurvePoolParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromStablePool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromStablePool_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        // Mock a PRICE implementation with a fewer number of decimals
        mockPrice.setPrice(DAI, 1 * 10 ** priceDecimals);
        mockPrice.setPrice(USDC, 1 * 10 ** priceDecimals);

        // Mock coins
        mockPool.setCoinsTwo(DAI, USDC);

        bytes memory params = encodeCurvePoolParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromStablePool(
            address(0),
            priceDecimals,
            params
        );

        // Uses outputDecimals_
        assertEq(price, VIRTUAL_PRICE.mulDiv(10 ** priceDecimals, 1e18));
    }

    function test_getPoolTokenPriceFromStablePool_revertsOnPriceDecimalsMaximum() public {
        // Mock a PRICE implementation with a higher number of decimals
        uint8 priceDecimals = MAX_DECIMALS + 1;
        mockPrice.setPrice(DAI, 1e21);
        mockPrice.setPrice(USDC, 1e21);

        expectRevert_uint8(
            CurvePoolTokenPrice.Curve_OutputDecimalsOutOfBounds.selector,
            priceDecimals
        );

        bytes memory params = encodeCurvePoolParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromStablePool(address(0), priceDecimals, params);
    }

    function test_getPoolTokenPriceFromStablePool_revertsOnZeroCoins() public {
        // Mock 0 coins
        address[] memory coins = new address[](0);
        mockPool.setCoins(coins);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromStablePool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromStablePool_threeCoins_minimumPrice() public {
        // Mock a PRICE price slightly lower
        mockPrice.setPrice(USDC, 0.98 * 1e18);

        bytes memory params = encodeCurvePoolParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromStablePool(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(price, VIRTUAL_PRICE.mulDiv(0.98 * 1e18, 1e18));
    }

    function test_getPoolTokenPriceFromStablePool_threeCoins_minimumPriceFuzz(
        uint8 priceDecimals_,
        uint8 priceOne_,
        uint8 priceTwo_,
        uint8 priceThree_
    ) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));
        // 10 ** 2
        uint256 priceOne = bound(priceOne_, 1, 150);
        uint256 priceTwo = bound(priceTwo_, 1, 150);
        uint256 priceThree = bound(priceThree_, 1, 150);

        mockPrice.setPrice(DAI, uint256(priceOne).mulDiv(10 ** priceDecimals, 10 ** 2));
        mockPrice.setPrice(USDC, uint256(priceTwo).mulDiv(10 ** priceDecimals, 10 ** 2));
        mockPrice.setPrice(USDT, uint256(priceThree).mulDiv(10 ** priceDecimals, 10 ** 2));

        uint256 _minimumPriceOne = (priceOne < priceTwo ? priceOne : priceTwo);
        uint256 _minimumPrice = (_minimumPriceOne < priceThree ? _minimumPriceOne : priceThree);
        uint256 minimumPrice = _minimumPrice.mulDiv(10 ** priceDecimals, 10 ** 2);

        bytes memory params = encodeCurvePoolParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromStablePool(
            address(0),
            priceDecimals,
            params
        );

        assertEq(price, VIRTUAL_PRICE.mulDiv(minimumPrice, 10 ** POOL_DECIMALS));
    }

    function test_getPoolTokenPriceFromStablePool_metaPool() public {
        address FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        address THREE_POOL = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;

        // Mock a token paired with a stable pool, forming a metapool
        mockPool.setCoinsTwo(FRAX, THREE_POOL);

        // Mock PRICE prices
        mockPrice.setPrice(FRAX, 10 ** PRICE_DECIMALS);
        mockPrice.setPrice(THREE_POOL, 10 ** PRICE_DECIMALS);

        bytes memory params = encodeCurvePoolParams(mockPool);
        uint256 price = curveSubmodule.getPoolTokenPriceFromStablePool(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(price, VIRTUAL_PRICE);
    }

    function test_getPoolTokenPriceFromStablePool_revertsOnCoinOneZero() public {
        mockPool.setCoinsTwo(address(0), DAI);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromStablePool(address(0), PRICE_DECIMALS, params);
    }

    function test_getPoolTokenPriceFromStablePool_revertsOnCoinTwoZero() public {
        mockPool.setCoinsTwo(DAI, address(0));

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolParams(mockPool);
        curveSubmodule.getPoolTokenPriceFromStablePool(address(0), PRICE_DECIMALS, params);
    }

    // ========= STABLE POOL - TOKEN SPOT PRICE ========= //

    function test_getTokenPriceFromStablePool_coinTwo() public {
        uint256 quantityInDai = 1.01 * 1e18;
        mockSwap(USDC, DAI, quantityInDai);

        bytes memory params = encodeCurvePoolParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromStablePool(USDC, PRICE_DECIMALS, params);

        assertEq(price, quantityInDai.mulDiv(DAI_PRICE, 1e18));
    }

    function test_getTokenPriceFromStablePool_revertsOnParamsPoolUndefined() public {
        uint256 quantityInDai = 1.01 * 1e18;
        mockSwap(USDC, DAI, quantityInDai);

        expectRevert_address(CurvePoolTokenPrice.Curve_PoolTypeNotStable.selector, address(0));

        bytes memory params = encodeCurvePoolParams(ICurvePool(address(0)));
        curveSubmodule.getTokenPriceFromStablePool(USDC, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_revertsOnIncorrectPoolType() public {
        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTypeNotStable.selector,
            address(mockNonWeightedPool)
        );

        bytes memory params = abi.encode(mockNonWeightedPool);
        curveSubmodule.getTokenPriceFromStablePool(USDC, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_coinThree() public {
        uint256 quantityInDai = 1.02 * 1e18;
        mockSwap(USDT, DAI, quantityInDai);

        bytes memory params = encodeCurvePoolParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromStablePool(USDT, PRICE_DECIMALS, params);

        assertEq(price, quantityInDai.mulDiv(DAI_PRICE, 1e18));
    }

    function test_getTokenPriceFromStablePool_coinTwo_depeg() public {
        uint256 quantityInDai = 1.01 * 1e18;
        mockSwap(USDC, DAI, quantityInDai);

        // Price of DAI is not 1
        mockPrice.setPrice(DAI, 0.98 * 1e18);

        bytes memory params = encodeCurvePoolParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromStablePool(USDC, PRICE_DECIMALS, params);

        assertEq(price, quantityInDai.mulDiv(0.98 * 1e18, 1e18));
    }

    function test_getTokenPriceFromStablePool_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, 2, MAX_DECIMALS));

        uint256 quantityInDai = 1.02 * 1e18;
        mockSwap(USDC, DAI, quantityInDai);

        uint256 daiPrice = DAI_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS);
        mockPrice.setPrice(DAI, daiPrice);
        uint256 usdcPrice = USDC_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS);
        mockPrice.setPrice(USDC, usdcPrice);
        uint256 usdtPrice = USDT_PRICE.mulDiv(10 ** priceDecimals, 10 ** PRICE_DECIMALS);
        mockPrice.setPrice(USDT, usdtPrice);

        bytes memory params = encodeCurvePoolParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromStablePool(USDC, priceDecimals, params);

        // Will be normalised to outputDecimals_
        assertEq(price, quantityInDai.mulDiv(daiPrice, 1e18));
    }

    function test_getTokenPriceFromStablePool_unknownToken() public {
        address WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

        expectRevert_address(CurvePoolTokenPrice.Curve_LookupTokenNotFound.selector, WBTC);

        bytes memory params = encodeCurvePoolParams(mockPool);
        curveSubmodule.getTokenPriceFromStablePool(WBTC, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_otherPriceZero() public {
        // Base token price is defined
        // No price for a different token
        mockPrice.setPrice(DAI, 0);

        uint256 quantityInDai = 1.02 * 1e18;
        mockSwap(USDC, USDT, quantityInDai);

        bytes memory params = encodeCurvePoolParams(mockPool);
        uint256 price = curveSubmodule.getTokenPriceFromStablePool(USDC, PRICE_DECIMALS, params);

        assertEq(price, quantityInDai.mulDiv(USDT_PRICE, 1e18));
    }

    function test_getTokenPriceFromStablePool_revertsOnCoinOneZero() public {
        mockPool.setCoinsThree(address(0), USDC, USDT);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolParams(mockPool);
        curveSubmodule.getTokenPriceFromStablePool(USDC, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_coinTwoZero() public {
        mockPool.setCoinsThree(DAI, address(0), USDT);

        expectRevert_address(
            CurvePoolTokenPrice.Curve_PoolTokensInvalid.selector,
            address(mockPool)
        );

        bytes memory params = encodeCurvePoolParams(mockPool);
        curveSubmodule.getTokenPriceFromStablePool(USDC, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_dyZero() public {
        // Don't define any swap behaviours

        expectRevert_address(CurvePoolTokenPrice.Curve_PriceNotFound.selector, address(mockPool));

        bytes memory params = encodeCurvePoolParams(mockPool);
        curveSubmodule.getTokenPriceFromStablePool(USDC, PRICE_DECIMALS, params);
    }
}
