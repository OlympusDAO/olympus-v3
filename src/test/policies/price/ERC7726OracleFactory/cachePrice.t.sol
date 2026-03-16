// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";
import {ERC7726OracleCloneable} from "src/policies/price/ERC7726OracleCloneable.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

contract CachePriceCaller {
    IPriceCache public cache;

    constructor(IPriceCache cache_) {
        cache = cache_;
    }

    function cachePrice(address asset_) external {
        cache.cachePrice(asset_);
    }

    function cachePriceIfNecessary(address asset_) external {
        cache.cachePriceIfNecessary(asset_, false);
    }
}

contract ERC7726OracleFactoryCachePriceTest is ERC7726OracleFactoryTest {
    function test_whenOracleIsEnabled_cachePriceCachesAsset()
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
        clone.cachePrice(address(baseToken));

        (, uint48 newTimestamp) = priceModule.getPrice(address(baseToken), IPRICEv2.Variant.LAST);
        assertGt(newTimestamp, oldTimestamp, "Asset should be cached");
    }

    function test_whenOracleIsEnabled_cachePriceIfNecessaryDoesNotCacheWhenFresh()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceModule.cachePrice(address(baseToken));
        (, uint48 oldTimestamp) = priceModule.getPrice(address(baseToken), IPRICEv2.Variant.LAST);

        vm.warp(block.timestamp + 1);
        clone.cachePriceIfNecessary(address(baseToken));

        (, uint48 newTimestamp) = priceModule.getPrice(address(baseToken), IPRICEv2.Variant.LAST);
        assertEq(newTimestamp, oldTimestamp, "Fresh cache should not be updated");
    }

    function test_whenOracleIsEnabled_cachePriceIfNecessaryCachesWhenStale()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        priceModule.cachePrice(address(baseToken));
        (, uint48 oldTimestamp) = priceModule.getPrice(address(baseToken), IPRICEv2.Variant.LAST);

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        clone.cachePriceIfNecessary(address(baseToken));

        (, uint48 newTimestamp) = priceModule.getPrice(address(baseToken), IPRICEv2.Variant.LAST);
        assertGt(newTimestamp, oldTimestamp, "Stale cache should be updated");
    }

    function test_whenOracleIsDisabled_cachePriceReverts()
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
        clone.cachePrice(address(baseToken));
    }

    function test_whenFactoryIsDisabled_cachePriceReverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenFactoryIsDisabled
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        ERC7726OracleCloneable clone = ERC7726OracleCloneable(oracle);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        clone.cachePrice(address(baseToken));
    }

    function test_whenCallerIsNotFactoryOracle_cachePriceReverts() public givenFactoryIsEnabled {
        CachePriceCaller caller = new CachePriceCaller(IPriceCache(address(factory)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_InvalidOracle.selector,
                address(caller)
            )
        );
        caller.cachePrice(address(baseToken));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
