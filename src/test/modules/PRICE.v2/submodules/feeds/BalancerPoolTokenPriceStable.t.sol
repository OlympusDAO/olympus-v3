// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockBalancerPool, MockBalancerStablePool, MockBalancerWeightedPool, MockBalancerComposableStablePool} from "test/mocks/MockBalancerPool.sol";
import {MockBalancerVault} from "test/mocks/MockBalancerVault.sol";
import {FullMath} from "libraries/FullMath.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {BalancerPoolTokenPrice, IStablePool, IVault} from "modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";

contract BalancerPoolTokenPriceStableTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for BalancerPoolTokenPrice;

    MockPrice internal mockPrice;
    MockBalancerVault internal mockBalancerVault;
    MockBalancerStablePool internal mockStablePool;

    BalancerPoolTokenPrice internal balancerSubmodule;

    bytes32 internal constant BALANCER_POOL_ID =
        0x3dd0843a028c86e0b760b1a76929d1c5ef93a2dd000200000000000000000249;
    address internal constant BALANCER_POOL = 0x3dd0843A028C86e0b760b1A76929d1C5Ef93a2dd;
    uint256 internal constant BALANCER_POOL_TOTAL_SUPPLY = 1166445846909257605048176;
    uint8 internal constant BALANCER_POOL_DECIMALS = 18;

    uint256 internal constant INVARIANT = 1203974641585710664986665;
    uint256 internal constant AMP_FACTOR = 50000;

    address internal constant B_80BAL_20WETH = 0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56;
    address internal constant AURA_BAL = 0x616e8BfA43F920657B3497DBf40D6b1A02D4608d;

    uint8 internal constant B_80BAL_20WETH_DECIMALS = 18;
    uint8 internal constant AURA_BAL_DECIMALS = 18;

    uint256 internal constant B_80BAL_20WETH_BALANCE = 507713528624138828935656;
    uint256 internal constant AURA_BAL_BALANCE = 696558540009160592774860;

    uint256 internal constant B_80BAL_20WETH_BALANCE_PRICE = 16.71 * 1e18;
    uint256 internal constant B_80BAL_20WETH_BALANCE_PRICE_EXPECTED = 16710001252344598708;
    uint256 internal constant AURA_BAL_PRICE_EXPECTED = 16602528871962134544;

    uint256 internal constant BALANCER_POOL_RATE = 1032914638684593940;

    uint8 internal constant PRICE_DECIMALS = 18;

    uint8 internal constant MIN_DECIMALS = 6;
    uint8 internal constant MAX_DECIMALS = 50;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Set up the mock balancer vault
        {
            mockBalancerVault = new MockBalancerVault();
            setTokensTwo(mockBalancerVault, B_80BAL_20WETH, AURA_BAL);
            setBalancesTwo(mockBalancerVault, B_80BAL_20WETH_BALANCE, AURA_BAL_BALANCE);
        }

        // Set up the mock balancer pool
        {
            mockStablePool = new MockBalancerStablePool();
            mockStablePool.setDecimals(BALANCER_POOL_DECIMALS);
            mockStablePool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
            mockStablePool.setPoolId(BALANCER_POOL_ID);
            mockStablePool.setLastInvariant(INVARIANT, AMP_FACTOR);
            mockStablePool.setRate(BALANCER_POOL_RATE);
            setScalingFactorsTwo(mockStablePool, 1000000000000000000, 1000000000000000000);
        }

        // Set up the Balancer submodule
        {
            Kernel kernel = new Kernel();
            mockPrice = new MockPrice(kernel, uint8(18), uint32(8 hours));
            mockPrice.setPriceDecimals(PRICE_DECIMALS);
            mockPrice.setTimestamp(uint48(block.timestamp));
            balancerSubmodule = new BalancerPoolTokenPrice(mockPrice, mockBalancerVault);
        }

        // Mock prices from PRICE
        {
            mockAssetPrice(B_80BAL_20WETH, B_80BAL_20WETH_BALANCE_PRICE);
        }

        // Mock ERC20 decimals
        {
            mockERC20Decimals(B_80BAL_20WETH, B_80BAL_20WETH_DECIMALS);
            mockERC20Decimals(AURA_BAL, AURA_BAL_DECIMALS);
        }
    }

    // =========  HELPER METHODS ========= //

    function setTokensTwo(MockBalancerVault vault, address coin1_, address coin2_) internal {
        address[] memory coins = new address[](2);
        coins[0] = coin1_;
        coins[1] = coin2_;
        vault.setTokens(coins);
    }

    function setTokensThree(
        MockBalancerVault vault,
        address coin1_,
        address coin2_,
        address coin3_
    ) internal {
        address[] memory coins = new address[](3);
        coins[0] = coin1_;
        coins[1] = coin2_;
        coins[2] = coin3_;
        vault.setTokens(coins);
    }

    function setBalancesTwo(
        MockBalancerVault vault,
        uint256 balance1_,
        uint256 balance2_
    ) internal {
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance1_;
        balances[1] = balance2_;
        vault.setBalances(balances);
    }

    function setBalancesThree(
        MockBalancerVault vault,
        uint256 balance1_,
        uint256 balance2_,
        uint256 balance3_
    ) internal {
        uint256[] memory balances = new uint256[](3);
        balances[0] = balance1_;
        balances[1] = balance2_;
        balances[2] = balance3_;
        vault.setBalances(balances);
    }

    function setScalingFactorsTwo(
        MockBalancerStablePool pool_,
        uint256 scalingFactor1_,
        uint256 scalingFactor2_
    ) internal {
        uint256[] memory scalingFactors = new uint256[](2);
        scalingFactors[0] = scalingFactor1_;
        scalingFactors[1] = scalingFactor2_;
        pool_.setScalingFactors(scalingFactors);
    }

    function mockERC20Decimals(address asset_, uint8 decimals_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }

    function mockAssetPrice(address asset_, uint256 price_) internal {
        mockPrice.setPrice(asset_, price_);
    }

    function encodeBalancerPoolParams(
        IStablePool pool
    ) internal pure returns (bytes memory params) {
        return abi.encode(pool);
    }

    function expectRevert_asset(bytes4 selector_, address asset_) internal {
        bytes memory err = abi.encodeWithSelector(selector_, asset_);
        vm.expectRevert(err);
    }

    function expectRevert_pool(bytes4 selector_, bytes32 poolId_) internal {
        bytes memory err = abi.encodeWithSelector(selector_, poolId_);
        vm.expectRevert(err);
    }

    function _getBalancerPoolTokenPrice(uint8 priceDecimals) internal view returns (uint256) {
        uint256 rate = BALANCER_POOL_RATE.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS); // outputDecimals_
        uint256 baseTokenPrice = (
            B_80BAL_20WETH_BALANCE_PRICE_EXPECTED < AURA_BAL_PRICE_EXPECTED
                ? B_80BAL_20WETH_BALANCE_PRICE_EXPECTED
                : AURA_BAL_PRICE_EXPECTED
        ).mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS); // outputDecimals_

        return rate.mulDiv(baseTokenPrice, 10 ** priceDecimals);
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

    // ========= TOKEN PRICE ========= //

    function test_getTokenPriceFromStablePool_success() public {
        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        uint256 price = balancerSubmodule.getTokenPriceFromStablePool(
            AURA_BAL,
            PRICE_DECIMALS,
            params
        );

        // Expected price, given the inputs
        assertEq(price, AURA_BAL_PRICE_EXPECTED);
    }

    function test_getTokenPriceFromStablePool_revertsOnParamsPoolUndefined() public {
        expectRevert_pool(BalancerPoolTokenPrice.Balancer_PoolTypeNotStable.selector, bytes32(0));

        bytes memory params = encodeBalancerPoolParams(IStablePool(address(0)));
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockAssetPrice(
            B_80BAL_20WETH,
            B_80BAL_20WETH_BALANCE_PRICE.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        uint256 price = balancerSubmodule.getTokenPriceFromStablePool(
            AURA_BAL,
            priceDecimals,
            params
        );

        // Will be normalised to outputDecimals_
        uint8 decimalDiff = priceDecimals > 18 ? priceDecimals - 18 : 18 - priceDecimals + 1;
        assertApproxEqAbs(
            price,
            AURA_BAL_PRICE_EXPECTED.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS),
            10 ** decimalDiff
        );
    }

    function test_getTokenPriceFromStablePool_priceDecimalsMaximum() public {
        uint8 priceDecimals = MAX_DECIMALS + 1;
        mockAssetPrice(B_80BAL_20WETH, (B_80BAL_20WETH_BALANCE_PRICE * 1e21) / 1e18);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_OutputDecimalsOutOfBounds.selector,
            priceDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, priceDecimals, params);
    }

    /**
     * The invariant is tied to the balances (and number of decimals), so we can't test
     * for different token decimal or pool decimal values.
     */
    // function test_getTokenPriceFromStablePool_tokenDecimalsFuzz(uint8 token0Decimals_, uint8 token1Decimals_) public {
    //     uint8 token0Decimals = uint8(bound(token0Decimals_, MIN_DECIMALS, MAX_DECIMALS));
    //     uint8 token1Decimals = uint8(bound(token1Decimals_, MIN_DECIMALS, MAX_DECIMALS));

    //     mockERC20Decimals(B_80BAL_20WETH, token0Decimals);
    //     mockERC20Decimals(AURA_BAL, token1Decimals);
    //     setBalancesTwo(mockBalancerVault, B_80BAL_20WETH_BALANCE.mulDiv(token0Decimals, 10 ** B_80BAL_20WETH_DECIMALS), AURA_BAL_BALANCE.mulDiv(token1Decimals, 10 ** AURA_BAL_DECIMALS));
    //
    //     bytes memory params = encodeBalancerPoolParams(mockStablePool);
    //     uint256 price = balancerSubmodule.getTokenPriceFromStablePool(
    //         AURA_BAL,
    //         PRICE_DECIMALS,
    //         params
    //     );

    //     assertTrue(success);
    //     // Will be normalised to outputDecimals_
    //     assertApproxEqAbs(price, AURA_BAL_PRICE_EXPECTED, 0);
    // }
    //
    // function test_getTokenPriceFromStablePool_tokenDecimalsMaximum() public {
    //     mockERC20Decimals(B_80BAL_20WETH, MAX_DECIMALS + 1);
    //     setBalancesTwo(mockBalancerVault, B_80BAL_20WETH_BALANCE.mulDiv(10 ** (MAX_DECIMALS + 1), 10 ** B_80BAL_20WETH_DECIMALS), AURA_BAL_BALANCE);
    //
    //     bytes memory params = encodeBalancerPoolParams(mockStablePool);
    //     uint256 price = balancerSubmodule.getTokenPriceFromStablePool(
    //         AURA_BAL,
    //         PRICE_DECIMALS,
    //         params
    //     );

    //     assertFalse(success);
    //     assertEq(0, price);
    // }

    function test_getTokenPriceFromStablePool_unknownToken() public {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_LookupTokenNotFound.selector,
            BALANCER_POOL_ID,
            DAI
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(DAI, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_noPrice() public {
        // PRICE not configured to handle the asset, returns 0
        mockAssetPrice(B_80BAL_20WETH, 0);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PriceNotFound.selector,
            BALANCER_POOL_ID,
            AURA_BAL
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_coinOneZero() public {
        setTokensTwo(mockBalancerVault, address(0), AURA_BAL);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenInvalid.selector,
            BALANCER_POOL_ID,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_coinTwoZero() public {
        setTokensTwo(mockBalancerVault, B_80BAL_20WETH, address(0));

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenInvalid.selector,
            BALANCER_POOL_ID,
            1,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_inverse() public {
        mockAssetPrice(B_80BAL_20WETH, 0);
        mockAssetPrice(AURA_BAL, AURA_BAL_PRICE_EXPECTED);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        uint256 price = balancerSubmodule.getTokenPriceFromStablePool(
            B_80BAL_20WETH,
            PRICE_DECIMALS,
            params
        );

        assertEq(price, B_80BAL_20WETH_BALANCE_PRICE_EXPECTED);
    }

    function test_getTokenPriceFromStablePool_twoTokens_oneBalances() public {
        uint256[] memory balances = new uint256[](1);
        balances[0] = B_80BAL_20WETH_BALANCE;
        mockBalancerVault.setBalances(balances);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenBalanceMismatch.selector,
            BALANCER_POOL_ID,
            2,
            1
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_oneTokens_twoBalances() public {
        // mockAssetPrice(B_80BAL_20WETH, 0);
        mockAssetPrice(AURA_BAL, AURA_BAL_PRICE_EXPECTED);

        address[] memory tokens = new address[](1);
        tokens[0] = B_80BAL_20WETH;
        mockBalancerVault.setTokens(tokens);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenBalanceMismatch.selector,
            BALANCER_POOL_ID,
            1,
            2
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(B_80BAL_20WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_weightedPoolType() public {
        // Set up a weighted pool
        MockBalancerWeightedPool mockWeightedPool = new MockBalancerWeightedPool();
        mockWeightedPool.setDecimals(BALANCER_POOL_DECIMALS);
        mockWeightedPool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
        mockWeightedPool.setPoolId(BALANCER_POOL_ID);

        // Will fail as the pool does not have the supported function
        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTypeNotStable.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = abi.encode(mockWeightedPool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromStablePool_composableStablePoolType() public {
        // Set up a composable stable pool
        MockBalancerComposableStablePool mockComposablePool = new MockBalancerComposableStablePool();
        mockComposablePool.setDecimals(BALANCER_POOL_DECIMALS);
        mockComposablePool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
        mockComposablePool.setPoolId(BALANCER_POOL_ID);
        mockComposablePool.setRate(BALANCER_POOL_RATE);
        mockComposablePool.setActualSupply(BALANCER_POOL_TOTAL_SUPPLY / 2);

        // Will fail as the pool does not have the supported function
        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTypeNotStable.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = abi.encode(mockComposablePool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, PRICE_DECIMALS, params);
    }

    /// @dev    Tests for issue 3.1 identified in hickuphh3's audit
    function test_getTokenPriceFromStablePool_scalingFactor() public {
        address dola = 0x865377367054516e17014CcdED1e7d814EDC9ce4;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        // Set up a pool for DOLA-USDC, which has a scaling factor
        // Values are taken from the live DOLA-USDC pool: https://etherscan.io/address/0xBA12222222228d8Ba445958a75a0704d566BF2C8#readContract
        MockBalancerStablePool mockDolaUsdcPool = new MockBalancerStablePool();
        mockDolaUsdcPool.setDecimals(BALANCER_POOL_DECIMALS);
        mockDolaUsdcPool.setTotalSupply(3262924705777927304170384);
        mockDolaUsdcPool.setPoolId(
            0xff4ce5aaab5a627bf82f4a571ab1ce94aa365ea6000200000000000000000426
        );
        mockDolaUsdcPool.setLastInvariant(3272947203169998812276392, 200000);
        mockDolaUsdcPool.setRate(1003083263104177887);
        setScalingFactorsTwo(
            mockDolaUsdcPool,
            1000000000000000000,
            1000000000000000000000000000000
        );

        setTokensTwo(mockBalancerVault, dola, usdc);
        setBalancesTwo(mockBalancerVault, 1872102650769666439105823, 1401055486359);

        mockERC20Decimals(usdc, 6);
        mockERC20Decimals(dola, 18);

        bytes memory params = encodeBalancerPoolParams(mockDolaUsdcPool);

        // Look up the price of DOLA
        uint256 expectedPriceDola = 998508498121509280; // $0.9985 reported on CoinGecko at the time of writing
        mockAssetPrice(usdc, 1e18);
        uint256 priceDola = balancerSubmodule.getTokenPriceFromStablePool(
            dola,
            PRICE_DECIMALS,
            params
        );
        _assertEqTruncated(priceDola, 18, expectedPriceDola, 18, 6, 0);

        // Look up the price of USDC
        mockAssetPrice(dola, expectedPriceDola);
        uint256 priceUsdc = balancerSubmodule.getTokenPriceFromStablePool(
            usdc,
            PRICE_DECIMALS,
            params
        );
        _assertEqTruncated(priceUsdc, 18, 1e18, 18, 6, 0);
    }

    function test_getTokenPriceFromStablePool_scalingFactor_priceDecimalsFuzz(
        uint8 priceDecimals_
    ) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        address dola = 0x865377367054516e17014CcdED1e7d814EDC9ce4;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        // Set up a pool for DOLA-USDC, which has a scaling factor
        // Values are taken from the live DOLA-USDC pool: https://etherscan.io/address/0xBA12222222228d8Ba445958a75a0704d566BF2C8#readContract
        MockBalancerStablePool mockDolaUsdcPool = new MockBalancerStablePool();
        mockDolaUsdcPool.setDecimals(BALANCER_POOL_DECIMALS);
        mockDolaUsdcPool.setTotalSupply(3262924705777927304170384);
        mockDolaUsdcPool.setPoolId(
            0xff4ce5aaab5a627bf82f4a571ab1ce94aa365ea6000200000000000000000426
        );
        mockDolaUsdcPool.setLastInvariant(3272947203169998812276392, 200000);
        mockDolaUsdcPool.setRate(1003083263104177887);
        setScalingFactorsTwo(
            mockDolaUsdcPool,
            1000000000000000000,
            1000000000000000000000000000000
        );

        setTokensTwo(mockBalancerVault, dola, usdc);
        setBalancesTwo(mockBalancerVault, 1872102650769666439105823, 1401055486359);

        mockERC20Decimals(usdc, 6);
        mockERC20Decimals(dola, 18);

        bytes memory params = encodeBalancerPoolParams(mockDolaUsdcPool);

        // Look up the price of DOLA
        uint256 expectedPriceDola = 998508498121509280; // $0.9985 reported on CoinGecko at the time of writing
        mockAssetPrice(usdc, 1 * 10 ** priceDecimals);
        uint256 priceDola = balancerSubmodule.getTokenPriceFromStablePool(
            dola,
            priceDecimals,
            params
        );
        _assertEqTruncated(priceDola, priceDecimals, expectedPriceDola, 18, 4, 50); // At low price decimals, it is rather imprecise. Truncate to 4 decimal places with a modest delta.

        // Look up the price of USDC
        mockAssetPrice(dola, expectedPriceDola.mulDiv(10 ** priceDecimals, 1e18));
        uint256 priceUsdc = balancerSubmodule.getTokenPriceFromStablePool(
            usdc,
            priceDecimals,
            params
        );
        _assertEqTruncated(priceUsdc, priceDecimals, 1e18, 18, 6, 0); // At low price decimals, it is rather imprecise. Truncate to 6 decimal places with a modest delta.
    }

    // ========= POOL TOKEN PRICE ========= //

    function setUpStablePoolTokenPrice() internal {
        mockAssetPrice(AURA_BAL, AURA_BAL_PRICE_EXPECTED);
        mockAssetPrice(B_80BAL_20WETH, B_80BAL_20WETH_BALANCE_PRICE_EXPECTED);
    }

    function test_getStablePoolTokenPrice_revertsOnParamsPoolUndefined() public {
        setUpStablePoolTokenPrice();

        expectRevert_pool(BalancerPoolTokenPrice.Balancer_PoolTypeNotStable.selector, bytes32(0));

        bytes memory params = encodeBalancerPoolParams(IStablePool(address(0)));
        balancerSubmodule.getTokenPriceFromStablePool(address(0), PRICE_DECIMALS, params);
    }

    function test_getStablePoolTokenPrice_baseTokenPriceZero() public {
        setUpStablePoolTokenPrice();

        mockAssetPrice(B_80BAL_20WETH, 0);

        // A revert in the base token price will be passed up, as that prevents calculation of the pool token price
        expectRevert_asset(PRICEv2.PRICE_PriceZero.selector, B_80BAL_20WETH);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getStablePoolTokenPrice_rateZero() public {
        setUpStablePoolTokenPrice();

        mockStablePool.setRate(0);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolStableRateInvalid.selector,
            BALANCER_POOL_ID,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getStablePoolTokenPrice_poolTokenDecimalsFuzz(uint8 poolDecimals_) public {
        uint8 poolDecimals = uint8(bound(poolDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        setUpStablePoolTokenPrice();

        mockStablePool.setDecimals(poolDecimals);
        mockStablePool.setTotalSupply(
            BALANCER_POOL_TOTAL_SUPPLY.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );
        mockStablePool.setRate(
            BALANCER_POOL_RATE.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        uint256 price = balancerSubmodule.getStablePoolTokenPrice(
            address(0),
            PRICE_DECIMALS,
            params
        );

        uint8 decimalDiff = poolDecimals > 18 ? poolDecimals - 18 : 18 - poolDecimals + 2;
        assertApproxEqAbs(price, _getBalancerPoolTokenPrice(18), 10 ** decimalDiff);
    }

    function test_getStablePoolTokenPrice_poolTokenDecimalsMaximum() public {
        setUpStablePoolTokenPrice();

        uint8 poolDecimals = 100;
        mockStablePool.setDecimals(poolDecimals);
        mockStablePool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolDecimalsOutOfBounds.selector,
            BALANCER_POOL_ID,
            poolDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getStablePoolTokenPrice_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        // Mock a PRICE implementation with a higher number of decimals
        mockAssetPrice(
            B_80BAL_20WETH,
            B_80BAL_20WETH_BALANCE_PRICE_EXPECTED.mulDiv(
                10 ** priceDecimals,
                10 ** BALANCER_POOL_DECIMALS
            )
        );
        mockAssetPrice(
            AURA_BAL,
            AURA_BAL_PRICE_EXPECTED.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        uint256 price = balancerSubmodule.getStablePoolTokenPrice(
            address(0),
            priceDecimals,
            params
        );

        // Uses outputDecimals_ parameter
        uint8 decimalDiff = priceDecimals > 18 ? priceDecimals - 18 : 18 - priceDecimals;
        assertApproxEqAbs(price, _getBalancerPoolTokenPrice(priceDecimals), 10 ** decimalDiff);
    }

    function test_getStablePoolTokenPrice_priceDecimalsMaximum() public {
        uint8 priceDecimals = MAX_DECIMALS + 1;
        setUpStablePoolTokenPrice();

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_OutputDecimalsOutOfBounds.selector,
            priceDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(address(0), priceDecimals, params);
    }

    function test_getStablePoolTokenPrice_fuzz(uint8 poolDecimals_, uint8 priceDecimals_) public {
        uint8 poolDecimals = uint8(bound(poolDecimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockAssetPrice(
            B_80BAL_20WETH,
            B_80BAL_20WETH_BALANCE_PRICE_EXPECTED.mulDiv(
                10 ** priceDecimals,
                10 ** BALANCER_POOL_DECIMALS
            )
        );
        mockAssetPrice(
            AURA_BAL,
            AURA_BAL_PRICE_EXPECTED.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );

        mockStablePool.setDecimals(poolDecimals);
        mockStablePool.setTotalSupply(
            BALANCER_POOL_TOTAL_SUPPLY.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );
        mockStablePool.setRate(
            BALANCER_POOL_RATE.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        uint256 price = balancerSubmodule.getStablePoolTokenPrice(
            address(0),
            priceDecimals,
            params
        );

        _assertEqTruncated(
            _getBalancerPoolTokenPrice(priceDecimals),
            priceDecimals,
            price,
            priceDecimals,
            2,
            1
        );
    }

    function test_getStablePoolTokenPrice_zeroCoins() public {
        setUpStablePoolTokenPrice();

        // Mock 0 coins
        address[] memory coins = new address[](0);
        mockBalancerVault.setTokens(coins);

        expectRevert_pool(BalancerPoolTokenPrice.Balancer_PoolValueZero.selector, BALANCER_POOL_ID);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getStablePoolTokenPrice_coinOneAddressZero() public {
        setUpStablePoolTokenPrice();

        setTokensTwo(mockBalancerVault, address(0), AURA_BAL);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenInvalid.selector,
            BALANCER_POOL_ID,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getStablePoolTokenPrice_weightedPoolType() public {
        setUpStablePoolTokenPrice();

        // Set up a weighted pool
        MockBalancerWeightedPool mockWeightedPool = new MockBalancerWeightedPool();
        mockWeightedPool.setDecimals(BALANCER_POOL_DECIMALS);
        mockWeightedPool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
        mockWeightedPool.setPoolId(BALANCER_POOL_ID);

        // Will fail as the pool does not have the supported function
        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTypeNotStable.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = abi.encode(mockWeightedPool);
        balancerSubmodule.getStablePoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getStablePoolTokenPrice_composableStablePoolType() public {
        setUpStablePoolTokenPrice();

        // Set up a composable stable pool
        MockBalancerComposableStablePool mockComposablePool = new MockBalancerComposableStablePool();
        mockComposablePool.setDecimals(BALANCER_POOL_DECIMALS);
        mockComposablePool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
        mockComposablePool.setPoolId(BALANCER_POOL_ID);
        mockComposablePool.setRate(BALANCER_POOL_RATE);
        mockComposablePool.setActualSupply(BALANCER_POOL_TOTAL_SUPPLY / 2);

        // Will fail as the pool does not have the supported function
        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTypeNotStable.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = abi.encode(mockComposablePool);
        balancerSubmodule.getStablePoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getStablePoolTokenPrice_threeTokens() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 wethBalance = 50000 * 1e18; // 1 ETH = 10 * 80BAL-20WETH

        // Set asset prices
        setUpStablePoolTokenPrice();
        mockAssetPrice(weth, 1700e18);

        // Set up a pool with three tokens
        MockBalancerStablePool mockPoolThree = new MockBalancerStablePool();
        mockPoolThree.setDecimals(BALANCER_POOL_DECIMALS);
        mockPoolThree.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
        mockPoolThree.setPoolId(BALANCER_POOL_ID);
        mockPoolThree.setLastInvariant(INVARIANT, AMP_FACTOR);
        mockPoolThree.setRate(BALANCER_POOL_RATE);
        setTokensThree(mockBalancerVault, B_80BAL_20WETH, AURA_BAL, weth);
        setBalancesThree(mockBalancerVault, B_80BAL_20WETH_BALANCE, AURA_BAL_BALANCE, wethBalance);

        // Check the price
        bytes memory params = encodeBalancerPoolParams(mockPoolThree);
        uint256 price = balancerSubmodule.getStablePoolTokenPrice(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(price, _getBalancerPoolTokenPrice(PRICE_DECIMALS));
    }

    function test_getStablePoolTokenPrice_threeTokens_minimumPriceFuzz(
        uint8 priceDecimals_,
        uint8 priceOne_,
        uint8 priceTwo_,
        uint8 priceThree_
    ) public {
        // Set up bounds
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint256 priceOne = bound(priceOne_, 1, 150);
        uint256 priceTwo = bound(priceTwo_, 1, 150);
        uint256 priceThree = bound(priceThree_, 1, 150);

        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 wethBalance = 50000 * 1e18;

        // Determine the minimum price
        uint256 _minimumPriceOne = (priceOne < priceTwo ? priceOne : priceTwo);
        uint256 _minimumPrice = (_minimumPriceOne < priceThree ? _minimumPriceOne : priceThree);
        uint256 minimumPrice = _minimumPrice.mulDiv(10 ** priceDecimals, 10 ** 2);

        // Set asset prices
        mockPrice.setPrice(B_80BAL_20WETH, uint256(priceOne).mulDiv(10 ** priceDecimals, 10 ** 2));
        mockPrice.setPrice(AURA_BAL, uint256(priceTwo).mulDiv(10 ** priceDecimals, 10 ** 2));
        mockPrice.setPrice(weth, uint256(priceThree).mulDiv(10 ** priceDecimals, 10 ** 2));

        // Set up a pool with three tokens
        MockBalancerStablePool mockPoolThree = new MockBalancerStablePool();
        mockPoolThree.setDecimals(BALANCER_POOL_DECIMALS);
        mockPoolThree.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
        mockPoolThree.setPoolId(BALANCER_POOL_ID);
        mockPoolThree.setLastInvariant(INVARIANT, AMP_FACTOR);
        mockPoolThree.setRate(BALANCER_POOL_RATE);
        setTokensThree(mockBalancerVault, B_80BAL_20WETH, AURA_BAL, weth);
        setBalancesThree(mockBalancerVault, B_80BAL_20WETH_BALANCE, AURA_BAL_BALANCE, wethBalance);

        // Check the price
        bytes memory params = encodeBalancerPoolParams(mockPoolThree);
        uint256 price = balancerSubmodule.getStablePoolTokenPrice(
            address(0),
            priceDecimals,
            params
        );

        assertEq(price, BALANCER_POOL_RATE.mulDiv(minimumPrice, 10 ** BALANCER_POOL_DECIMALS));
    }
}
