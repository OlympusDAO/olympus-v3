// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {Actions} from "src/Kernel.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";

contract MorphoOracleCloneablePriceTest is MorphoOracleCloneableTest {
    // The SwapMock contract is used as inspiration for how to validate that the
    // scale and value of the price are correct.
    // See: https://github.com/morpho-org/morpho-blue-snippets/blob/cf9431f320a61b1344a9936baeb71719c2e44c41/src/morpho-blue/mocks/SwapMock.sol

    // ========== TESTS ========== //

    // price
    // when factory is disabled
    //  [X] it reverts with MorphoOracle_NotEnabled

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IMorphoOracle.MorphoOracle_NotEnabled.selector);

        oracle.price();
    }

    function test_whenFactoryPolicyIsDeactivated_reverts() public {
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));

        vm.expectRevert(IOracleFactory.OracleFactory_PolicyNotActive.selector);
        oracle.price();
    }

    // when oracle is not enabled
    //  [X] it reverts with MorphoOracle_NotEnabled

    function test_whenOracleIsNotEnabled_reverts() public givenOracleIsDisabled {
        vm.expectRevert(IMorphoOracle.MorphoOracle_NotEnabled.selector);

        oracle.price();
    }

    // when collateral token cache is stale
    //  [X] it reverts with MorphoOracle_Stale

    function test_whenCollateralTokenCacheIsStale_reverts() public {
        uint48 cachedAt = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        // Force stale state; cached-only semantics should revert stale before using live prices.
        vm.warp(uint256(cachedAt) + DEFAULT_MAX_AGE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracle.MorphoOracle_Stale.selector,
                cachedAt,
                DEFAULT_MAX_AGE
            )
        );
        oracle.price();
    }

    // when loan token cache is stale
    //  [X] it reverts with MorphoOracle_Stale

    function test_whenLoanTokenCacheIsStale_reverts() public {
        uint48 cachedAt = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        // Force stale state; cached-only semantics should revert stale before using live prices.
        vm.warp(uint256(cachedAt) + DEFAULT_MAX_AGE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracle.MorphoOracle_Stale.selector,
                cachedAt,
                DEFAULT_MAX_AGE
            )
        );
        oracle.price();
    }

    // when collateral token cached price is zero
    //  [X] it reverts with MorphoOracle_InvalidPrice

    function test_whenCollateralTokenCachedPriceIsZero_revertsInvalidPrice() public {
        _setPRICEPrices(address(collateralToken), 0);
        priceCache.cachePrice(address(collateralToken), address(loanToken));

        vm.expectRevert(IMorphoOracle.MorphoOracle_InvalidPrice.selector);
        oracle.price();
    }

    // when loan token cached price is zero
    //  [X] it reverts with MorphoOracle_InvalidPrice

    function test_whenLoanTokenCachedPriceIsZero_revertsInvalidPrice() public {
        _setPRICEPrices(address(loanToken), 0);
        priceCache.cachePrice(address(collateralToken), address(loanToken));

        vm.expectRevert(IMorphoOracle.MorphoOracle_InvalidPrice.selector);
        oracle.price();
    }

    // [X] it calculates price correctly
    // [X] it returns price with correct scale (36 decimals + 18 - 18)

    function test_whenCacheIsFresh_returnsCorrectScaledPrice() public view {
        // oracle.price() returns the price of 1 collateral token quoted in loan tokens, scaled by 1e36
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals)
        // scaleFactor = 1e36 (36 + 18 - 18)
        // the price is 2e18 * 1e36 / 1e18 = 2e36
        uint256 expectedPrice = 2e36;
        uint256 actualPrice = oracle.price();

        assertEq(actualPrice, expectedPrice, "Price should be calculated correctly");

        // Calculate the loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e18 * 2e36 / 1e36 = 2e18
        uint256 expectedLoanTokensPerCollateralToken = 2e18;
        uint256 actualLoanTokensPerCollateralToken = (1e18 * actualPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly"
        );

        // Calculate the collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e18 * 1e36 / 2e36 = 0.5e18
        uint256 expectedCollateralTokensPerLoanToken = 0.5e18;
        uint256 actualCollateralTokensPerLoanToken = (1e18 * 1e36) / actualPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly"
        );
    }

    function test_gasSnapshot_price() public {
        vm.startSnapshotGas("MorphoOracleCloneable.price");
        oracle.price();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    // when the collateral token decimals are smaller than the loan token decimals
    //  [X] it calculates price correctly

    function test_whenCollateralTokenDecimalsAreSmallerThanLoanTokenDecimals() public {
        // Create a new collateral token with 9 decimals
        MockERC20 newCollateralToken = new MockERC20("New Collateral Token", "NEWCOL", 9);

        // Set collateral token price to 2e18
        _setPRICEPrices(address(newCollateralToken), 2e18);

        // Create the oracle with the new collateral token
        vm.prank(admin);
        address newOracle = factory.createOracle(
            address(newCollateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        // oracle.price() returns the price of 1 collateral token quoted in loan tokens, scaled by 1e36
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals, but native is 9 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals)
        // scaleFactor = 1e45 (36 + loanDecimals - collateralDecimals = 36 + 18 - 9)
        // the price is 2e18 * 1e45 / 1e18 = 2e45
        uint256 expectedPrice = 2e45;
        uint256 actualPrice = IMorphoOracle(newOracle).price();

        assertEq(actualPrice, expectedPrice, "Price should be calculated correctly");

        // Calculate the loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e9 * 2e45 / 1e36 = 2e18
        uint256 expectedLoanTokensPerCollateralToken = 2e18;
        uint256 actualLoanTokensPerCollateralToken = (1e9 * actualPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly"
        );

        // Calculate the collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e18 * 1e36 / 2e45 = 0.5e9
        uint256 expectedCollateralTokensPerLoanToken = 0.5e9;
        uint256 actualCollateralTokensPerLoanToken = (1e18 * 1e36) / actualPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly"
        );
    }

    // when the loan token decimals are smaller than the collateral token decimals
    //  [X] it calculates price correctly

    function test_whenLoanTokenDecimalsAreSmallerThanCollateralTokenDecimals() public {
        // Create a new loan token with 9 decimals
        MockERC20 newLoanToken = new MockERC20("New Loan Token", "NEWLOAN", 9);

        // Set loan token price to 1e18
        _setPRICEPrices(address(newLoanToken), 1e18);

        // Create the oracle with the new loan token
        vm.prank(admin);
        address newOracle = factory.createOracle(
            address(collateralToken),
            address(newLoanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        // oracle.price() returns the price of 1 collateral token quoted in loan tokens, scaled by 1e36
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals, but native is 9 decimals)
        // scaleFactor = 1e27 (36 + 9 - 18)
        // the price is 2e18 * 1e27 / 2e18 = 2e27
        uint256 expectedPrice = 2e27;
        uint256 actualPrice = IMorphoOracle(newOracle).price();

        assertEq(actualPrice, expectedPrice, "Price should be calculated correctly");

        // Calculate the loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e18 * 2e27 / 1e36 = 2e9
        uint256 expectedLoanTokensPerCollateralToken = 2e9;
        uint256 actualLoanTokensPerCollateralToken = (1e18 * actualPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly"
        );

        // Calculate the collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e9 * 1e36 / 2e27 = 0.5e18
        uint256 expectedCollateralTokensPerLoanToken = 0.5e18;
        uint256 actualCollateralTokensPerLoanToken = (1e9 * 1e36) / actualPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly"
        );
    }

    // when collateral has 0 decimals and loan has 18 decimals
    //  [X] it returns the correctly scaled non-zero price for a 1:3 ratio
    function test_whenZeroDecimalCollateralAndOneToThreeRatio_returnsNonZeroPrice() public {
        // Create a new collateral token with 0 decimals.
        MockERC20 newCollateralToken = new MockERC20("Zero Dec Collateral", "ZCOL", 0);

        // Set prices to collateral=1e18 USD and loan=3e18 USD.
        _setPRICEPrices(address(newCollateralToken), 1e18);
        _setPRICEPrices(address(loanToken), 3e18);

        // Create oracle for the new pair.
        vm.prank(admin);
        address newOracle = factory.createOracle(
            address(newCollateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        // scaleFactor = 1e54 (36 + 18 - 0)
        // price = (1e18 * 1e54) / 3e18 = 1e54 / 3
        uint256 expectedPrice = 333333333333333333333333333333333333333333333333333333;
        uint256 actualPrice = IMorphoOracle(newOracle).price();
        assertEq(actualPrice, expectedPrice, "Price should preserve non-zero precision");

        // loan tokens per collateral token = 1 * price / 1e36 = 333333333333333333
        uint256 expectedLoanTokensPerCollateralToken = 333333333333333333;
        uint256 actualLoanTokensPerCollateralToken = actualPrice / 1e36;
        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be correctly scaled"
        );
    }

    // when collateral live price changes
    //  [X] it keeps returning cached price until cache refresh
    //  [X] it reflects new price after cache refresh

    function test_whenCollateralPriceChanges_reflectsAfterCacheRefresh() public {
        // Initial price: 2e18 / 1e18 * 1e36 = 2e36
        uint256 initialPrice = oracle.price();
        assertEq(initialPrice, 2e36, "Initial price should be 2e36");

        // Change live collateral price only (do not cache yet)
        _setPRICEPrices(address(collateralToken), 3e18);

        // Cached-only semantics: value should remain unchanged before cache refresh
        uint256 staleCachedPrice = oracle.price();
        assertEq(staleCachedPrice, initialPrice, "Price should remain cached before refresh");

        // Refresh both caches to pull in new live values
        vm.warp(block.timestamp + 1);
        priceCache.cachePrice(address(collateralToken), address(loanToken));

        // New price: 3e18 / 1e18 * 1e36 = 3e36
        uint256 newPrice = oracle.price();
        assertEq(newPrice, 3e36, "Price should reflect new collateral price");
    }

    // when loan live price changes
    //  [X] it keeps returning cached price until cache refresh
    //  [X] it reflects new price after cache refresh

    function test_whenLoanPriceChanges_reflectsAfterCacheRefresh() public {
        // Initial price: 2e18 / 1e18 * 1e36 = 2e36
        uint256 initialPrice = oracle.price();
        assertEq(initialPrice, 2e36, "Initial price should be 2e36");

        // Change live loan price only (do not cache yet)
        _setPRICEPrices(address(loanToken), 2e18);

        // Cached-only semantics: value should remain unchanged before cache refresh
        uint256 staleCachedPrice = oracle.price();
        assertEq(staleCachedPrice, initialPrice, "Price should remain cached before refresh");

        // Refresh both caches to pull in new live values
        vm.warp(block.timestamp + 1);
        priceCache.cachePrice(address(collateralToken), address(loanToken));

        // New price: 2e18 / 2e18 * 1e36 = 1e36
        uint256 newPrice = oracle.price();
        assertEq(newPrice, 1e36, "Price should reflect new loan price");
    }

    function test_whenOnlyCollateralUsdCacheChanges_returnsCachedPairPrice() public {
        // Move to a new block and change only live collateral/USD price.
        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(collateralToken), 8e18);

        // Refresh only collateral/USD cache. The direct collateral/loan pair cache should be unchanged.
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);

        assertEq(oracle.price(), 2e36, "Oracle should continue using the cached pair price");
    }

    function test_whenOnlyLoanUsdCacheChanges_returnsCachedPairPrice() public {
        // Move to a new block and change only live loan/USD price.
        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(loanToken), 4e18);

        // Refresh only loan/USD cache. The direct collateral/loan pair cache should be unchanged.
        priceCache.cachePrice(address(loanToken), UNIT_OF_ACCOUNT);

        assertEq(oracle.price(), 2e36, "Oracle should continue using the cached pair price");
    }

    // when price cache is updated in factory
    //  [X] it uses the updated cache policy

    function test_whenPriceCacheIsUpdatedInFactory_usesUpdatedPolicy() public {
        MockPriceCache newPriceCache = new MockPriceCache(address(kernel));
        newPriceCache.setUsdPrice(address(collateralToken), 4e18);
        newPriceCache.setUsdPrice(address(loanToken), 1e18);
        newPriceCache.cachePrice(address(collateralToken), address(loanToken));

        vm.prank(admin);
        factory.setPriceCache(address(newPriceCache));

        // Oracle should now reflect the updated cache policy values.
        // Expected: 4e18 / 1e18 * 1e36 = 4e36
        uint256 newPrice = oracle.price();
        assertEq(newPrice, 4e36, "Oracle should use updated cache policy prices");
    }

    // when cache decimals are changed
    //  [X] it calculates price correctly

    function test_whenPriceCacheDecimalsAreChanged_calculatesPriceCorrectly() public {
        // Initial setup: cache decimals = 18
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals)
        // scaleFactor = 1e36 (36 + 18 - 18)
        // Expected price: 2e18 * 1e36 / 1e18 = 2e36
        uint256 initialPrice = oracle.price();
        assertEq(initialPrice, 2e36, "Initial price should be 2e36");

        // Change cache decimals from 18 to 9
        priceCache.setPriceDecimals(9);

        // Update prices to maintain same USD values with new decimals
        // 2e18 (18 decimals) -> 2e9 (9 decimals) for $2
        // 1e18 (18 decimals) -> 1e9 (9 decimals) for $1
        _setPRICEPrices(address(collateralToken), 2e9);
        _setPRICEPrices(address(loanToken), 1e9);

        // Oracle should still return correct price
        // The scaleFactor is immutable and based on token decimals (36 + 18 - 18 = 36)
        // collateralPriceUsd = 2e9 (2 USD, 9 decimals)
        // loanPriceUsd = 1e9 (1 USD, 9 decimals)
        // scaleFactor = 1e36 (unchanged, based on token decimals)
        // Price calculation: 1e36 * 2e9 / 1e9 = 2e36
        // The result is still 2e36 because the ratio is preserved
        uint256 newPrice = oracle.price();
        assertEq(newPrice, 2e36, "Price should remain 2e36 after cache decimals change");

        // Verify the calculation is still accurate by checking loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e18 * 2e36 / 1e36 = 2e18
        uint256 expectedLoanTokensPerCollateralToken = 2e18;
        uint256 actualLoanTokensPerCollateralToken = (1e18 * newPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly after cache decimals change"
        );

        // Verify collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e18 * 1e36 / 2e36 = 0.5e18
        uint256 expectedCollateralTokensPerLoanToken = 0.5e18;
        uint256 actualCollateralTokensPerLoanToken = (1e18 * 1e36) / newPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly after cache decimals change"
        );
    }

    // given the collateral token decimals are smaller than the loan token decimals
    //  when cache decimals are changed
    //   [X] it calculates price correctly

    function test_whenCollateralTokenDecimalsAreSmallerThanLoanTokenDecimals_whenPriceCacheDecimalsAreChanged()
        public
    {
        // Create a new collateral token with 9 decimals
        MockERC20 newCollateralToken = new MockERC20("New Collateral Token", "NEWCOL", 9);

        // Set collateral token price to 2e18
        _setPRICEPrices(address(newCollateralToken), 2e18);

        // Create the oracle with the new collateral token
        vm.prank(admin);
        address newOracle = factory.createOracle(
            address(newCollateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        // Initial setup: cache decimals = 18
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals)
        // scaleFactor = 1e45 (36 + 18 - 9)
        // Expected price: 1e45 * 2e18 / 1e18 = 2e45
        uint256 expectedPrice = 2e45;
        uint256 initialPrice = IMorphoOracle(newOracle).price();
        assertEq(initialPrice, expectedPrice, "Initial price should be 2e45");

        // Change cache decimals from 18 to 9
        priceCache.setPriceDecimals(9);

        // Update prices to maintain same USD values with new decimals
        // 2e18 (18 decimals) -> 2e9 (9 decimals) for $2
        // 1e18 (18 decimals) -> 1e9 (9 decimals) for $1
        _setPRICEPrices(address(newCollateralToken), 2e9);
        _setPRICEPrices(address(loanToken), 1e9);

        // Oracle should still return correct price
        // The scaleFactor is immutable and based on token decimals (36 + 18 - 9 = 45)
        // collateralPriceUsd = 2e9 (2 USD, 9 decimals)
        // loanPriceUsd = 1e9 (1 USD, 9 decimals)
        // scaleFactor = 1e45 (unchanged, based on token decimals)
        // Price calculation: 1e45 * 2e9 / 1e9 = 2e45
        // The result is still 2e45 because the ratio is preserved
        uint256 newPrice = IMorphoOracle(newOracle).price();
        assertEq(newPrice, expectedPrice, "Price should remain 2e45 after cache decimals change");

        // Verify the calculation is still accurate by checking loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e9 * 2e45 / 1e36 = 2e18
        uint256 expectedLoanTokensPerCollateralToken = 2e18;
        uint256 actualLoanTokensPerCollateralToken = (1e9 * newPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly after cache decimals change"
        );

        // Verify collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e18 * 1e36 / 2e45 = 0.5e9
        uint256 expectedCollateralTokensPerLoanToken = 0.5e9;
        uint256 actualCollateralTokensPerLoanToken = (1e18 * 1e36) / newPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly after cache decimals change"
        );
    }

    // given the loan token decimals are smaller than the collateral token decimals
    //  when cache decimals are changed
    //   [X] it calculates price correctly

    function test_whenLoanTokenDecimalsAreSmallerThanCollateralTokenDecimals_whenPriceCacheDecimalsAreChanged()
        public
    {
        // Create a new loan token with 9 decimals
        MockERC20 newLoanToken = new MockERC20("New Loan Token", "NEWLOAN", 9);

        // Set loan token price to 1e18
        _setPRICEPrices(address(newLoanToken), 1e18);

        // Create the oracle with the new loan token
        vm.prank(admin);
        address newOracle = factory.createOracle(
            address(collateralToken),
            address(newLoanToken),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        // Initial setup: cache decimals = 18
        // collateralPriceUsd = 2e18 (2 USD, 18 decimals)
        // loanPriceUsd = 1e18 (1 USD, 18 decimals)
        // scaleFactor = 1e27 (36 + loanDecimals - collateralDecimals = 36 + 9 - 18)
        // Expected price: 1e27 * 2e18 / 1e18 = 2e27
        uint256 expectedPrice = 2e27;
        uint256 initialPrice = IMorphoOracle(newOracle).price();
        assertEq(initialPrice, expectedPrice, "Initial price should be 2e27");

        // Change cache decimals from 18 to 9
        priceCache.setPriceDecimals(9);

        // Update prices to maintain same USD values with new decimals
        // 2e18 (18 decimals) -> 2e9 (9 decimals) for $2
        // 1e18 (18 decimals) -> 1e9 (9 decimals) for $1
        _setPRICEPrices(address(collateralToken), 2e9);
        _setPRICEPrices(address(newLoanToken), 1e9);

        // Oracle should still return correct price
        // The scaleFactor is immutable and based on token decimals (36 + 9 - 18 = 27)
        // collateralPriceUsd = 2e9 (2 USD, 9 decimals)
        // loanPriceUsd = 1e9 (1 USD, 9 decimals)
        // scaleFactor = 1e27 (unchanged, based on token decimals)
        // Price calculation: 1e27 * 2e9 / 1e9 = 2e27
        // The result is still 2e27 because the ratio is preserved
        uint256 newPrice = IMorphoOracle(newOracle).price();
        assertEq(newPrice, expectedPrice, "Price should remain 2e27 after cache decimals change");

        // Verify the calculation is still accurate by checking loan tokens per collateral token
        // loan tokens per collateral token = 1 collateral token (native decimals) * price / 1e36
        // loan tokens per collateral token = 1e18 * 2e27 / 1e36 = 2e9
        uint256 expectedLoanTokensPerCollateralToken = 2e9;
        uint256 actualLoanTokensPerCollateralToken = (1e18 * newPrice) / 1e36;

        assertEq(
            actualLoanTokensPerCollateralToken,
            expectedLoanTokensPerCollateralToken,
            "Loan tokens per collateral token should be calculated correctly after cache decimals change"
        );

        // Verify collateral tokens per loan token
        // collateral tokens per loan token = 1 loan token (native decimals) * 1e36 / price
        // collateral tokens per loan token = 1e9 * 1e36 / 2e27 = 0.5e18
        uint256 expectedCollateralTokensPerLoanToken = 0.5e18;
        uint256 actualCollateralTokensPerLoanToken = (1e9 * 1e36) / newPrice;

        assertEq(
            actualCollateralTokensPerLoanToken,
            expectedCollateralTokensPerLoanToken,
            "Collateral tokens per loan token should be calculated correctly after cache decimals change"
        );
    }

    // when cached prices are fresh (within maxAge)
    //  [X] it returns cached prices even if live prices changed

    function test_whenCachedPricesAreFresh_returnsCachedPrices(uint48 warpDelta_) public {
        // Cache initial prices
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        // Change live prices without storing
        _setPRICEPrices(address(collateralToken), 3e18);
        _setPRICEPrices(address(loanToken), 1e18);

        // Fuzz warp to a time strictly within maxAge so cache remains fresh
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE - 1));
        vm.warp(cachedAt + warpDelta);

        // Cached ratio remains (2e18 / 1e18) * 1e36 = 2e36
        uint256 expectedCachedPrice = 2e36;
        uint256 actualPrice = oracle.price();

        assertEq(actualPrice, expectedCachedPrice, "Should return cached price while fresh");
    }

    function test_whenCachedAgeEqualsMaxAge_returnsCachedPrices() public {
        // Cache initial prices
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        // Change live prices without storing so cache-vs-live behavior is observable
        _setPRICEPrices(address(collateralToken), 3e18);
        _setPRICEPrices(address(loanToken), 1e18);

        // Border case: cached age is exactly maxAge and should still be treated as fresh
        vm.warp(cachedAt + DEFAULT_MAX_AGE);

        // Cached ratio remains (2e18 / 1e18) * 1e36 = 2e36
        uint256 expectedCachedPrice = 2e36;
        uint256 actualPrice = oracle.price();

        assertEq(actualPrice, expectedCachedPrice, "Should return cached price at maxAge boundary");
    }

    // when cached prices are stale (older than maxAge)
    //  [X] it reverts

    function test_whenCachedPricesAreStale_reverts(uint48 warpDelta_) public {
        // Cache initial prices
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        // Fuzz warp to a time strictly beyond maxAge so cache is stale
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );
        vm.warp(cachedAt + warpDelta);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracle.MorphoOracle_Stale.selector,
                cachedAt,
                DEFAULT_MAX_AGE
            )
        );
        oracle.price();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
