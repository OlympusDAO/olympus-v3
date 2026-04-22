// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheGetCachedPriceTest is PriceCacheTest {
    function test_returnsSeparateAssetAndQuoteUsdLegs() public {
        _cachePair();

        IPriceCache.CachedPrice memory assetQuote = cache.getCachedPrice(
            address(assetToken),
            address(quoteToken)
        );
        assertEq(assetQuote.assetPriceUsd, 2e18, "Asset leg should remain asset/USD");
        assertEq(assetQuote.quotePriceUsd, 1e18, "Quote leg should remain quote/USD");

        IPriceCache.CachedPrice memory quoteAsset = cache.getCachedPrice(
            address(quoteToken),
            address(assetToken)
        );
        assertEq(quoteAsset.assetPriceUsd, 1e18, "Reversed asset leg should flip orientation");
        assertEq(quoteAsset.quotePriceUsd, 2e18, "Reversed quote leg should flip orientation");
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
        cache.getCachedPrice(address(assetToken), address(quoteToken));
    }

    function test_whenQuoteRemovedFromPRICE_reverts() public {
        _cachePair();
        priceModule.removeAsset(address(quoteToken));

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(quoteToken))
        );
        cache.getCachedPrice(address(assetToken), address(quoteToken));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
