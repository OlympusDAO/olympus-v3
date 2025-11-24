// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockBalancerPool, MockBalancerWeightedPool} from "test/mocks/MockBalancerPool.sol";
import {MockBalancerVault} from "test/mocks/MockBalancerVault.sol";
import {FullMath} from "libraries/FullMath.sol";
import {LogExpMath} from "libraries/Balancer/math/LogExpMath.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {BalancerPoolTokenPrice, IWeightedPool, IVault} from "modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";

contract BalancerPoolTokenPriceWeightedTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for BalancerPoolTokenPrice;

    MockPrice internal mockPrice;
    MockBalancerVault internal mockBalancerVault;
    MockBalancerWeightedPool internal mockWeightedPool;

    BalancerPoolTokenPrice internal balancerSubmodule;

    bytes32 internal constant BALANCER_POOL_ID =
        0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019;
    address internal constant BALANCER_POOL = 0x96646936b91d6B9D7D0c47C496AfBF3D6ec7B6f8;
    uint256 internal constant BALANCER_POOL_TOTAL_SUPPLY = 44828046497101022591963;
    uint8 internal constant BALANCER_POOL_DECIMALS = 18;

    uint8 internal constant PRICE_DECIMALS = 18;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint8 internal constant USDC_DECIMALS = 6;
    uint8 internal constant WETH_DECIMALS = 18;

    uint256 internal constant USDC_WEIGHT = 500000000000000000;
    uint256 internal constant WETH_WEIGHT = 500000000000000000;

    uint256 internal constant BALANCER_POOL_INVARIANT = 25432168041089078866395;

    uint256 internal constant USDC_BALANCE = 1112351166021;
    uint256 internal constant WETH_BALANCE = 581466708560997532338;

    uint256 internal constant USDC_PRICE = 1 * 1e18;
    uint256 internal constant WETH_PRICE = 1_917.25 * 1e18;

    // ((base reserves / base weight) / (destination reserves / destination weight)) * base rate
    // = 1660.2643102434 * 10^18
    uint256 internal constant WETH_RATE =
        (((USDC_BALANCE * 1e12 * 1e18) / USDC_WEIGHT) * USDC_PRICE) /
            ((WETH_BALANCE * 1e18) / WETH_WEIGHT);
    uint256 internal constant USDC_RATE =
        (((WETH_BALANCE * 1e18) / WETH_WEIGHT) * WETH_PRICE) /
            ((USDC_BALANCE * 1e12 * 1e18) / USDC_WEIGHT);

    uint8 internal constant MIN_DECIMALS = 6;
    uint8 internal constant MAX_DECIMALS = 50;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Set up the mock balancer vault
        {
            mockBalancerVault = new MockBalancerVault();
            setTokensTwo(mockBalancerVault, USDC, WETH);
            setBalancesTwo(mockBalancerVault, USDC_BALANCE, WETH_BALANCE);
        }

        // Set up the mock balancer pool
        {
            mockWeightedPool = new MockBalancerWeightedPool();
            mockWeightedPool.setDecimals(BALANCER_POOL_DECIMALS);
            mockWeightedPool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
            mockWeightedPool.setPoolId(BALANCER_POOL_ID);
            mockWeightedPool.setInvariant(BALANCER_POOL_INVARIANT);
            setNormalizedWeightsTwo(mockWeightedPool, USDC_WEIGHT, WETH_WEIGHT);
        }

        // Set up the Balancer submodule
        {
            Kernel kernel = new Kernel();
            mockPrice = new MockPrice(kernel, uint8(18), uint32(8 hours));
            mockPrice.setTimestamp(uint48(block.timestamp));
            mockPrice.setPriceDecimals(PRICE_DECIMALS);
            balancerSubmodule = new BalancerPoolTokenPrice(mockPrice, mockBalancerVault);
        }

        // Mock prices from PRICE
        {
            mockAssetPrice(USDC, USDC_PRICE);
        }

        // Mock ERC20 decimals
        {
            mockERC20Decimals(USDC, USDC_DECIMALS);
            mockERC20Decimals(WETH, WETH_DECIMALS);
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

    function setNormalizedWeightsTwo(
        MockBalancerWeightedPool pool,
        uint256 weight1_,
        uint256 weight2_
    ) internal {
        uint256[] memory weights = new uint256[](2);
        weights[0] = weight1_;
        weights[1] = weight2_;
        pool.setNormalizedWeights(weights);
    }

    function setNormalizedWeightsThree(
        MockBalancerWeightedPool pool,
        uint256 weight1_,
        uint256 weight2_,
        uint256 weight3_
    ) internal {
        uint256[] memory weights = new uint256[](3);
        weights[0] = weight1_;
        weights[1] = weight2_;
        weights[2] = weight3_;
        pool.setNormalizedWeights(weights);
    }

    function mockERC20Decimals(address asset_, uint8 decimals_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }

    function mockERC20TotalSupply(address asset_, uint256 totalSupply_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("totalSupply()"), abi.encode(totalSupply_));
    }

    function mockAssetPrice(address asset_, uint256 price_) internal {
        mockPrice.setPrice(asset_, price_);
    }

    function encodeBalancerPoolParams(
        IWeightedPool pool
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

    // (25432168041089078866395 * 10^18 / 44828046497101022591963)  * (((1 * 10^18) / 500000000000000000)^0.5)  * (((1917.25 * 10^18) / 500000000000000000)^0.5) = 49,682,442,621,348,655,240.1843998201 = 49.6824426213486552401843998201 * 10^18
    function _getBalancerPoolTokenPrice(uint8 priceDecimals) internal pure returns (uint256) {
        uint256 invariant = (
            BALANCER_POOL_INVARIANT.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS)
        ).mulDiv(
                10 ** priceDecimals,
                BALANCER_POOL_TOTAL_SUPPLY.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS)
            ); // outputDecimals__

        uint256 usdcComponent = LogExpMath.pow(
            USDC_PRICE.mulDiv(10 ** BALANCER_POOL_DECIMALS, USDC_WEIGHT), // Needs to be in terms of 1e18
            USDC_WEIGHT
        ); // 1e18

        uint256 wethComponent = LogExpMath.pow(
            WETH_PRICE.mulDiv(10 ** BALANCER_POOL_DECIMALS, WETH_WEIGHT), // Needs to be in terms of 1e18
            WETH_WEIGHT
        ); // 1e18

        uint256 mult = usdcComponent.mulDiv(wethComponent, 10 ** BALANCER_POOL_DECIMALS); // 1e18

        uint256 result = (invariant).mulDiv(mult, 10 ** BALANCER_POOL_DECIMALS); // outputDecimals_

        return result;
    }

    function _max(uint8 a, uint8 b) public pure returns (uint8) {
        return a > b ? a : b;
    }

    function _min(uint8 a, uint8 b) public pure returns (uint8) {
        return a < b ? a : b;
    }

    // ========= TOKEN PRICE ========= //

    function test_getTokenPriceFromWeightedPool_fuzz(
        uint8 priceDecimals_,
        uint8 poolDecimals_,
        uint8 tokenDecimals_
    ) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint8 poolDecimals = uint8(bound(poolDecimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint8 tokenDecimals = uint8(bound(tokenDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        // outputDecimals_
        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS));

        // pool decimals
        mockWeightedPool.setDecimals(poolDecimals);
        mockWeightedPool.setTotalSupply(
            BALANCER_POOL_TOTAL_SUPPLY.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );
        mockWeightedPool.setInvariant(
            BALANCER_POOL_INVARIANT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );
        setNormalizedWeightsTwo(
            mockWeightedPool,
            USDC_WEIGHT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS),
            WETH_WEIGHT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );

        // token decimals
        mockERC20Decimals(USDC, tokenDecimals);
        setBalancesTwo(
            mockBalancerVault,
            USDC_BALANCE.mulDiv(10 ** tokenDecimals, 10 ** USDC_DECIMALS),
            WETH_BALANCE
        );

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        uint256 price = balancerSubmodule.getTokenPriceFromWeightedPool(
            WETH,
            priceDecimals,
            params
        );

        // Simpler to check that the price before the decimal point is equal
        uint256 truncatedPrice = price.mulDiv(1, 10 ** priceDecimals);
        uint256 truncatedExpectedPrice = WETH_RATE.mulDiv(1, 10 ** BALANCER_POOL_DECIMALS);
        assertEq(truncatedPrice, truncatedExpectedPrice);
    }

    function test_getTokenPriceFromWeightedPool_revertsOnParamsPoolUndefined() public {
        expectRevert_pool(BalancerPoolTokenPrice.Balancer_PoolTypeNotWeighted.selector, bytes32(0));

        bytes memory params = encodeBalancerPoolParams(IWeightedPool(address(0)));
        balancerSubmodule.getTokenPriceFromWeightedPool(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromWeightedPool_priceDecimalsSame() public {
        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        uint256 price = balancerSubmodule.getTokenPriceFromWeightedPool(
            WETH,
            PRICE_DECIMALS,
            params
        );

        // 187339411560870503*1500*10^18 / 10^18
        // 281009117341305754500
        // $281.0091173413
        assertEq(price, WETH_RATE);
    }

    function test_getTokenPriceFromWeightedPool_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS));

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        uint256 price = balancerSubmodule.getTokenPriceFromWeightedPool(
            WETH,
            priceDecimals,
            params
        );

        // Uses outputDecimals__ parameter
        uint8 decimalDiff = priceDecimals > 18 ? priceDecimals - 18 : 18 - priceDecimals;
        assertApproxEqAbs(
            price,
            WETH_RATE.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS),
            10 ** decimalDiff
        );
    }

    function test_getTokenPriceFromWeightedPool_priceDecimalsMaximum() public {
        uint8 priceDecimals = MAX_DECIMALS + 1;
        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** priceDecimals, 1e18));

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_OutputDecimalsOutOfBounds.selector,
            priceDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getTokenPriceFromWeightedPool(WETH, priceDecimals, params);
    }

    function test_getTokenPriceFromWeightedPool_poolDecimalsFuzz(uint8 poolDecimals_) public {
        uint8 poolDecimals = uint8(bound(poolDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockWeightedPool.setDecimals(poolDecimals);
        mockWeightedPool.setTotalSupply(
            BALANCER_POOL_TOTAL_SUPPLY.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );
        mockWeightedPool.setInvariant(
            BALANCER_POOL_INVARIANT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );
        setNormalizedWeightsTwo(
            mockWeightedPool,
            USDC_WEIGHT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS),
            WETH_WEIGHT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        uint256 price = balancerSubmodule.getTokenPriceFromWeightedPool(
            WETH,
            PRICE_DECIMALS,
            params
        );

        assertEq(price, WETH_RATE);
    }

    function test_getTokenPriceFromWeightedPool_poolDecimalsMaximum() public {
        uint8 poolDecimals = MAX_DECIMALS + 1;
        mockWeightedPool.setDecimals(poolDecimals);
        mockWeightedPool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolDecimalsOutOfBounds.selector,
            BALANCER_POOL_ID,
            poolDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getTokenPriceFromWeightedPool(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromWeightedPool_tokenDecimalsFuzz(uint8 tokenDecimals_) public {
        uint8 tokenDecimals = uint8(bound(tokenDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockERC20Decimals(USDC, tokenDecimals);
        setBalancesTwo(
            mockBalancerVault,
            USDC_BALANCE.mulDiv(10 ** tokenDecimals, 10 ** USDC_DECIMALS),
            WETH_BALANCE
        );

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        uint256 price = balancerSubmodule.getTokenPriceFromWeightedPool(
            WETH,
            PRICE_DECIMALS,
            params
        );

        // Will be normalised to outputDecimals_
        assertEq(price, WETH_RATE);
    }

    function test_getTokenPriceFromWeightedPool_tokenDecimalsMaximum() public {
        mockERC20Decimals(USDC, MAX_DECIMALS + 1);
        setBalancesTwo(mockBalancerVault, USDC_BALANCE, WETH_BALANCE);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_AssetDecimalsOutOfBounds.selector,
            USDC,
            MAX_DECIMALS + 1,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getTokenPriceFromWeightedPool(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromWeightedPool_unknownToken() public {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_LookupTokenNotFound.selector,
            BALANCER_POOL_ID,
            DAI
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getTokenPriceFromWeightedPool(DAI, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromWeightedPool_noPrice() public {
        // PRICE not configured to handle the asset, returns 0
        mockAssetPrice(USDC, 0);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PriceNotFound.selector,
            BALANCER_POOL_ID,
            WETH
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getTokenPriceFromWeightedPool(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromWeightedPool_coinOneZero() public {
        setTokensTwo(mockBalancerVault, address(0), WETH);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenInvalid.selector,
            BALANCER_POOL_ID,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getTokenPriceFromWeightedPool(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromWeightedPool_coinTwoZero() public {
        setTokensTwo(mockBalancerVault, WETH, address(0));

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenInvalid.selector,
            BALANCER_POOL_ID,
            1,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getTokenPriceFromWeightedPool(WETH, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromWeightedPool_inverse() public {
        mockAssetPrice(USDC, 0);
        mockAssetPrice(WETH, WETH_PRICE);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        uint256 price = balancerSubmodule.getTokenPriceFromWeightedPool(
            USDC,
            PRICE_DECIMALS,
            params
        );

        assertEq(price, USDC_RATE);
    }

    function test_getTokenPriceFromWeightedPool_threeTokens() public {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        uint256 stablecoinWeight = 500000000000000000 / 2;

        mockERC20Decimals(DAI, 18);

        mockAssetPrice(USDC, 0);
        mockAssetPrice(WETH, WETH_PRICE);
        mockAssetPrice(DAI, 1e18);

        setBalancesThree(mockBalancerVault, USDC_BALANCE / 2, WETH_BALANCE, USDC_BALANCE / 2);
        setTokensThree(mockBalancerVault, USDC, WETH, DAI);
        setNormalizedWeightsThree(
            mockWeightedPool,
            stablecoinWeight,
            WETH_WEIGHT,
            stablecoinWeight
        );

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        uint256 price = balancerSubmodule.getTokenPriceFromWeightedPool(
            USDC,
            PRICE_DECIMALS,
            params
        );

        uint256 usdcRate = (((WETH_BALANCE * 1e18) / WETH_WEIGHT) * WETH_PRICE) /
            (((USDC_BALANCE / 2) * 1e12 * 1e18) / stablecoinWeight);

        assertEq(price, usdcRate);
    }

    function test_getTokenPriceFromWeightedPool_threeTokens_threeBalances_twoWeights() public {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        uint256 stablecoinWeight = 500000000000000000 / 2;

        mockERC20Decimals(DAI, 18);

        mockAssetPrice(USDC, 0);
        mockAssetPrice(WETH, WETH_PRICE);
        mockAssetPrice(DAI, 1e18);

        setBalancesThree(mockBalancerVault, USDC_BALANCE / 2, WETH_BALANCE, USDC_BALANCE / 2);
        setTokensThree(mockBalancerVault, USDC, WETH, DAI);
        setNormalizedWeightsTwo(mockWeightedPool, stablecoinWeight, WETH_WEIGHT);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenBalanceWeightMismatch.selector,
            BALANCER_POOL_ID,
            3,
            3,
            2
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getTokenPriceFromWeightedPool(USDC, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromWeightedPool_threeTokens_twoBalances_threeWeights() public {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        uint256 stablecoinWeight = 500000000000000000 / 2;

        mockERC20Decimals(DAI, 18);

        mockAssetPrice(USDC, 0);
        mockAssetPrice(WETH, WETH_PRICE);
        mockAssetPrice(DAI, 1e18);

        setBalancesTwo(mockBalancerVault, USDC_BALANCE / 2, WETH_BALANCE);
        setTokensThree(mockBalancerVault, USDC, WETH, DAI);
        setNormalizedWeightsThree(
            mockWeightedPool,
            stablecoinWeight,
            WETH_WEIGHT,
            stablecoinWeight
        );

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenBalanceWeightMismatch.selector,
            BALANCER_POOL_ID,
            3,
            2,
            3
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getTokenPriceFromWeightedPool(USDC, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromWeightedPool_twoTokens_threeBalances_threeWeights() public {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        uint256 stablecoinWeight = 500000000000000000 / 2;

        mockERC20Decimals(DAI, 18);

        mockAssetPrice(USDC, 0);
        mockAssetPrice(WETH, WETH_PRICE);
        mockAssetPrice(DAI, 1e18);

        setBalancesThree(mockBalancerVault, USDC_BALANCE / 2, WETH_BALANCE, USDC_BALANCE / 2);
        setTokensTwo(mockBalancerVault, USDC, WETH);
        setNormalizedWeightsThree(
            mockWeightedPool,
            stablecoinWeight,
            WETH_WEIGHT,
            stablecoinWeight
        );

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenBalanceWeightMismatch.selector,
            BALANCER_POOL_ID,
            2,
            3,
            3
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getTokenPriceFromWeightedPool(USDC, PRICE_DECIMALS, params);
    }

    function test_getTokenPriceFromWeightedPool_incorrectPoolType() public {
        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(BALANCER_POOL_DECIMALS);
        mockNonWeightedPool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
        mockNonWeightedPool.setPoolId(BALANCER_POOL_ID);

        // Will fail as the pool does not have the supported function
        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTypeNotWeighted.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = abi.encode(mockNonWeightedPool);
        balancerSubmodule.getTokenPriceFromWeightedPool(WETH, PRICE_DECIMALS, params);
    }

    // ========= POOL TOKEN PRICE ========= //

    function setUpWeightedPoolTokenPrice() internal {
        mockAssetPrice(USDC, USDC_PRICE);
        mockAssetPrice(WETH, WETH_PRICE);
    }

    function test_getWeightedPoolTokenPrice_priceZero() public {
        setUpWeightedPoolTokenPrice();

        mockAssetPrice(USDC, 0);

        // A revert in any of the underlying token prices will be passed up, as that prevents calculation of the pool token price
        expectRevert_asset(PRICEv2.PRICE_PriceZero.selector, USDC);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getWeightedPoolTokenPrice_revertsOnParamsPoolUndefined() public {
        expectRevert_pool(BalancerPoolTokenPrice.Balancer_PoolTypeNotWeighted.selector, bytes32(0));

        bytes memory params = encodeBalancerPoolParams(IWeightedPool(address(0)));
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getWeightedPoolTokenPrice_coinWeightOneZero() public {
        setUpWeightedPoolTokenPrice();

        setNormalizedWeightsTwo(mockWeightedPool, 0, WETH_WEIGHT);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolWeightInvalid.selector,
            BALANCER_POOL_ID,
            0,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getWeightedPoolTokenPrice_coinWeightTwoZero() public {
        setUpWeightedPoolTokenPrice();

        setNormalizedWeightsTwo(mockWeightedPool, USDC_WEIGHT, 0);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolWeightInvalid.selector,
            BALANCER_POOL_ID,
            1,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getWeightedPoolTokenPrice_coinWeightCountDifferent() public {
        setUpWeightedPoolTokenPrice();

        // Two coins, one weight
        uint256[] memory weights = new uint256[](1);
        weights[0] = USDC_WEIGHT;
        mockWeightedPool.setNormalizedWeights(weights);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenWeightMismatch.selector,
            BALANCER_POOL_ID,
            2,
            1
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getWeightedPoolTokenPrice_fuzz(
        uint8 priceDecimals_,
        uint8 poolDecimals_,
        uint8 tokenDecimals_
    ) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint8 poolDecimals = uint8(bound(poolDecimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint8 tokenDecimals = uint8(bound(tokenDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        // outputDecimals_
        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS));
        mockAssetPrice(WETH, WETH_PRICE.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS));

        // pool decimals
        mockWeightedPool.setDecimals(poolDecimals);
        mockWeightedPool.setTotalSupply(
            BALANCER_POOL_TOTAL_SUPPLY.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );
        mockWeightedPool.setInvariant(
            BALANCER_POOL_INVARIANT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );
        setNormalizedWeightsTwo(
            mockWeightedPool,
            USDC_WEIGHT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS),
            WETH_WEIGHT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );

        // token decimals
        mockERC20Decimals(USDC, tokenDecimals);
        setBalancesTwo(
            mockBalancerVault,
            USDC_BALANCE.mulDiv(10 ** tokenDecimals, 10 ** USDC_DECIMALS),
            WETH_BALANCE
        );

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        uint256 price = balancerSubmodule.getWeightedPoolTokenPrice(
            address(0),
            priceDecimals,
            params
        );

        // Simpler to check that the price before the decimal point is equal
        uint256 truncatedPrice = price.mulDiv(1, 10 ** priceDecimals);
        uint256 truncatedExpectedPrice = _getBalancerPoolTokenPrice(18).mulDiv(
            1,
            10 ** BALANCER_POOL_DECIMALS
        );
        assertEq(truncatedPrice, truncatedExpectedPrice);
    }

    function test_getWeightedPoolTokenPrice_poolTokenDecimalsFuzz(uint8 poolDecimals_) public {
        uint8 poolDecimals = uint8(bound(poolDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        setUpWeightedPoolTokenPrice();

        mockWeightedPool.setDecimals(poolDecimals);
        mockWeightedPool.setTotalSupply(
            BALANCER_POOL_TOTAL_SUPPLY.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );
        mockWeightedPool.setInvariant(
            BALANCER_POOL_INVARIANT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );
        setNormalizedWeightsTwo(
            mockWeightedPool,
            USDC_WEIGHT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS),
            WETH_WEIGHT.mulDiv(10 ** poolDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        uint256 price = balancerSubmodule.getWeightedPoolTokenPrice(
            address(0),
            PRICE_DECIMALS,
            params
        );

        uint8 decimalDiff = poolDecimals > 18 ? poolDecimals - 18 : 18 - poolDecimals;
        assertApproxEqAbs(price, _getBalancerPoolTokenPrice(18), 10 ** decimalDiff);
    }

    function test_getWeightedPoolTokenPrice_poolTokenDecimalsMaximum() public {
        setUpWeightedPoolTokenPrice();

        uint8 poolDecimals = MAX_DECIMALS + 1;
        mockWeightedPool.setDecimals(poolDecimals);
        mockWeightedPool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolDecimalsOutOfBounds.selector,
            BALANCER_POOL_ID,
            poolDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getWeightedPoolTokenPrice_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        // Mock a PRICE implementation with the specified number of decimals
        mockAssetPrice(USDC, USDC_PRICE.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS));
        mockAssetPrice(WETH, WETH_PRICE.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS));

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        uint256 price = balancerSubmodule.getWeightedPoolTokenPrice(
            address(0),
            priceDecimals,
            params
        );

        // Uses outputDecimals_ parameter
        uint8 decimalDiff = priceDecimals > 18 ? priceDecimals - 18 : 18 - priceDecimals + 1;
        assertApproxEqAbs(price, _getBalancerPoolTokenPrice(priceDecimals), 10 ** decimalDiff);
    }

    function test_getWeightedPoolTokenPrice_priceDecimalsMaximum() public {
        uint8 priceDecimals = MAX_DECIMALS + 1;
        setUpWeightedPoolTokenPrice();

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_OutputDecimalsOutOfBounds.selector,
            priceDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), priceDecimals, params);
    }

    function test_getWeightedPoolTokenPrice_tokenDecimalsFuzz(uint8 tokenDecimals_) public {
        uint8 tokenDecimals = uint8(bound(tokenDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        setUpWeightedPoolTokenPrice();

        mockERC20Decimals(USDC, tokenDecimals);
        setBalancesTwo(
            mockBalancerVault,
            USDC_BALANCE.mulDiv(10 ** tokenDecimals, 10 ** USDC_DECIMALS),
            WETH_BALANCE
        );

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        uint256 price = balancerSubmodule.getWeightedPoolTokenPrice(
            address(0),
            PRICE_DECIMALS,
            params
        );

        uint8 decimalDiff = tokenDecimals > 18 ? tokenDecimals - 18 : 18 - tokenDecimals;
        assertApproxEqAbs(price, _getBalancerPoolTokenPrice(18), 10 ** decimalDiff);
    }

    function test_getWeightedPoolTokenPrice_zeroCoins() public {
        setUpWeightedPoolTokenPrice();

        // Mock 0 coins
        address[] memory coins = new address[](0);
        mockBalancerVault.setTokens(coins);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenWeightMismatch.selector,
            BALANCER_POOL_ID,
            0,
            2
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getWeightedPoolTokenPrice_coinOneAddressZero() public {
        setUpWeightedPoolTokenPrice();

        setTokensTwo(mockBalancerVault, address(0), WETH);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenInvalid.selector,
            BALANCER_POOL_ID,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getWeightedPoolTokenPrice_coinTwoAddressZero() public {
        setUpWeightedPoolTokenPrice();

        setTokensTwo(mockBalancerVault, USDC, address(0));

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolTokenInvalid.selector,
            BALANCER_POOL_ID,
            1,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getWeightedPoolTokenPrice_poolTokenSupplyZero() public {
        setUpWeightedPoolTokenPrice();

        mockWeightedPool.setTotalSupply(0);

        bytes memory err = abi.encodeWithSelector(
            BalancerPoolTokenPrice.Balancer_PoolSupplyInvalid.selector,
            BALANCER_POOL_ID,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeBalancerPoolParams(mockWeightedPool);
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getWeightedPoolTokenPrice_incorrectPoolType() public {
        setUpWeightedPoolTokenPrice();

        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(BALANCER_POOL_DECIMALS);
        mockNonWeightedPool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);
        mockNonWeightedPool.setPoolId(BALANCER_POOL_ID);

        // Will fail as the pool does not have the supported function
        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTypeNotWeighted.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = abi.encode(mockNonWeightedPool);
        balancerSubmodule.getWeightedPoolTokenPrice(address(0), PRICE_DECIMALS, params);
    }
}
