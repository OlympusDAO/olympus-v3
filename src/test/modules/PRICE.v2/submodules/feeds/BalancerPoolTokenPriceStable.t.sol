// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPricev2} from "test/mocks/MockPrice.v2.sol";
import {MockBalancerPool, MockBalancerStablePool, MockBalancerWeightedPool} from "test/mocks/MockBalancerPool.sol";
import {MockBalancerVault} from "test/mocks/MockBalancerVault.sol";
import {FullMath} from "libraries/FullMath.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {BalancerPoolTokenPrice, IStablePool, IVault} from "modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";

contract BalancerPoolTokenPriceStableTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for BalancerPoolTokenPrice;

    MockPricev2 internal mockPrice;
    MockBalancerVault internal mockBalancerVault;
    MockBalancerStablePool internal mockStablePool;

    BalancerPoolTokenPrice internal balancerSubmodule;

    bytes32 internal BALANCER_POOL_ID =
        0x3dd0843a028c86e0b760b1a76929d1c5ef93a2dd000200000000000000000249;
    address internal BALANCER_POOL = 0x3dd0843A028C86e0b760b1A76929d1C5Ef93a2dd;
    uint256 internal BALANCER_POOL_TOTAL_SUPPLY = 1166445846909257605048176;
    uint8 internal BALANCER_POOL_DECIMALS = 18;

    uint256 internal INVARIANT = 1203974641585710664986665;
    uint256 internal AMP_FACTOR = 50000;

    address internal B_80BAL_20WETH = 0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56;
    address internal AURA_BAL = 0x616e8BfA43F920657B3497DBf40D6b1A02D4608d;

    uint8 internal B_80BAL_20WETH_DECIMALS = 18;
    uint8 internal AURA_BAL_DECIMALS = 18;

    uint256 internal B_80BAL_20WETH_BALANCE = 507713528624138828935656;
    uint256 internal AURA_BAL_BALANCE = 696558540009160592774860;

    uint256 internal B_80BAL_20WETH_BALANCE_PRICE = 16.71 * 1e18;
    uint256 internal B_80BAL_20WETH_BALANCE_PRICE_EXPECTED = 16710001252344598708;
    uint256 internal AURA_BAL_PRICE_EXPECTED = 16602528871962134544;

    uint256 internal BALANCER_POOL_RATE = 1032914638684593940;

    uint8 MIN_DECIMALS = 6;
    uint8 MAX_DECIMALS = 50;

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
        }

        // Set up the Balancer submodule
        {
            Kernel kernel = new Kernel();
            mockPrice = new MockPricev2(kernel);
            mockPrice.setTimestamp(uint48(block.timestamp));
            mockPrice.setPriceDecimals(BALANCER_POOL_DECIMALS);
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
        uint256 rate = BALANCER_POOL_RATE.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS); // price decimals
        uint256 baseTokenPrice = B_80BAL_20WETH_BALANCE_PRICE_EXPECTED.mulDiv(
            10 ** priceDecimals,
            10 ** BALANCER_POOL_DECIMALS
        ); // price decimals

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
        uint256 price = balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, params);

        // Expected price, given the inputs
        assertEq(price, AURA_BAL_PRICE_EXPECTED);
    }

    function test_getTokenPriceFromStablePool_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockPrice.setPriceDecimals(priceDecimals);
        mockAssetPrice(
            B_80BAL_20WETH,
            B_80BAL_20WETH_BALANCE_PRICE.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS)
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        uint256 price = balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, params);

        // Will be normalised to price decimals
        uint8 decimalDiff = priceDecimals > 18 ? priceDecimals - 18 : 18 - priceDecimals;
        assertApproxEqAbs(
            price,
            AURA_BAL_PRICE_EXPECTED.mulDiv(10 ** priceDecimals, 10 ** BALANCER_POOL_DECIMALS),
            10 ** decimalDiff
        );
    }

    function test_getTokenPriceFromStablePool_priceDecimalsMaximum() public {
        mockPrice.setPriceDecimals(100);
        mockAssetPrice(B_80BAL_20WETH, (B_80BAL_20WETH_BALANCE_PRICE * 1e21) / 1e18);

        expectRevert_asset(
            BalancerPoolTokenPrice.Balancer_PRICEDecimalsOutOfBounds.selector,
            address(mockPrice)
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, params);
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
    //         params
    //     );

    //     assertTrue(success);
    //     // Will be normalised to price decimals
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
    //         params
    //     );

    //     assertFalse(success);
    //     assertEq(0, price);
    // }

    function test_getTokenPriceFromStablePool_unknownToken() public {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        expectRevert_asset(BalancerPoolTokenPrice.Balancer_LookupTokenNotFound.selector, DAI);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(DAI, params);
    }

    function test_getTokenPriceFromStablePool_noPrice() public {
        // PRICE not configured to handle the asset, returns 0
        mockAssetPrice(B_80BAL_20WETH, 0);

        expectRevert_asset(BalancerPoolTokenPrice.Balancer_PriceNotFound.selector, AURA_BAL);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, params);
    }

    function test_getTokenPriceFromStablePool_coinOneZero() public {
        setTokensTwo(mockBalancerVault, address(0), AURA_BAL);

        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTokensInvalid.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, params);
    }

    function test_getTokenPriceFromStablePool_coinTwoZero() public {
        setTokensTwo(mockBalancerVault, B_80BAL_20WETH, address(0));

        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTokensInvalid.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, params);
    }

    function test_getTokenPriceFromStablePool_inverse() public {
        mockAssetPrice(B_80BAL_20WETH, 0);
        mockAssetPrice(AURA_BAL, AURA_BAL_PRICE_EXPECTED);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        uint256 price = balancerSubmodule.getTokenPriceFromStablePool(B_80BAL_20WETH, params);

        assertEq(price, B_80BAL_20WETH_BALANCE_PRICE_EXPECTED);
    }

    function test_getTokenPriceFromStablePool_twoTokens_oneBalances() public {
        uint256[] memory balances = new uint256[](1);
        balances[0] = B_80BAL_20WETH_BALANCE;
        mockBalancerVault.setBalances(balances);

        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTokensInvalid.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, params);
    }

    function test_getTokenPriceFromStablePool_oneTokens_twoBalances() public {
        // mockAssetPrice(B_80BAL_20WETH, 0);
        mockAssetPrice(AURA_BAL, AURA_BAL_PRICE_EXPECTED);

        address[] memory tokens = new address[](1);
        tokens[0] = B_80BAL_20WETH;
        mockBalancerVault.setTokens(tokens);

        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTokensInvalid.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getTokenPriceFromStablePool(B_80BAL_20WETH, params);
    }

    function test_getTokenPriceFromStablePool_incorrectPoolType() public {
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
        balancerSubmodule.getTokenPriceFromStablePool(AURA_BAL, params);
    }

    // ========= POOL TOKEN PRICE ========= //

    function setUpStablePoolTokenPrice() internal {
        mockAssetPrice(AURA_BAL, AURA_BAL_PRICE_EXPECTED);
        mockAssetPrice(B_80BAL_20WETH, B_80BAL_20WETH_BALANCE_PRICE_EXPECTED);
    }

    function test_getStablePoolTokenPrice_baseTokenPriceZero() public {
        setUpStablePoolTokenPrice();

        mockAssetPrice(B_80BAL_20WETH, 0);

        // A revert in the base token price will be passed up, as that prevents calculation of the pool token price
        expectRevert_asset(PRICEv2.PRICE_PriceZero.selector, B_80BAL_20WETH);

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(params);
    }

    function test_getStablePoolTokenPrice_rateZero() public {
        setUpStablePoolTokenPrice();

        mockStablePool.setRate(0);

        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolStableRateInvalid.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(params);
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
        uint256 price = balancerSubmodule.getStablePoolTokenPrice(params);

        uint8 decimalDiff = poolDecimals > 18 ? poolDecimals - 18 : 18 - poolDecimals + 2;
        assertApproxEqAbs(price, _getBalancerPoolTokenPrice(18), 10 ** decimalDiff);
    }

    function test_getStablePoolTokenPrice_poolTokenDecimalsMaximum() public {
        setUpStablePoolTokenPrice();

        mockStablePool.setDecimals(100);
        mockStablePool.setTotalSupply(BALANCER_POOL_TOTAL_SUPPLY);

        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolDecimalsOutOfBounds.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(params);
    }

    function test_getStablePoolTokenPrice_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        // Mock a PRICE implementation with a higher number of decimals
        mockPrice.setPriceDecimals(priceDecimals);
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
        uint256 price = balancerSubmodule.getStablePoolTokenPrice(params);

        // Uses price decimals parameter
        uint8 decimalDiff = priceDecimals > 18 ? priceDecimals - 18 : 18 - priceDecimals;
        assertApproxEqAbs(price, _getBalancerPoolTokenPrice(priceDecimals), 10 ** decimalDiff);
    }

    function test_getStablePoolTokenPrice_priceDecimalsMaximum() public {
        setUpStablePoolTokenPrice();

        // Mock a PRICE implementation with a higher number of decimals
        mockPrice.setPriceDecimals(100);

        expectRevert_asset(
            BalancerPoolTokenPrice.Balancer_PRICEDecimalsOutOfBounds.selector,
            address(mockPrice)
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(params);
    }

    function test_getStablePoolTokenPrice_fuzz(uint8 poolDecimals_, uint8 priceDecimals_) public {
        uint8 poolDecimals = uint8(bound(poolDecimals_, MIN_DECIMALS, MAX_DECIMALS));
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        mockPrice.setPriceDecimals(priceDecimals);
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
        uint256 price = balancerSubmodule.getStablePoolTokenPrice(params);

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

        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTokensInvalid.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(params);
    }

    function test_getStablePoolTokenPrice_coinOneAddressZero() public {
        setUpStablePoolTokenPrice();

        setTokensTwo(mockBalancerVault, address(0), AURA_BAL);

        expectRevert_pool(
            BalancerPoolTokenPrice.Balancer_PoolTokensInvalid.selector,
            BALANCER_POOL_ID
        );

        bytes memory params = encodeBalancerPoolParams(mockStablePool);
        balancerSubmodule.getStablePoolTokenPrice(params);
    }

    function test_getStablePoolTokenPrice_incorrectPoolType() public {
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
        balancerSubmodule.getStablePoolTokenPrice(params);
    }
}
