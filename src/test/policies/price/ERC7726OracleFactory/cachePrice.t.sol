// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";
import {ERC7726OracleCloneable} from "src/policies/price/ERC7726OracleCloneable.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

contract CachePriceCaller {
    IERC7726OracleFactory public cache;

    constructor(IERC7726OracleFactory cache_) {
        cache = cache_;
    }

    function cachePrices(address base_, address quote_) external {
        cache.cachePrices(base_, quote_);
    }

    function cachePricesIfNecessary(address base_, address quote_, uint48 maxAge_) external {
        cache.cachePricesIfNecessary(base_, quote_, maxAge_);
    }
}

contract ERC7726OracleFactoryCachePriceTest is ERC7726OracleFactoryTest {
    function test_whenOracleIsEnabled_cachePricesCachesAsset()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        // Seed an initial cache timestamp for comparison.
        priceModule.cachePrice(address(baseToken));
        (, uint48 oldTimestamp) = priceModule.getPrice(address(baseToken), IPRICEv2.Variant.LAST);

        vm.warp(block.timestamp + 1);
        clone.cachePrices(address(baseToken), address(quoteToken));

        (, uint48 newTimestamp) = priceModule.getPrice(address(baseToken), IPRICEv2.Variant.LAST);
        assertGt(newTimestamp, oldTimestamp, "Asset should be cached");
    }

    function test_whenOracleIsEnabled_cachePricesIfNecessaryDoesNotCacheWhenFresh()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceModule.cachePrice(address(baseToken));
        priceModule.cachePrice(address(quoteToken));
        (, uint48 oldTimestamp) = priceModule.getPrice(address(baseToken), IPRICEv2.Variant.LAST);

        vm.warp(block.timestamp + 1);
        clone.cachePricesIfNecessary(address(baseToken), address(quoteToken));

        (, uint48 newTimestamp) = priceModule.getPrice(address(baseToken), IPRICEv2.Variant.LAST);
        assertEq(newTimestamp, oldTimestamp, "Fresh cache should not be updated");
    }

    function test_whenOracleIsEnabled_cachePricesIfNecessaryCachesWhenStale()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceModule.cachePrice(address(baseToken));
        priceModule.cachePrice(address(quoteToken));
        (, uint48 oldTimestamp) = priceModule.getPrice(address(baseToken), IPRICEv2.Variant.LAST);

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        clone.cachePricesIfNecessary(address(baseToken), address(quoteToken));

        (, uint48 newTimestamp) = priceModule.getPrice(address(baseToken), IPRICEv2.Variant.LAST);
        assertGt(newTimestamp, oldTimestamp, "Stale cache should be updated");
    }

    function test_whenOracleMaxAgeIsZero_cachePricesIfNecessaryCachesWhenTimestampIsFromPriorBlock()
        public
        givenFactoryIsEnabled
    {
        address oracle = _createOracle(0);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceModule.cachePrice(address(baseToken));
        priceModule.cachePrice(address(quoteToken));
        (, uint48 oldBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        clone.cachePricesIfNecessary(address(baseToken), address(quoteToken));

        (, uint48 newBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        assertGt(newBaseTimestamp, oldBaseTimestamp, "maxAge=0 should recache base token");
        assertGt(newQuoteTimestamp, oldQuoteTimestamp, "maxAge=0 should recache quote token");
    }

    function test_whenOracleIsEnabled_cachePricesCachesBothAssets()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceModule.cachePrice(address(baseToken));
        priceModule.cachePrice(address(quoteToken));
        (, uint48 oldBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        clone.cachePrices(address(baseToken), address(quoteToken));

        (, uint48 newBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        assertGt(newBaseTimestamp, oldBaseTimestamp, "Base asset should be cached");
        assertGt(newQuoteTimestamp, oldQuoteTimestamp, "Quote asset should be cached");
    }

    function test_whenOracleIsEnabled_cachePricesIfNecessaryCachesBothWhenStale()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceModule.cachePrice(address(baseToken));
        priceModule.cachePrice(address(quoteToken));
        (, uint48 oldBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 oldQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        clone.cachePricesIfNecessary(address(baseToken), address(quoteToken));

        (, uint48 newBaseTimestamp) = priceModule.getPrice(
            address(baseToken),
            IPRICEv2.Variant.LAST
        );
        (, uint48 newQuoteTimestamp) = priceModule.getPrice(
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        assertGt(newBaseTimestamp, oldBaseTimestamp, "Base asset should be cached when stale");
        assertGt(newQuoteTimestamp, oldQuoteTimestamp, "Quote asset should be cached when stale");
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
        clone.cachePrices(address(baseToken), address(quoteToken));
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
        clone.cachePrices(address(baseToken), address(quoteToken));
    }

    function test_whenCallerIsNotFactoryOracle_cachePricesReverts() public givenFactoryIsEnabled {
        CachePriceCaller caller = new CachePriceCaller(IERC7726OracleFactory(address(factory)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_InvalidOracle.selector,
                address(caller)
            )
        );
        caller.cachePrices(address(baseToken), address(quoteToken));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
