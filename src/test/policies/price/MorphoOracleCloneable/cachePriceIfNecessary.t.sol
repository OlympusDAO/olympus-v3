// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {Actions} from "src/Kernel.sol";
import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";

contract MorphoOracleCloneableCachePriceIfNecessaryTest is MorphoOracleCloneableTest {
    function test_whenPricesAreFresh_cachePricesIfNecessaryDoesNotCache(uint48 warpDelta_) public {
        uint256 initialCacheCalls = priceCache.cachePriceCallCount();
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));

        vm.warp(uint256(cachedAt) + uint256(warpDelta));
        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

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

    function test_whenPricesAreStale_cachePricesIfNecessaryCaches(uint48 warpDelta_) public {
        uint256 initialCacheCalls = priceCache.cachePriceCallCount();
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );

        vm.warp(uint256(cachedAt) + uint256(warpDelta));
        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

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

    function test_whenFactoryPolicyIsDeactivated_reverts() public {
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));

        vm.expectRevert(IOracleFactory.OracleFactory_PolicyNotActive.selector);
        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();
    }

    function test_whenOnlyCollateralUsdCacheChanges_cachePricesIfNecessaryDoesNotRecachePair()
        public
    {
        priceCache.setUsdPrice(UNIT_OF_ACCOUNT, 1e18);

        priceCache.cachePrice(address(collateralToken), address(loanToken));
        IPriceCache.CachedPrice memory oldPair = priceCache.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(collateralToken), 3e18);
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);

        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

        IPriceCache.CachedPrice memory newPair = priceCache.getCachedPrice(
            address(collateralToken),
            address(loanToken)
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

    function test_whenOnlyLoanUsdCacheChanges_cachePricesIfNecessaryDoesNotRecachePair() public {
        priceCache.setUsdPrice(UNIT_OF_ACCOUNT, 1e18);

        priceCache.cachePrice(address(collateralToken), address(loanToken));
        IPriceCache.CachedPrice memory oldPair = priceCache.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(loanToken), 2e18);
        priceCache.cachePrice(address(loanToken), UNIT_OF_ACCOUNT);

        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

        IPriceCache.CachedPrice memory newPair = priceCache.getCachedPrice(
            address(collateralToken),
            address(loanToken)
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
