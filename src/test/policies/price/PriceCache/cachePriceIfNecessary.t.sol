// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheCachePriceIfNecessaryTest is PriceCacheTest {
    using SafeCast for uint256;

    uint48 internal constant _MAX_CACHE_AGE = 1 hours;
    uint48 internal constant _MAX_STALE_DELTA = 365 days;
    uint256 internal constant _ASSET_PRICE = 2e18;
    uint256 internal constant _QUOTE_PRICE = 1e18;

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-L01.
    function test_whenPolicyDisabled_reverts() public {
        vm.prank(admin);
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        // Return data is unreachable because this call must revert.
        // forge-lint: disable-next-line(unused-return)
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), _MAX_CACHE_AGE);
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-L02.
    function test_whenPolicyIsDeactivated_reverts() public {
        _deactivateCachePolicy();

        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        // Return data is unreachable because this call must revert.
        // forge-lint: disable-next-line(unused-return)
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), _MAX_CACHE_AGE);
    }

    // when no snapshot exists
    //  then it caches and returns the pair
    // Scenarios: PCACHE-CACHE-IF-NECESSARY-P01.
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

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-P02.
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
    // Scenarios: PCACHE-CACHE-IF-NECESSARY-P03.
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
    // Scenarios: PCACHE-CACHE-IF-NECESSARY-N01.
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
    // Scenarios: PCACHE-CACHE-IF-NECESSARY-N02.
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
    // Scenarios: PCACHE-CACHE-IF-NECESSARY-N03.
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

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-P04.
    function test_whenSnapshotIsStale_recachesPair(uint48 staleDelta_) public {
        _cachePair();
        IPriceCache.CachedPrice memory before = _cachedPair();
        uint48 staleDelta = bound(uint256(staleDelta_), 1, _MAX_STALE_DELTA).toUint48();

        vm.warp(uint256(before.updatedAt) + _MAX_CACHE_AGE + uint256(staleDelta));
        priceModule.setTimestamp(vm.getBlockTimestamp().toUint48());
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
    // Scenarios: PCACHE-CACHE-IF-NECESSARY-T01.
    function test_givenSnapshotIsStale_whenPRICEReverts_revertsAndPreservesSnapshot() public {
        _cachePair();
        IPriceCache.CachedPrice memory before = _cachedPair();
        vm.warp(uint256(before.updatedAt) + _MAX_CACHE_AGE + 1);
        priceModule.setTimestamp(vm.getBlockTimestamp().toUint48());
        priceModule.setPrice(address(assetToken), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(assetToken))
        );
        // Return data is unreachable because this call must revert.
        // forge-lint: disable-next-line(unused-return)
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), _MAX_CACHE_AGE);

        _assertCachedPriceEq(_cachedPair(), before);
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-P05.
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

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-I01.
    function test_whenAssetZero_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(0),
                address(quoteToken)
            )
        );
        vm.prank(caller_);
        cache.cachePriceIfNecessary(address(0), address(quoteToken), 0);
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-I02.
    function test_whenQuoteZero_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(assetToken),
                address(0)
            )
        );
        vm.prank(caller_);
        cache.cachePriceIfNecessary(address(assetToken), address(0), 0);
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-I03.
    function test_whenSamePair_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(assetToken),
                address(assetToken)
            )
        );
        vm.prank(caller_);
        cache.cachePriceIfNecessary(address(assetToken), address(assetToken), 0);
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-I04.
    function test_whenAssetUnapproved_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        vm.prank(caller_);
        cache.cachePriceIfNecessary(unapprovedAsset, address(quoteToken), 0);
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-I05.
    function test_whenQuoteUnapproved_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        vm.prank(caller_);
        cache.cachePriceIfNecessary(address(assetToken), unapprovedAsset, 0);
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-I06.
    function test_whenAssetMetadataMissing_reverts(address caller_) public {
        address nca = makeAddr("MISSING_METADATA");
        _registerNonContractAsset(nca);
        priceModule.setPrice(nca, 3e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                nca
            )
        );
        vm.prank(caller_);
        cache.cachePriceIfNecessary(nca, address(quoteToken), 0);
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-I07.
    function test_whenQuoteMetadataMissing_reverts(address caller_) public {
        address nca = makeAddr("MISSING_METADATA");
        _registerNonContractAsset(nca);
        priceModule.setPrice(nca, 3e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                nca
            )
        );
        vm.prank(caller_);
        cache.cachePriceIfNecessary(address(assetToken), nca, 0);
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-L03.
    function test_givenInactivePaused_whenCalled_reverts(
        address caller_
    ) public givenCachePaused givenCacheInactive {
        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        vm.prank(caller_);
        cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), 0);
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-L04.
    function test_givenReEnabled_whenCalled(address caller_) public givenCacheReEnabled {
        vm.prank(caller_);
        IPriceCache.CachedPrice memory snapshot = cache.cachePriceIfNecessary(
            address(assetToken),
            address(quoteToken),
            0
        );
        assertEq(snapshot.assetPriceUsd, 2e18, "asset price restored");
        assertEq(snapshot.quotePriceUsd, 1e18, "quote price restored");
        assertEq(snapshot.roundId, 1, "exact round after restoration");
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-L04.
    function test_givenReactivated_whenCalled(address caller_) public givenCacheReactivated {
        vm.prank(caller_);
        IPriceCache.CachedPrice memory snapshot = cache.cachePriceIfNecessary(
            address(assetToken),
            address(quoteToken),
            0
        );
        assertEq(snapshot.assetPriceUsd, 2e18, "asset price restored");
        assertEq(snapshot.quotePriceUsd, 1e18, "quote price restored");
        assertEq(snapshot.roundId, 1, "exact round after restoration");
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-D01.
    function test_whenFreshHitAvoidsLivePrice() public {
        _cachePair();
        IPriceCache.CachedPrice memory beforeSnapshot = _cachedPair();
        vm.mockCallRevert(
            address(priceModule),
            abi.encodeWithSignature("getPrice(address,uint8)"),
            abi.encodeWithSelector(MetadataReadFailed.selector)
        );
        _assertCachedPriceEq(
            cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), type(uint48).max),
            beforeSnapshot
        );
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-N04.
    function test_whenFullRangeFreshnessHolds(
        address caller_,
        uint48 at_,
        uint48 age_,
        uint48 elapsed_
    ) public {
        uint48 observedAt = SafeCast.toUint48(bound(at_, 1, type(uint48).max));
        priceModule.setTimestamp(observedAt);
        _cachePair();
        IPriceCache.CachedPrice memory beforeSnapshot = _cachedPair();
        vm.warp(uint256(observedAt) + bound(elapsed_, 0, age_));
        vm.prank(caller_);
        _assertCachedPriceEq(
            cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), age_),
            beforeSnapshot
        );
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-N04.
    function test_whenFullRangeSnapshotIsFirstStale(address caller_, uint48 age_) public {
        priceModule.setTimestamp(1);
        _cachePair();
        vm.warp(uint256(age_) + 2);
        // The clock may exceed uint48; oracle observations still fit their declared type.
        priceModule.setTimestamp(2);
        vm.prank(caller_);
        IPriceCache.CachedPrice memory snapshot = cache.cachePriceIfNecessary(
            address(assetToken),
            address(quoteToken),
            age_
        );
        assertEq(snapshot.roundId, 2, "first stale instant recaches once");
        assertEq(snapshot.updatedAt, 2, "new oracle observation used");
    }

    // Scenarios: PCACHE-CACHE-IF-NECESSARY-N04.
    function test_whenAgeOneAtAndAfterDeadline() public {
        priceModule.setTimestamp(1);
        _cachePair();
        vm.warp(2);
        assertEq(
            cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), 1).roundId,
            1,
            "age one deadline remains fresh"
        );
        vm.warp(3);
        priceModule.setTimestamp(3);
        assertEq(
            cache.cachePriceIfNecessary(address(assetToken), address(quoteToken), 1).roundId,
            2,
            "first stale instant recaches"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
