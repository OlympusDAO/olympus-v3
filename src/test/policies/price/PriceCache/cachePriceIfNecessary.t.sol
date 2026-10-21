// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheCachePriceIfNecessaryTest is PriceCacheTest {
    using SafeCast for uint256;

    uint48 internal constant _MAX_CACHE_AGE = 1 hours;
    uint48 internal constant _MAX_STALE_DELTA = 365 days;
    uint256 internal constant _ASSET_PRICE = 2e18;
    uint256 internal constant _QUOTE_PRICE = 1e18;

    function test_whenPolicyDisabled_reverts() public {
        vm.prank(admin);
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        // Return data is unreachable because this call must revert.
        // forge-lint: disable-next-line(unused-return)
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), _MAX_CACHE_AGE);
    }

    function test_whenPolicyIsDeactivated_reverts() public {
        _deactivateCachePolicy();

        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        // Return data is unreachable because this call must revert.
        // forge-lint: disable-next-line(unused-return)
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), _MAX_CACHE_AGE);
    }

    // when no snapshot exists
    //  then it caches and returns the pair
    function test_whenNoSnapshotExists_cachesPair(address caller_) public {
        vm.prank(caller_);
        IPriceCache.CachedPrice memory returned = cache.cachePriceIfNecessary(
            address(assetToken),
            address(quoteToken),
            _MAX_CACHE_AGE
        );

        IPriceCache.CachedPrice memory snapshot = _cachedPair();
        _assertCachedPriceEq(returned, snapshot);
        assertEq(snapshot.assetPriceUsd, _ASSET_PRICE, "Asset leg should be cached");
        assertEq(snapshot.quotePriceUsd, _QUOTE_PRICE, "Quote leg should be cached");
        assertEq(snapshot.roundId, 1, "roundId should increment on write");
        assertGt(snapshot.updatedAt, 0, "updatedAt should be set");
    }

    function test_whenSnapshotIsFresh_doesNotRecache(uint48 elapsed_) public {
        _cachePair();
        IPriceCache.CachedPrice memory before = _cachedPair();
        uint48 elapsed = bound(uint256(elapsed_), 0, _MAX_CACHE_AGE).toUint48();

        vm.warp(uint256(before.updatedAt) + uint256(elapsed));
        IPriceCache.CachedPrice memory returned = cache.cachePriceIfNecessary(
            address(assetToken),
            address(quoteToken),
            _MAX_CACHE_AGE
        );

        IPriceCache.CachedPrice memory after_ = _cachedPair();
        _assertCachedPriceEq(returned, before);
        _assertCachedPriceEq(returned, after_);
        assertEq(after_.roundId, before.roundId, "roundId should not change for fresh cache");
        assertEq(after_.updatedAt, before.updatedAt, "timestamp should not change for fresh cache");
    }

    // given the snapshot is fresh
    //  when pair is reversed
    //   then it returns the existing snapshot
    function test_givenSnapshotIsFresh_whenPairIsReversed_returnsExistingSnapshot() public {
        _cachePair();
        IPriceCache.CachedPrice memory expected = cache.getCachedPrice(
            address(quoteToken),
            address(assetToken)
        );

        IPriceCache.CachedPrice memory returned = cache.cachePriceIfNecessary(
            address(quoteToken),
            address(assetToken),
            _MAX_CACHE_AGE
        );

        _assertCachedPriceEq(returned, expected);
        assertEq(returned.assetPriceUsd, _QUOTE_PRICE, "reversed asset price");
        assertEq(returned.quotePriceUsd, _ASSET_PRICE, "reversed quote price");
    }

    // given the snapshot is exactly max age old
    //  when the pair cache is requested
    //   then it returns the existing snapshot
    function test_givenSnapshotIsExactlyMaxAgeOld_returnsExistingSnapshot() public {
        _cachePair();
        IPriceCache.CachedPrice memory before = _cachedPair();
        vm.warp(uint256(before.updatedAt) + _MAX_CACHE_AGE);

        IPriceCache.CachedPrice memory returned = cache.cachePriceIfNecessary(
            address(assetToken),
            address(quoteToken),
            _MAX_CACHE_AGE
        );

        _assertCachedPriceEq(returned, before);
    }

    // given the snapshot is current
    //  when max age is zero
    //   then it returns the existing snapshot
    function test_givenSnapshotIsCurrent_whenMaxAgeIsZero_returnsExistingSnapshot() public {
        _cachePair();
        IPriceCache.CachedPrice memory before = _cachedPair();

        IPriceCache.CachedPrice memory returned = cache.cachePriceIfNecessary(
            address(assetToken),
            address(quoteToken),
            0
        );

        _assertCachedPriceEq(returned, before);
    }

    // given a snapshot exists
    //  when max age is maximum
    //   then it returns the existing snapshot
    function test_givenSnapshotExists_whenMaxAgeIsMaximum_returnsExistingSnapshot() public {
        _cachePair();
        IPriceCache.CachedPrice memory before = _cachedPair();

        IPriceCache.CachedPrice memory returned = cache.cachePriceIfNecessary(
            address(assetToken),
            address(quoteToken),
            type(uint48).max
        );

        _assertCachedPriceEq(returned, before);
    }

    function test_whenSnapshotIsStale_recachesPair(uint48 staleDelta_) public {
        _cachePair();
        IPriceCache.CachedPrice memory before = _cachedPair();
        uint48 staleDelta = bound(uint256(staleDelta_), 1, _MAX_STALE_DELTA).toUint48();

        vm.warp(uint256(before.updatedAt) + _MAX_CACHE_AGE + uint256(staleDelta));
        priceModule.setTimestamp(block.timestamp.toUint48());
        IPriceCache.CachedPrice memory returned = cache.cachePriceIfNecessary(
            address(assetToken),
            address(quoteToken),
            _MAX_CACHE_AGE
        );

        IPriceCache.CachedPrice memory after_ = _cachedPair();
        _assertCachedPriceEq(returned, after_);
        assertEq(after_.roundId, before.roundId + 1, "roundId should increment when recached");
        assertGt(after_.updatedAt, before.updatedAt, "timestamp should advance when recached");
    }

    // given the snapshot is stale
    //  when PRICE reverts
    //   then it reverts and preserves the snapshot
    function test_givenSnapshotIsStale_whenPRICEReverts_revertsAndPreservesSnapshot() public {
        _cachePair();
        IPriceCache.CachedPrice memory before = _cachedPair();
        vm.warp(uint256(before.updatedAt) + _MAX_CACHE_AGE + 1);
        priceModule.setTimestamp(block.timestamp.toUint48());
        priceModule.setPrice(address(assetToken), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(assetToken))
        );
        // Return data is unreachable because this call must revert.
        // forge-lint: disable-next-line(unused-return)
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), _MAX_CACHE_AGE);

        _assertCachedPriceEq(_cachedPair(), before);
    }

    function test_whenPRICEModuleIsUpgraded_invalidatedPairRecachesOnDemand() public {
        _cachePair();
        _upgradePriceModuleAndReconfigure(18);

        IPriceCache.CachedPrice memory returned = cache.cachePriceIfNecessary(
            address(assetToken),
            address(quoteToken),
            _MAX_STALE_DELTA
        );
        IPriceCache.CachedPrice memory snapshot = _cachedPair();

        _assertCachedPriceEq(returned, snapshot);
        assertEq(snapshot.roundId, 1, "Round should restart from one after invalidation");
        assertEq(snapshot.assetPriceUsd, 4e18, "Asset leg should use upgraded module price");
        assertEq(
            snapshot.quotePriceUsd,
            _ASSET_PRICE,
            "Quote leg should use upgraded module price"
        );
        assertGt(snapshot.updatedAt, 0, "Timestamp should be set after recache");
    }

    // when version is queried
    //  then it returns version 1.0
    function test_VERSION_returnsOneZero() public view {
        (uint8 major, uint8 minor) = cache.VERSION();

        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
