// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheCachePriceTest is PriceCacheTest {
    function test_whenPolicyDisabled_reverts() public {
        vm.prank(admin);
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        cache.cachePrice(address(assetToken), address(quoteToken));
    }

    function test_whenPolicyIsDeactivated_reverts() public {
        _deactivateCachePolicy();

        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        cache.cachePrice(address(assetToken), address(quoteToken));
    }

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

    function test_whenAssetIsUnapproved_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        cache.cachePrice(unapprovedAsset, address(quoteToken));
    }

    function test_whenQuoteIsUnapproved_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        cache.cachePrice(address(assetToken), unapprovedAsset);
    }

    function test_whenBothAssetsAreUnapproved_reverts() public {
        address unapprovedQuote = makeAddr("UNAPPROVED_QUOTE");

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        cache.cachePrice(unapprovedAsset, unapprovedQuote);
    }

    function test_whenPairIsValid_cachesSnapshotAndIncrementsRoundId() public {
        cache.cachePrice(address(assetToken), address(quoteToken));
        IPriceCache.CachedPrice memory firstSnapshot = _cachedPair();
        assertEq(firstSnapshot.assetPriceUsd, 2e18, "Asset leg should be cached");
        assertEq(firstSnapshot.quotePriceUsd, 1e18, "Quote leg should be cached");
        assertGt(firstSnapshot.updatedAt, 0, "updatedAt should be set");
        assertEq(firstSnapshot.roundId, 1, "roundId should start at 1");

        vm.warp(block.timestamp + 1);
        priceModule.setTimestamp(uint48(block.timestamp));
        cache.cachePrice(address(assetToken), address(quoteToken));
        IPriceCache.CachedPrice memory secondSnapshot = _cachedPair();
        assertEq(secondSnapshot.roundId, 2, "roundId should increment on each write");
        assertGt(secondSnapshot.updatedAt, firstSnapshot.updatedAt, "updatedAt should advance");
    }

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
        assertEq(firstQuoteAsset.assetPriceUsd, 1e18, "Reverse asset leg should flip orientation");
        assertEq(firstQuoteAsset.quotePriceUsd, 2e18, "Reverse quote leg should flip orientation");

        vm.warp(block.timestamp + 5);
        priceModule.setTimestamp(uint48(block.timestamp));
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

        vm.warp(block.timestamp + 7);
        priceModule.setTimestamp(uint48(block.timestamp));
        cache.cachePrice(address(quoteToken), address(assetToken));
        IPriceCache.CachedPrice memory thirdAssetQuote = cache.getCachedPrice(
            address(assetToken),
            address(quoteToken)
        );
        IPriceCache.CachedPrice memory thirdQuoteAsset = cache.getCachedPrice(
            address(quoteToken),
            address(assetToken)
        );
        assertEq(thirdAssetQuote.roundId, 3, "Forward round should increment from reverse writes");
        assertEq(thirdQuoteAsset.roundId, 3, "Reverse round should share incremented round");
        assertGt(
            thirdAssetQuote.updatedAt,
            secondAssetQuote.updatedAt,
            "Timestamp should keep advancing"
        );
        assertEq(thirdAssetQuote.assetPriceUsd, 2e18, "Forward orientation should remain correct");
        assertEq(thirdAssetQuote.quotePriceUsd, 1e18, "Forward orientation should remain correct");
        assertEq(thirdQuoteAsset.assetPriceUsd, 1e18, "Reverse orientation should remain correct");
        assertEq(thirdQuoteAsset.quotePriceUsd, 2e18, "Reverse orientation should remain correct");
    }

    function test_whenAssetIsUnitOfAccount_cachesUnitPriceAsAssetLeg() public {
        address unitOfAccount = _unitOfAccount();

        cache.cachePrice(unitOfAccount, address(assetToken));
        IPriceCache.CachedPrice memory snapshot = cache.getCachedPrice(
            unitOfAccount,
            address(assetToken)
        );

        assertEq(snapshot.assetPriceUsd, 1e18, "Unit-of-account should be cached at 1e18");
        assertEq(snapshot.quotePriceUsd, 2e18, "Quote leg should use token USD price");
        assertEq(snapshot.roundId, 1, "Round should increment on successful write");
        assertGt(snapshot.updatedAt, 0, "Timestamp should be set");
    }

    function test_whenQuoteIsUnitOfAccount_cachesUnitPriceAsQuoteLeg() public {
        address unitOfAccount = _unitOfAccount();

        cache.cachePrice(address(assetToken), unitOfAccount);
        IPriceCache.CachedPrice memory snapshot = cache.getCachedPrice(
            address(assetToken),
            unitOfAccount
        );

        assertEq(snapshot.assetPriceUsd, 2e18, "Asset leg should use token USD price");
        assertEq(snapshot.quotePriceUsd, 1e18, "Unit-of-account should be cached at 1e18");
        assertEq(snapshot.roundId, 1, "Round should increment on successful write");
        assertGt(snapshot.updatedAt, 0, "Timestamp should be set");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
