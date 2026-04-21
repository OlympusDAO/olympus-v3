// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";
import {ERC7726OracleCloneable} from "src/policies/price/ERC7726OracleCloneable.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract CachePriceCaller {
    IERC7726OracleFactory public cache;

    constructor(IERC7726OracleFactory cache_) {
        cache = cache_;
    }

    function cachePrice(address base_, address quote_) external {
        cache.cachePrice(base_, quote_);
    }

    function cachePriceIfNecessary(address base_, address quote_, uint48 maxAge_) external {
        cache.cachePriceIfNecessary(base_, quote_, maxAge_);
    }
}

contract ERC7726OracleFactoryCachePriceTest is ERC7726OracleFactoryTest {
    function test_whenOracleIsEnabled_cachePricesCachesPair()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        (, uint48 oldTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        clone.cachePrice(address(baseToken), address(quoteToken));

        (, uint48 newTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        assertGt(newTimestamp, oldTimestamp, "Pair should be cached");
    }

    function test_whenOracleIsEnabled_cachePricesIfNecessaryDoesNotCacheWhenFresh()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceModule.cachePrice(address(baseToken), address(quoteToken));
        (, uint48 oldTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        clone.cachePriceIfNecessary(address(baseToken), address(quoteToken));

        (, uint48 newTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        assertEq(newTimestamp, oldTimestamp, "Fresh pair cache should not be updated");
    }

    function test_whenOracleIsEnabled_cachePricesIfNecessaryCachesWhenStale()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceModule.cachePrice(address(baseToken), address(quoteToken));
        (, uint48 oldTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        clone.cachePriceIfNecessary(address(baseToken), address(quoteToken));

        (, uint48 newTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        assertGt(newTimestamp, oldTimestamp, "Stale pair cache should be updated");
    }

    function test_whenOracleMaxAgeIsZero_cachePricesIfNecessaryCachesWhenTimestampIsFromPriorBlock()
        public
        givenFactoryIsEnabled
    {
        address oracle = _createOracle(0);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceModule.cachePrice(address(baseToken), address(quoteToken));
        (, uint48 oldPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        clone.cachePriceIfNecessary(address(baseToken), address(quoteToken));

        (, uint48 newPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        assertGt(newPairTimestamp, oldPairTimestamp, "maxAge=0 should recache pair timestamp");
    }

    function test_whenOracleIsEnabled_cachePricesCachesBothAssets()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        (, uint48 oldPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + 1);
        clone.cachePrice(address(baseToken), address(quoteToken));

        (, uint48 newPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        assertGt(newPairTimestamp, oldPairTimestamp, "Pair timestamp should be re-cached");
    }

    function test_whenOracleIsEnabled_cachePricesIfNecessaryCachesBothWhenStale()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceModule.cachePrice(address(baseToken), address(quoteToken));
        (, uint48 oldPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        clone.cachePriceIfNecessary(address(baseToken), address(quoteToken));

        (, uint48 newPairTimestamp) = priceModule.getPriceIn(
            address(baseToken),
            address(quoteToken),
            IPRICEv2.Variant.LAST
        );
        assertGt(
            newPairTimestamp,
            oldPairTimestamp,
            "Pair timestamp should be re-cached when stale"
        );
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
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
