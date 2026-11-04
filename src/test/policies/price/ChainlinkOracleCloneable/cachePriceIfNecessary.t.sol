// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {Actions} from "src/Kernel.sol";
import {ChainlinkOracleCloneable} from "src/policies/price/ChainlinkOracleCloneable.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {ChainlinkOracleCloneableTest} from "./ChainlinkOracleCloneableTest.sol";

contract ChainlinkOracleCloneableCachePriceIfNecessaryTest is ChainlinkOracleCloneableTest {
    function test_whenPricesAreFresh_cachePriceIfNecessaryDoesNotCache(uint48 warpDelta_) public {
        uint256 initialCacheCalls = priceCache.cachePriceCallCount();
        priceCache.cachePrice(address(baseToken), address(quoteToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(baseToken), address(quoteToken))
            .updatedAt;
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));

        vm.warp(uint256(cachedAt) + uint256(warpDelta));
        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();

        assertEq(
            priceCache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(
            priceCache.cachePriceCallCount(),
            initialCacheCalls + 1,
            "Fresh cache should not be re-cached"
        );
    }

    function test_whenPricesAreStale_cachePriceIfNecessaryCaches(uint48 warpDelta_) public {
        uint256 initialCacheCalls = priceCache.cachePriceCallCount();
        priceCache.cachePrice(address(baseToken), address(quoteToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(baseToken), address(quoteToken))
            .updatedAt;
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );

        vm.warp(uint256(cachedAt) + uint256(warpDelta));
        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();

        assertEq(
            priceCache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(
            priceCache.cachePriceCallCount(),
            initialCacheCalls + 2,
            "Stale cache should be re-cached"
        );
    }

    function test_whenOracleMaxAgeIsZero_cachePriceIfNecessaryCachesWhenTimestampIsFromPriorBlock()
        public
    {
        uint256 initialCacheCalls = priceCache.cachePriceCallCount();
        address zeroMaxAgeOracleAddress = _createOracle(address(baseToken), address(quoteToken), 0);
        ChainlinkOracleCloneable zeroMaxAgeOracle = ChainlinkOracleCloneable(
            zeroMaxAgeOracleAddress
        );

        priceCache.cachePrice(address(baseToken), address(quoteToken));

        vm.warp(block.timestamp + 1);
        zeroMaxAgeOracle.cachePriceIfNecessary();

        assertEq(
            priceCache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(
            priceCache.cachePriceCallCount(),
            initialCacheCalls + 3,
            "maxAge=0 should recache pair"
        );
    }

    function test_whenFactoryPolicyIsDeactivated_reverts() public {
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));

        vm.expectRevert(IOracleFactory.OracleFactory_PolicyNotActive.selector);
        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();
    }

    function test_whenOnlyBaseUsdCacheChanges_cachePriceIfNecessaryDoesNotRecachePair() public {
        address unitOfAccount = UNIT_OF_ACCOUNT;
        priceCache.setUsdPrice(unitOfAccount, 1e18);

        priceCache.cachePrice(address(baseToken), address(quoteToken));
        IPriceCache.CachedPrice memory oldPair = priceCache.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );

        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(baseToken), 3e18);
        priceCache.cachePrice(address(baseToken), unitOfAccount);

        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();

        IPriceCache.CachedPrice memory newPair = priceCache.getCachedPrice(
            address(baseToken),
            address(quoteToken)
        );
        assertEq(
            priceCache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(newPair.roundId, oldPair.roundId, "Pair round should remain unchanged");
        assertEq(
            newPair.updatedAt,
            oldPair.updatedAt,
            "Direct pair timestamp should remain unchanged"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
