// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";

contract IPriceCacheSemanticsTest is Test {
    MockPriceCache internal cache;
    address internal asset;
    address internal quote;

    function setUp() public {
        cache = new MockPriceCache();
        asset = makeAddr("asset");
        quote = makeAddr("quote");

        cache.setUsdPrice(asset, 2e18);
        cache.setUsdPrice(quote, 1e18);
    }

    function test_cachePrice_whenPairIsNotExplicitlyAllowed_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(MockPriceCache.PriceCache_PairNotAllowed.selector, asset, quote)
        );
        cache.cachePrice(asset, quote);
    }

    function test_getCachedPrice_returnsSeparateAssetAndQuoteUsdLegs() public {
        cache.setPairAllowed(asset, quote, true);
        cache.cachePrice(asset, quote);

        IPriceCache.CachedPrice memory assetQuote = cache.getCachedPrice(asset, quote);
        assertEq(assetQuote.assetPriceUsd, 2e18, "Asset leg should remain asset/USD");
        assertEq(assetQuote.quotePriceUsd, 1e18, "Quote leg should remain quote/USD");

        IPriceCache.CachedPrice memory quoteAsset = cache.getCachedPrice(quote, asset);
        assertEq(quoteAsset.assetPriceUsd, 1e18, "Reversed asset leg should flip orientation");
        assertEq(quoteAsset.quotePriceUsd, 2e18, "Reversed quote leg should flip orientation");
    }

    function test_cachePrice_roundIdIncrementsPerSuccessfulPairWrite() public {
        cache.setPairAllowed(asset, quote, true);

        cache.cachePrice(asset, quote);
        IPriceCache.CachedPrice memory firstSnapshot = cache.getCachedPrice(asset, quote);
        assertEq(firstSnapshot.roundId, 1, "First successful cache write should set roundId to 1");

        vm.warp(block.timestamp + 1);
        cache.cachePrice(asset, quote);
        IPriceCache.CachedPrice memory secondSnapshot = cache.getCachedPrice(asset, quote);
        assertEq(
            secondSnapshot.roundId,
            2,
            "Second successful cache write should increment roundId"
        );
        assertGt(secondSnapshot.updatedAt, firstSnapshot.updatedAt, "updatedAt should advance");
    }
}
