// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheCachePriceIfNecessaryTest is PriceCacheTest {
    function test_whenPolicyDisabled_reverts() public {
        vm.prank(admin);
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), 1 hours);
    }

    function test_whenPolicyIsDeactivated_reverts() public {
        _deactivateCachePolicy();

        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), 1 hours);
    }

    function test_whenNoSnapshotExists_cachesPair() public {
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), 1 hours);

        IPriceCache.CachedPrice memory snapshot = _cachedPair();
        assertEq(snapshot.assetPriceUsd, 2e18, "Asset leg should be cached");
        assertEq(snapshot.quotePriceUsd, 1e18, "Quote leg should be cached");
        assertEq(snapshot.roundId, 1, "roundId should increment on write");
        assertGt(snapshot.updatedAt, 0, "updatedAt should be set");
    }

    function test_whenSnapshotIsFresh_doesNotRecache(uint48 elapsed_) public {
        _cachePair();
        IPriceCache.CachedPrice memory before = _cachedPair();
        uint48 elapsed = uint48(bound(uint256(elapsed_), 0, 1 hours));

        vm.warp(uint256(before.updatedAt) + uint256(elapsed));
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), 1 hours);

        IPriceCache.CachedPrice memory after_ = _cachedPair();
        assertEq(after_.roundId, before.roundId, "roundId should not change for fresh cache");
        assertEq(after_.updatedAt, before.updatedAt, "timestamp should not change for fresh cache");
    }

    function test_whenSnapshotIsStale_recachesPair(uint48 staleDelta_) public {
        _cachePair();
        IPriceCache.CachedPrice memory before = _cachedPair();
        uint48 staleDelta = uint48(bound(uint256(staleDelta_), 1, 365 days));

        vm.warp(uint256(before.updatedAt) + 1 hours + uint256(staleDelta));
        priceModule.setTimestamp(uint48(block.timestamp));
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), 1 hours);

        IPriceCache.CachedPrice memory after_ = _cachedPair();
        assertEq(after_.roundId, before.roundId + 1, "roundId should increment when recached");
        assertGt(after_.updatedAt, before.updatedAt, "timestamp should advance when recached");
    }

    function test_whenPRICEModuleIsUpgraded_invalidatedPairRecachesOnDemand() public {
        _cachePair();
        _upgradePriceModuleAndReconfigure(18);

        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), 365 days);
        IPriceCache.CachedPrice memory snapshot = _cachedPair();

        assertEq(snapshot.roundId, 1, "Round should restart from one after invalidation");
        assertEq(snapshot.assetPriceUsd, 4e18, "Asset leg should use upgraded module price");
        assertEq(snapshot.quotePriceUsd, 2e18, "Quote leg should use upgraded module price");
        assertGt(snapshot.updatedAt, 0, "Timestamp should be set after recache");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
