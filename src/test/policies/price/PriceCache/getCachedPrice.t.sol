// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheGetCachedPriceTest is PriceCacheTest {
    function test_whenPolicyDisabled_reverts() public {
        vm.prank(admin);
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.getCachedPrice(address(assetToken), address(quoteToken));
    }

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

    function test_whenPRICEModuleIsUpgraded_invalidatesExistingSnapshots() public {
        _cachePair();
        IPriceCache.CachedPrice memory beforeUpgrade = _cachedPair();
        assertEq(beforeUpgrade.roundId, 1, "Round should exist before upgrade");

        _upgradePriceModuleAndReconfigure(18);

        IPriceCache.CachedPrice memory afterUpgrade = _cachedPair();
        assertEq(afterUpgrade.assetPriceUsd, 0, "Asset leg should be invalidated");
        assertEq(afterUpgrade.quotePriceUsd, 0, "Quote leg should be invalidated");
        assertEq(afterUpgrade.updatedAt, 0, "Timestamp should be invalidated");
        assertEq(afterUpgrade.roundId, 0, "Round should be invalidated");
    }

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

        IPriceCache.CachedPrice memory forward = cache.getCachedPrice(
            address(assetToken),
            unitOfAccount
        );
        IPriceCache.CachedPrice memory reverse = cache.getCachedPrice(
            unitOfAccount,
            address(assetToken)
        );

        assertEq(forward.assetPriceUsd, 0, "Forward asset leg should be invalidated");
        assertEq(forward.quotePriceUsd, 0, "Forward quote leg should be invalidated");
        assertEq(forward.updatedAt, 0, "Forward timestamp should be invalidated");
        assertEq(forward.roundId, 0, "Forward round should be invalidated");

        assertEq(reverse.assetPriceUsd, 0, "Reverse asset leg should be invalidated");
        assertEq(reverse.quotePriceUsd, 0, "Reverse quote leg should be invalidated");
        assertEq(reverse.updatedAt, 0, "Reverse timestamp should be invalidated");
        assertEq(reverse.roundId, 0, "Reverse round should be invalidated");
    }

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

        IPriceCache.CachedPrice memory forward = cache.getCachedPrice(
            address(assetToken),
            nonContractAsset
        );
        IPriceCache.CachedPrice memory reverse = cache.getCachedPrice(
            nonContractAsset,
            address(assetToken)
        );

        assertEq(forward.assetPriceUsd, 0, "Forward asset leg should be invalidated");
        assertEq(forward.quotePriceUsd, 0, "Forward quote leg should be invalidated");
        assertEq(forward.updatedAt, 0, "Forward timestamp should be invalidated");
        assertEq(forward.roundId, 0, "Forward round should be invalidated");

        assertEq(reverse.assetPriceUsd, 0, "Reverse asset leg should be invalidated");
        assertEq(reverse.quotePriceUsd, 0, "Reverse quote leg should be invalidated");
        assertEq(reverse.updatedAt, 0, "Reverse timestamp should be invalidated");
        assertEq(reverse.roundId, 0, "Reverse round should be invalidated");
    }

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

        IPriceCache.CachedPrice memory afterUpdate = cache.getCachedPrice(
            address(assetToken),
            unitOfAccount
        );

        assertEq(
            afterUpdate.assetPriceUsd,
            beforeUpdate.assetPriceUsd,
            "Asset leg should remain cached for unrelated decimals changes"
        );
        assertEq(
            afterUpdate.quotePriceUsd,
            beforeUpdate.quotePriceUsd,
            "Quote leg should remain cached for unrelated decimals changes"
        );
        assertEq(
            afterUpdate.updatedAt,
            beforeUpdate.updatedAt,
            "Timestamp should remain cached for unrelated decimals changes"
        );
        assertEq(
            afterUpdate.roundId,
            beforeUpdate.roundId,
            "Round should remain cached for unrelated decimals changes"
        );
    }

    function test_whenPolicyIsDeactivated_reverts() public {
        _deactivateCachePolicy();

        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.getCachedPrice(address(assetToken), address(quoteToken));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
