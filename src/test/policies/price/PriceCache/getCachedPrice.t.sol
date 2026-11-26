// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheGetCachedPriceTest is PriceCacheTest {
    // Scenarios: PCACHE-GET-CACHED-L01.
    function test_whenPolicyDisabled_reverts() public {
        vm.prank(admin);
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.getCachedPrice(address(assetToken), address(quoteToken));
    }

    // Scenarios: PCACHE-GET-CACHED-P01.
    function test_givenPairIsCached_getCachedPrice_returnsSeparateUsdLegs() public {
        _cachePair();

        IPriceCache.CachedPrice memory assetQuote = cache.getCachedPrice(
            address(assetToken),
            address(quoteToken)
        );
        assertEq(assetQuote.assetPriceUsd, ASSET_PRICE_USD, "Asset leg should remain asset/USD");
        assertEq(assetQuote.quotePriceUsd, QUOTE_PRICE_USD, "Quote leg should remain quote/USD");

        IPriceCache.CachedPrice memory quoteAsset = cache.getCachedPrice(
            address(quoteToken),
            address(assetToken)
        );
        assertEq(
            quoteAsset.assetPriceUsd,
            QUOTE_PRICE_USD,
            "Reversed asset leg should flip orientation"
        );
        assertEq(
            quoteAsset.quotePriceUsd,
            ASSET_PRICE_USD,
            "Reversed quote leg should flip orientation"
        );
        assertEq(quoteAsset.updatedAt, assetQuote.updatedAt, "Pair timestamp should be shared");
        assertEq(quoteAsset.roundId, assetQuote.roundId, "Pair roundId should be shared");
    }

    // Scenarios: PCACHE-DEPENDENCIES-P03.
    function test_whenPRICEModuleIsUpgraded_invalidatesExistingSnapshots() public {
        _cachePair();
        IPriceCache.CachedPrice memory beforeUpgrade = _cachedPair();
        assertEq(beforeUpgrade.roundId, 1, "Round should exist before upgrade");

        _upgradePriceModuleAndReconfigure(18);

        _assertUncached(address(assetToken), address(quoteToken));
    }

    // Scenarios: PCACHE-GET-CACHED-I01.
    function test_whenAssetRemovedFromPRICE_reverts() public {
        _cachePair();
        priceModule.removeAsset(address(assetToken));

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(assetToken))
        );
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.getCachedPrice(address(assetToken), address(quoteToken));
    }

    // Scenarios: PCACHE-GET-CACHED-I02.
    function test_whenQuoteRemovedFromPRICE_reverts() public {
        _cachePair();
        priceModule.removeAsset(address(quoteToken));

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(quoteToken))
        );
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.getCachedPrice(address(assetToken), address(quoteToken));
    }

    // Scenarios: PCACHE-METADATA-P04.
    function test_whenUnitOfAccountDecimalsChange_invalidatesPairsInBothOrientations() public {
        address unitOfAccount = _unitOfAccount();
        _setNonContractAssetMetadata(unitOfAccount, 2, "NCA");

        cache.cachePrice(address(assetToken), unitOfAccount);

        IPriceCache.CachedPrice memory beforeUpdate = cache.getCachedPrice(
            address(assetToken),
            unitOfAccount
        );
        assertEq(beforeUpdate.roundId, 1, "Pair should be cached before invalidation");

        _setNonContractAssetMetadata(unitOfAccount, 3, "NCA");

        _assertUncached(address(assetToken), unitOfAccount);
        _assertUncached(unitOfAccount, address(assetToken));
    }

    // Scenarios: PCACHE-METADATA-P05.
    function test_whenRegisteredNonContractAssetDecimalsChange_invalidatesPairsInBothOrientations()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        priceModule.setPrice(nonContractAsset, NON_CONTRACT_PRICE_USD);
        _setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");

        cache.cachePrice(address(assetToken), nonContractAsset);

        IPriceCache.CachedPrice memory beforeUpdate = cache.getCachedPrice(
            address(assetToken),
            nonContractAsset
        );
        assertEq(beforeUpdate.roundId, 1, "Pair should be cached before invalidation");

        _setNonContractAssetMetadata(nonContractAsset, UPDATED_NON_CONTRACT_DECIMALS, "NCA");

        _assertUncached(address(assetToken), nonContractAsset);
        _assertUncached(nonContractAsset, address(assetToken));
    }

    // Scenarios: PCACHE-METADATA-P06.
    function test_whenUnrelatedNonContractAssetDecimalsChange_pairRemainsCached() public {
        address unitOfAccount = _unitOfAccount();
        address otherNonContractAsset = makeAddr("OTHER_NON_CONTRACT_ASSET");

        _registerNonContractAsset(otherNonContractAsset);
        priceModule.setPrice(otherNonContractAsset, NON_CONTRACT_PRICE_USD);
        _setNonContractAssetMetadata(unitOfAccount, 2, "NCA");
        _setNonContractAssetMetadata(otherNonContractAsset, NON_CONTRACT_DECIMALS, "NCA");

        cache.cachePrice(address(assetToken), unitOfAccount);

        IPriceCache.CachedPrice memory beforeUpdate = cache.getCachedPrice(
            address(assetToken),
            unitOfAccount
        );

        _setNonContractAssetMetadata(otherNonContractAsset, UPDATED_NON_CONTRACT_DECIMALS, "NCA");

        _assertCachedPriceEq(
            cache.getCachedPrice(address(assetToken), unitOfAccount),
            beforeUpdate
        );
    }

    // Scenarios: PCACHE-GET-CACHED-L02.
    function test_whenPolicyIsDeactivated_reverts() public {
        _deactivateCachePolicy();

        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.getCachedPrice(address(assetToken), address(quoteToken));
    }

    // Scenarios: PCACHE-GET-CACHED-I03.
    function test_whenAssetZero_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(0),
                address(quoteToken)
            )
        );
        vm.prank(caller_);
        cache.getCachedPrice(address(0), address(quoteToken));
    }

    // Scenarios: PCACHE-GET-CACHED-I04.
    function test_whenQuoteZero_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(assetToken),
                address(0)
            )
        );
        vm.prank(caller_);
        cache.getCachedPrice(address(assetToken), address(0));
    }

    // Scenarios: PCACHE-GET-CACHED-I05.
    function test_whenSamePair_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(assetToken),
                address(assetToken)
            )
        );
        vm.prank(caller_);
        cache.getCachedPrice(address(assetToken), address(assetToken));
    }

    // Scenarios: PCACHE-GET-CACHED-I06.
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
        cache.getCachedPrice(nca, address(quoteToken));
    }

    // Scenarios: PCACHE-GET-CACHED-I07.
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
        cache.getCachedPrice(address(assetToken), nca);
    }

    // Scenarios: PCACHE-GET-CACHED-L03.
    function test_givenInactivePaused_whenCalled_reverts(
        address caller_
    ) public givenCachePaused givenCacheInactive {
        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        vm.prank(caller_);
        cache.getCachedPrice(address(assetToken), address(quoteToken));
    }

    // Scenarios: PCACHE-GET-CACHED-L04.
    function test_givenReEnabled_whenCalled(address caller_) public givenCacheReEnabled {
        _cachePair();
        vm.prank(caller_);
        IPriceCache.CachedPrice memory snapshot = cache.getCachedPrice(
            address(assetToken),
            address(quoteToken)
        );
        assertEq(snapshot.assetPriceUsd, 2e18, "asset price restored");
        assertEq(snapshot.quotePriceUsd, 1e18, "quote price restored");
        assertEq(snapshot.roundId, 1, "exact round after restoration");
    }

    // Scenarios: PCACHE-GET-CACHED-L04.
    function test_givenReactivated_whenCalled(address caller_) public givenCacheReactivated {
        _cachePair();
        vm.prank(caller_);
        IPriceCache.CachedPrice memory snapshot = cache.getCachedPrice(
            address(assetToken),
            address(quoteToken)
        );
        assertEq(snapshot.assetPriceUsd, 2e18, "asset price restored");
        assertEq(snapshot.quotePriceUsd, 1e18, "quote price restored");
        assertEq(snapshot.roundId, 1, "exact round after restoration");
    }

    // Scenarios: PCACHE-GET-CACHED-P02.
    function test_whenUncachedPairReadAvoidsLivePrice(address caller_) public {
        vm.mockCallRevert(
            address(priceModule),
            abi.encodeWithSignature("getPrice(address,uint8)"),
            abi.encodeWithSelector(MetadataReadFailed.selector)
        );
        vm.prank(caller_);
        IPriceCache.CachedPrice memory snapshot = cache.getCachedPrice(
            address(assetToken),
            address(quoteToken)
        );
        IPriceCache.CachedPrice memory zero;
        _assertCachedPriceEq(snapshot, zero);
    }

    // Scenarios: PCACHE-GET-CACHED-P03.
    function test_whenStaleSnapshotRemainsReadable(address caller_) public {
        _cachePair();
        IPriceCache.CachedPrice memory beforeSnapshot = _cachedPair();
        vm.warp(uint256(beforeSnapshot.updatedAt) + 1 days);
        vm.prank(caller_);
        _assertCachedPriceEq(
            cache.getCachedPrice(address(assetToken), address(quoteToken)),
            beforeSnapshot
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
