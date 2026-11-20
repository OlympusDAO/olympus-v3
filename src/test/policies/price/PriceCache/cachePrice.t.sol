// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheCachePriceTest is PriceCacheTest {
    uint80 internal constant THIRD_ROUND_ID = 3;

    // Scenarios: PCACHE-CACHE-L01.
    function test_whenPolicyDisabled_reverts() public {
        vm.prank(admin);
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        cache.cachePrice(address(assetToken), address(quoteToken));
    }

    // Scenarios: PCACHE-CACHE-L02.
    function test_whenPolicyIsDeactivated_reverts() public {
        _deactivateCachePolicy();

        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        cache.cachePrice(address(assetToken), address(quoteToken));
    }

    // Scenarios: PCACHE-CACHE-I03.
    function test_whenAssetAndQuoteAreSame_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(assetToken),
                address(assetToken)
            )
        );
        cache.cachePrice(address(assetToken), address(assetToken));
    }

    // Scenarios: PCACHE-CACHE-I01.
    function test_whenAssetIsZeroAddress_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(0),
                address(quoteToken)
            )
        );
        cache.cachePrice(address(0), address(quoteToken));
    }

    // Scenarios: PCACHE-CACHE-I02.
    function test_whenQuoteIsZeroAddress_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(assetToken),
                address(0)
            )
        );
        cache.cachePrice(address(assetToken), address(0));
    }

    // Scenarios: PCACHE-CACHE-I04.
    function test_whenAssetIsUnapproved_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        cache.cachePrice(unapprovedAsset, address(quoteToken));
    }

    // Scenarios: PCACHE-CACHE-I05.
    function test_whenQuoteIsUnapproved_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        cache.cachePrice(address(assetToken), unapprovedAsset);
    }

    // Scenarios: PCACHE-CACHE-I06.
    function test_whenBothAssetsAreUnapproved_reverts() public {
        address unapprovedQuote = makeAddr("UNAPPROVED_QUOTE");

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        cache.cachePrice(unapprovedAsset, unapprovedQuote);
    }

    // Scenarios: PCACHE-CACHE-P01.
    function test_whenPairIsValid_cachesSnapshotAndIncrementsRoundId() public {
        cache.cachePrice(address(assetToken), address(quoteToken));
        IPriceCache.CachedPrice memory firstSnapshot = _cachedPair();
        assertEq(firstSnapshot.assetPriceUsd, ASSET_PRICE_USD, "Asset leg should be cached");
        assertEq(firstSnapshot.quotePriceUsd, QUOTE_PRICE_USD, "Quote leg should be cached");
        assertGt(firstSnapshot.updatedAt, 0, "updatedAt should be set");
        assertEq(firstSnapshot.roundId, 1, "roundId should start at 1");

        vm.warp(vm.getBlockTimestamp() + 1);
        _setPriceTimestampAtCurrentBlock();
        cache.cachePrice(address(assetToken), address(quoteToken));
        IPriceCache.CachedPrice memory secondSnapshot = _cachedPair();
        assertEq(secondSnapshot.roundId, 2, "roundId should increment on each write");
        assertGt(secondSnapshot.updatedAt, firstSnapshot.updatedAt, "updatedAt should advance");
    }

    // Scenarios: PCACHE-CACHE-P02.
    function test_whenCachedMultipleTimes_updatesRoundTimestampAndBothDirections() public {
        cache.cachePrice(address(assetToken), address(quoteToken));
        IPriceCache.CachedPrice memory firstAssetQuote = cache.getCachedPrice(
            address(assetToken),
            address(quoteToken)
        );
        IPriceCache.CachedPrice memory firstQuoteAsset = cache.getCachedPrice(
            address(quoteToken),
            address(assetToken)
        );
        assertEq(firstAssetQuote.roundId, 1, "Forward round should start at 1");
        assertEq(firstQuoteAsset.roundId, 1, "Reverse round should share the same round");
        assertEq(
            firstAssetQuote.updatedAt,
            firstQuoteAsset.updatedAt,
            "Pair timestamp should match"
        );
        assertEq(
            firstQuoteAsset.assetPriceUsd,
            QUOTE_PRICE_USD,
            "Reverse asset leg should flip orientation"
        );
        assertEq(
            firstQuoteAsset.quotePriceUsd,
            ASSET_PRICE_USD,
            "Reverse quote leg should flip orientation"
        );

        vm.warp(vm.getBlockTimestamp() + 5);
        _setPriceTimestampAtCurrentBlock();
        cache.cachePrice(address(assetToken), address(quoteToken));
        IPriceCache.CachedPrice memory secondAssetQuote = cache.getCachedPrice(
            address(assetToken),
            address(quoteToken)
        );
        IPriceCache.CachedPrice memory secondQuoteAsset = cache.getCachedPrice(
            address(quoteToken),
            address(assetToken)
        );
        assertEq(secondAssetQuote.roundId, 2, "Forward round should increment to 2");
        assertEq(secondQuoteAsset.roundId, 2, "Reverse round should increment to 2");
        assertGt(secondAssetQuote.updatedAt, firstAssetQuote.updatedAt, "Timestamp should advance");
        assertEq(
            secondAssetQuote.updatedAt,
            secondQuoteAsset.updatedAt,
            "Forward and reverse timestamps should match"
        );

        vm.warp(vm.getBlockTimestamp() + 7);
        _setPriceTimestampAtCurrentBlock();
        cache.cachePrice(address(quoteToken), address(assetToken));
        IPriceCache.CachedPrice memory thirdAssetQuote = cache.getCachedPrice(
            address(assetToken),
            address(quoteToken)
        );
        IPriceCache.CachedPrice memory thirdQuoteAsset = cache.getCachedPrice(
            address(quoteToken),
            address(assetToken)
        );
        assertEq(
            thirdAssetQuote.roundId,
            THIRD_ROUND_ID,
            "Forward round should increment from reverse writes"
        );
        assertEq(
            thirdQuoteAsset.roundId,
            THIRD_ROUND_ID,
            "Reverse round should share incremented round"
        );
        assertGt(
            thirdAssetQuote.updatedAt,
            secondAssetQuote.updatedAt,
            "Timestamp should keep advancing"
        );
        assertEq(
            thirdAssetQuote.assetPriceUsd,
            ASSET_PRICE_USD,
            "Forward orientation should remain correct"
        );
        assertEq(
            thirdAssetQuote.quotePriceUsd,
            QUOTE_PRICE_USD,
            "Forward orientation should remain correct"
        );
        assertEq(
            thirdQuoteAsset.assetPriceUsd,
            QUOTE_PRICE_USD,
            "Reverse orientation should remain correct"
        );
        assertEq(
            thirdQuoteAsset.quotePriceUsd,
            ASSET_PRICE_USD,
            "Reverse orientation should remain correct"
        );
    }

    // Scenarios: PCACHE-CACHE-P03.
    function test_whenAssetIsUnitOfAccount_cachesUnitPriceAsAssetLeg() public {
        address unitOfAccount = _unitOfAccount();

        cache.cachePrice(unitOfAccount, address(assetToken));
        IPriceCache.CachedPrice memory snapshot = cache.getCachedPrice(
            unitOfAccount,
            address(assetToken)
        );

        assertEq(
            snapshot.assetPriceUsd,
            QUOTE_PRICE_USD,
            "Unit-of-account should be cached at 1e18"
        );
        assertEq(snapshot.quotePriceUsd, ASSET_PRICE_USD, "Quote leg should use token USD price");
        assertEq(snapshot.roundId, 1, "Round should increment on successful write");
        assertGt(snapshot.updatedAt, 0, "Timestamp should be set");
    }

    // Scenarios: PCACHE-CACHE-P04.
    function test_whenQuoteIsUnitOfAccount_cachesUnitPriceAsQuoteLeg() public {
        address unitOfAccount = _unitOfAccount();

        cache.cachePrice(address(assetToken), unitOfAccount);
        IPriceCache.CachedPrice memory snapshot = cache.getCachedPrice(
            address(assetToken),
            unitOfAccount
        );

        assertEq(snapshot.assetPriceUsd, ASSET_PRICE_USD, "Asset leg should use token USD price");
        assertEq(
            snapshot.quotePriceUsd,
            QUOTE_PRICE_USD,
            "Unit-of-account should be cached at 1e18"
        );
        assertEq(snapshot.roundId, 1, "Round should increment on successful write");
        assertGt(snapshot.updatedAt, 0, "Timestamp should be set");
    }

    // Scenarios: PCACHE-CACHE-L03.
    function test_givenInactivePaused_whenCalled_reverts(
        address caller_
    ) public givenCachePaused givenCacheInactive {
        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        vm.prank(caller_);
        cache.cachePrice(address(assetToken), address(quoteToken));
    }

    // Scenarios: PCACHE-CACHE-L04.
    function test_givenReEnabled_whenCalled(address caller_) public givenCacheReEnabled {
        vm.prank(caller_);
        cache.cachePrice(address(assetToken), address(quoteToken));
        IPriceCache.CachedPrice memory snapshot = _cachedPair();
        assertEq(snapshot.assetPriceUsd, 2e18, "asset price restored");
        assertEq(snapshot.quotePriceUsd, 1e18, "quote price restored");
        assertEq(snapshot.roundId, 1, "exact round after restoration");
    }

    // Scenarios: PCACHE-CACHE-L04.
    function test_givenReactivated_whenCalled(address caller_) public givenCacheReactivated {
        vm.prank(caller_);
        cache.cachePrice(address(assetToken), address(quoteToken));
        IPriceCache.CachedPrice memory snapshot = _cachedPair();
        assertEq(snapshot.assetPriceUsd, 2e18, "asset price restored");
        assertEq(snapshot.quotePriceUsd, 1e18, "quote price restored");
        assertEq(snapshot.roundId, 1, "exact round after restoration");
    }

    // Scenarios: PCACHE-CACHE-A01.
    function test_whenAnyCallerCachesValidPair(address caller_) public {
        vm.prank(caller_);
        cache.cachePrice(address(assetToken), address(quoteToken));
        IPriceCache.CachedPrice memory snapshot = _cachedPair();
        assertEq(snapshot.assetPriceUsd, 2e18, "exact asset price");
        assertEq(snapshot.quotePriceUsd, 1e18, "exact quote price");
        assertEq(snapshot.roundId, 1, "one cache write");
    }

    // Scenarios: PCACHE-CACHE-N01.
    function test_whenObservationTimesVaryIndependently(uint48 assetAt_, uint48 quoteAt_) public {
        vm.mockCall(
            address(priceModule),
            abi.encodeWithSignature("getPrice(address,uint8)", address(assetToken), uint8(0)),
            abi.encode(uint256(2e18), assetAt_)
        );
        vm.mockCall(
            address(priceModule),
            abi.encodeWithSignature("getPrice(address,uint8)", address(quoteToken), uint8(0)),
            abi.encode(uint256(1e18), quoteAt_)
        );
        cache.cachePrice(address(assetToken), address(quoteToken));
        assertEq(
            _cachedPair().updatedAt,
            assetAt_ < quoteAt_ ? assetAt_ : quoteAt_,
            "older leg owns observation timestamp"
        );
    }

    // Scenarios: PCACHE-CACHE-D01.
    function test_whenPriceReadFails_preservesSnapshot() public {
        _cachePair();
        IPriceCache.CachedPrice memory beforeSnapshot = _cachedPair();
        vm.mockCallRevert(
            address(priceModule),
            abi.encodeWithSignature("getPrice(address,uint8)", address(assetToken), uint8(0)),
            abi.encodeWithSelector(MetadataReadFailed.selector)
        );
        vm.expectRevert(MetadataReadFailed.selector);
        cache.cachePrice(address(assetToken), address(quoteToken));
        _assertCachedPriceEq(_cachedPair(), beforeSnapshot);
    }

    // Scenarios: PCACHE-CACHE-D02.
    function test_whenRequiredDecimalsAreMissing_reverts() public {
        address nca = makeAddr("MISSING_METADATA");
        _registerNonContractAsset(nca);
        priceModule.setPrice(nca, 3e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                nca
            )
        );
        cache.cachePrice(nca, address(quoteToken));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
