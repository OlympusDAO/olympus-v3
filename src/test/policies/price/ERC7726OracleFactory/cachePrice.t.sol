// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";
import {ERC7726OracleCloneable} from "src/policies/price/ERC7726OracleCloneable.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";

contract CachePriceCaller {
    IERC7726OracleFactory public cache;

    constructor(IERC7726OracleFactory cache_) {
        cache = cache_;
    }

    function cachePrice(address base_, address quote_) external {
        cache.cachePrice(base_, quote_);
    }
}

contract ERC7726OracleFactoryCachePriceTest is ERC7726OracleFactoryTest {
    function test_whenOracleIsEnabled_cachePricesCachesPair()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        MockPriceCache priceCache = _deployConfiguredPriceCache();
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        clone.cachePrice(address(baseToken), address(quoteToken));

        assertEq(
            priceCache.cachePriceCallCount(),
            1,
            "Price cache should receive direct cache write"
        );
        assertEq(priceCache.lastAsset(), address(baseToken), "Asset should match direct pair");
        assertEq(priceCache.lastQuote(), address(quoteToken), "Quote should match direct pair");
    }

    function test_whenOracleIsEnabled_cachePricesIfNecessaryDoesNotCacheWhenFresh()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        MockPriceCache priceCache = _deployConfiguredPriceCache();
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceCache.cachePrice(address(baseToken), address(quoteToken));

        vm.warp(block.timestamp + 1);
        clone.cachePriceIfNecessary(address(baseToken), address(quoteToken));

        assertEq(
            priceCache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(priceCache.cachePriceCallCount(), 1, "Fresh cache should not be re-cached");
    }

    function test_whenOracleIsEnabled_cachePricesIfNecessaryCachesWhenStale()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        MockPriceCache priceCache = _deployConfiguredPriceCache();
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceCache.cachePrice(address(baseToken), address(quoteToken));

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        clone.cachePriceIfNecessary(address(baseToken), address(quoteToken));

        assertEq(
            priceCache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(priceCache.cachePriceCallCount(), 2, "Stale pair cache should be updated");
    }

    function test_whenOracleMaxAgeIsZero_cachePricesIfNecessaryCachesWhenTimestampIsFromPriorBlock()
        public
        givenFactoryIsEnabled
    {
        MockPriceCache priceCache = _deployConfiguredPriceCache();
        address oracle = _createOracle(0);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceCache.cachePrice(address(baseToken), address(quoteToken));

        vm.warp(block.timestamp + 1);
        clone.cachePriceIfNecessary(address(baseToken), address(quoteToken));

        assertEq(
            priceCache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(priceCache.cachePriceCallCount(), 2, "maxAge=0 should recache pair timestamp");
    }

    function test_whenOracleIsDisabled_cachePricesReverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_OracleDisabled.selector,
                oracle
            )
        );
        clone.cachePrice(address(baseToken), address(quoteToken));
    }

    function test_whenFactoryIsDisabled_cachePricesReverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenFactoryIsDisabled
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        clone.cachePrice(address(baseToken), address(quoteToken));
    }

    function test_whenCallerIsNotFactoryOracle_cachePricesReverts() public givenFactoryIsEnabled {
        CachePriceCaller caller = new CachePriceCaller(IERC7726OracleFactory(address(factory)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_InvalidOracle.selector,
                address(caller)
            )
        );
        caller.cachePrice(address(baseToken), address(quoteToken));
    }

    function test_whenPriceCachePolicyIsDisabled_cachePriceReverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        MockPriceCache priceCache = _deployConfiguredPriceCache();
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceCache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        clone.cachePrice(address(baseToken), address(quoteToken));
    }

    function _deployConfiguredPriceCache() internal returns (MockPriceCache priceCache) {
        priceCache = new MockPriceCache();
        priceCache.setUsdPrice(address(baseToken), 2e18);
        priceCache.setUsdPrice(address(quoteToken), 1e18);

        vm.prank(admin);
        factory.setPriceCache(address(priceCache));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
