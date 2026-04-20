// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {PriceV2BaseTest} from "src/test/modules/PRICE.v2/PriceV2BaseTest.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";
import {toSubKeycode} from "src/Submodules.sol";
import {Module} from "src/Kernel.sol";

contract PriceV2CachePriceTest is PriceV2BaseTest {
    address internal constant _UNIT_OF_ACCOUNT = address(840);

    event PricePairCached(
        address indexed asset_,
        address indexed quote_,
        uint256 assetPriceUsd_,
        uint256 quotePriceUsd_,
        uint48 cachedAt_,
        uint80 roundId_
    );

    function setUp() public override {
        super.setUp();
        _addBaseAssets(0);
    }

    function _expectAssetNotApprovedRevert(
        address asset_,
        address base_,
        address expectedUnapproved_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, expectedUnapproved_)
        );
        price.cachePrice(asset_, base_);
    }

    function _assertAssetUsdCacheUpdated(
        address asset_,
        uint256 expectedPrice_,
        uint80 roundIdBefore_
    ) internal view {
        (, , uint48 pairTimestamp, uint80 roundIdAfter) = price.getCachedPrice(
            asset_,
            _UNIT_OF_ACCOUNT
        );
        (uint256 cachedPrice, uint48 cachedTimestamp) = price.getPrice(
            asset_,
            IPRICEv2.Variant.LAST
        );

        assertEq(
            pairTimestamp,
            uint48(block.timestamp),
            "Asset/USD pair timestamp should be updated"
        );
        assertEq(roundIdAfter, roundIdBefore_ + 1, "Asset/USD round should increment");
        assertEq(cachedPrice, expectedPrice_, "Asset/USD cache should be backfilled");
        assertEq(
            cachedTimestamp,
            uint48(block.timestamp),
            "Asset/USD LAST timestamp should be backfilled"
        );
    }

    // given the caller is not permissioned: it reverts

    function test_givenCallerNotPermissioned_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        price.cachePrice(address(ohm), _UNIT_OF_ACCOUNT);
    }

    // given the asset is not approved: it reverts

    function test_givenAssetNotApproved_reverts() public {
        address unapprovedAsset = makeAddr("unapprovedAsset");
        address otherUnapprovedAsset = makeAddr("otherUnapprovedAsset");

        vm.startPrank(priceWriter);

        // Unit-of-account pairs should revert regardless of operand ordering.
        _expectAssetNotApprovedRevert(unapprovedAsset, _UNIT_OF_ACCOUNT, unapprovedAsset);
        _expectAssetNotApprovedRevert(_UNIT_OF_ACCOUNT, unapprovedAsset, unapprovedAsset);

        // Non-unit pairs should revert when either side is unapproved.
        _expectAssetNotApprovedRevert(unapprovedAsset, address(reserve), unapprovedAsset);
        _expectAssetNotApprovedRevert(address(reserve), unapprovedAsset, unapprovedAsset);

        // If both are unapproved, the first operand should fail validation first.
        _expectAssetNotApprovedRevert(unapprovedAsset, otherUnapprovedAsset, unapprovedAsset);
        _expectAssetNotApprovedRevert(otherUnapprovedAsset, unapprovedAsset, otherUnapprovedAsset);

        vm.stopPrank();
    }

    function test_givenAssetIsZeroAddress_reverts() public {
        vm.startPrank(priceWriter);
        _expectAssetNotApprovedRevert(address(0), _UNIT_OF_ACCOUNT, address(0));
        _expectAssetNotApprovedRevert(_UNIT_OF_ACCOUNT, address(0), address(0));
        vm.stopPrank();
    }

    function test_givenSameAddress_reverts() public {
        vm.startPrank(priceWriter);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsPairInvalid.selector,
                address(ohm),
                address(ohm)
            )
        );
        price.cachePrice(address(ohm), address(ohm));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsPairInvalid.selector,
                _UNIT_OF_ACCOUNT,
                _UNIT_OF_ACCOUNT
            )
        );
        price.cachePrice(_UNIT_OF_ACCOUNT, _UNIT_OF_ACCOUNT);

        vm.stopPrank();
    }

    // when the current price is zero: it reverts

    function test_whenCurrentPriceZero_reverts() public {
        // Use ALPHA asset which has a single feed
        // Set feed price to 0
        alphaUsdPriceFeed.setLatestAnswer(0);

        vm.startPrank(priceWriter);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(alpha)));
        price.cachePrice(address(alpha), _UNIT_OF_ACCOUNT);
        vm.stopPrank();
    }

    // when the strategy fails: it reverts

    function test_whenStrategyFails_reverts() public {
        // OHM uses getMedianPriceIfDeviation strategy with 3 feeds.
        // If we make all feeds fail/return 0 and set revertOnInsufficientCount to true, it should fail.

        vm.startPrank(priceWriter);

        // Update OHM to revert on insufficient count.
        IPRICEv2.UpdateAssetParams memory params;
        params.updateStrategy = true;
        params.strategy = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            strategy.getMedianPriceIfDeviation.selector,
            abi.encode(
                ISimplePriceFeedStrategy.DeviationParams({
                    deviationBps: 300,
                    revertOnInsufficientCount: true
                })
            )
        );
        price.updateAsset(address(ohm), params);

        // Now make 2 feeds return 0
        ohmUsdPriceFeed.setLatestAnswer(0);
        ohmEthPriceFeed.setLatestAnswer(0);

        // Now cachePrice should revert because strategy will fail to find enough non-zero prices
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_StrategyFailed.selector,
                address(ohm),
                abi.encodeWithSelector(
                    ISimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector,
                    1,
                    3
                )
            )
        );
        price.cachePrice(address(ohm), _UNIT_OF_ACCOUNT);
        vm.stopPrank();
    }

    // when store moving average is true, when use moving average is false: it does not update the observations, it updates the price cache

    function test_whenStoreMovingAverageTrue_whenUseMovingAverageFalse() public {
        // ALPHA does not store MA by default, but we can update it
        IPRICEv2.UpdateAssetParams memory params;
        params.updateMovingAverage = true;
        params.storeMovingAverage = true;
        params.movingAverageDuration = 10 * OBSERVATION_FREQUENCY;
        params.observations = new uint256[](10);
        for (uint256 i; i < 10; i++) params.observations[i] = 50e18;
        params.lastObservationTime = uint48(block.timestamp);

        vm.prank(priceWriter);
        price.updateAsset(address(alpha), params);

        IPRICEv2.Asset memory assetBefore = price.getAssetData(address(alpha));
        uint16 nextObsIndexBefore = assetBefore.nextObsIndex;

        alphaUsdPriceFeed.setLatestAnswer(70e8);
        uint256 expectedPrice = 70e18;

        vm.prank(priceWriter);
        price.cachePrice(address(alpha), _UNIT_OF_ACCOUNT);

        IPRICEv2.Asset memory assetAfter = price.getAssetData(address(alpha));
        assertEq(assetAfter.nextObsIndex, nextObsIndexBefore, "Observations should not be updated");
        assertEq(
            assetAfter.obs[nextObsIndexBefore],
            assetBefore.obs[nextObsIndexBefore],
            "Observation value should not change"
        );

        (uint256 cachedPrice, ) = price.getPrice(address(alpha), IPRICEv2.Variant.LAST);
        assertEq(cachedPrice, expectedPrice, "Cache should be updated");
    }

    // when store moving average is true, when use moving average is true, when the moving average is stale: it reverts

    function test_whenStoreMovingAverageTrue_whenUseMovingAverageTrue_whenMovingAverageStale_reverts()
        public
    {
        // ONEMA uses MA, already added in setUp via _addBaseAssets

        // Warp time past observation frequency
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY + 1);

        vm.startPrank(priceWriter);
        // The last observation time was block.timestamp before warp
        uint48 lastObsTime = uint48(block.timestamp - OBSERVATION_FREQUENCY - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_MovingAverageStale.selector,
                address(onema),
                lastObsTime
            )
        );
        price.cachePrice(address(onema), _UNIT_OF_ACCOUNT);
        vm.stopPrank();
    }

    // when store moving average is true, when use moving average is true, when the moving average is not stale: it does not update the observations, it updates the price cache

    function test_whenStoreMovingAverageTrue_whenUseMovingAverageTrue() public {
        // ONEMA uses and stores MA
        IPRICEv2.Asset memory assetBefore = price.getAssetData(address(onema));
        uint16 nextObsIndexBefore = assetBefore.nextObsIndex;

        onemaUsdPriceFeed.setLatestAnswer(200e8);
        // cachePrice uses MA, but ONEMA strategy is FirstNonZero, it will take the feed price
        uint256 expectedPrice = 200e18;

        vm.prank(priceWriter);
        price.cachePrice(address(onema), _UNIT_OF_ACCOUNT);

        IPRICEv2.Asset memory assetAfter = price.getAssetData(address(onema));
        assertEq(assetAfter.nextObsIndex, nextObsIndexBefore, "Observations should not be updated");

        (uint256 cachedPrice, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(cachedPrice, expectedPrice, "Cache should be updated");
    }

    // when store moving average is true, when use moving average is true, when the moving average is not stale: calling cachePrice results in the same cached value as storeObservation (ONEMA)

    function test_whenUseMovingAverageTrue_consistencyWithStoreObservation_ONEMA() public {
        // Wait until it's time for a new observation
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);

        onemaUsdPriceFeed.setLatestAnswer(300e8);

        vm.startPrank(priceWriter);
        price.storeObservation(address(onema));
        (uint256 cachedPriceAfterStore, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);

        // Call cachePrice in the same block
        price.cachePrice(address(onema), _UNIT_OF_ACCOUNT);
        (uint256 cachedPriceAfterCache, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);

        assertEq(cachedPriceAfterCache, cachedPriceAfterStore, "Consistency mismatch (ONEMA)");
        vm.stopPrank();
    }

    // when store moving average is true, when use moving average is true, when the moving average is not stale: calling cachePrice results in the same cached value as storeObservation (TWOMA)

    function test_whenUseMovingAverageTrue_consistencyWithStoreObservation_TWOMA() public {
        // TWOMA uses Average strategy
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);

        twomaUsdPriceFeed.setLatestAnswer(100e8);
        twomaEthPriceFeed.setLatestAnswer(0.1e18); // asset/eth
        ethUsdPriceFeed.setLatestAnswer(2000e8); // eth/usd
        // feed1: 100e18
        // feed2: 0.1 * 2000 = 200e18

        vm.startPrank(priceWriter);
        price.storeObservation(address(twoma));
        (uint256 cachedPriceAfterStore, ) = price.getPrice(address(twoma), IPRICEv2.Variant.LAST);

        // Call cachePrice in the same block
        price.cachePrice(address(twoma), _UNIT_OF_ACCOUNT);
        (uint256 cachedPriceAfterCache, ) = price.getPrice(address(twoma), IPRICEv2.Variant.LAST);

        assertEq(cachedPriceAfterCache, cachedPriceAfterStore, "Consistency mismatch (TWOMA)");
        vm.stopPrank();
    }

    // when everything is correct: it updates the price cache, it emits a PriceCached event

    function test_whenSuccess() public {
        // Use ALPHA
        uint256 newPrice = 60e8; // alphaUsdPriceFeed has 8 decimals
        uint256 expectedPrice = 60e18; // result is in 18 decimals
        (, , , uint80 alphaUsdRoundIdBefore) = price.getCachedPrice(
            address(alpha),
            _UNIT_OF_ACCOUNT
        );
        /// forge-lint: disable-next-line(unsafe-typecast)
        alphaUsdPriceFeed.setLatestAnswer(int256(newPrice));

        vm.startPrank(priceWriter);

        vm.expectEmit(true, true, true, true);
        emit PriceCached(address(alpha), expectedPrice, uint48(block.timestamp));

        price.cachePrice(address(alpha), _UNIT_OF_ACCOUNT);

        (uint256 cachedPrice, uint48 cachedAt) = price.getPrice(
            address(alpha),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 alphaUsdRoundIdAfter) = price.getCachedPrice(
            address(alpha),
            _UNIT_OF_ACCOUNT
        );
        assertEq(cachedPrice, expectedPrice, "cached price mismatch");
        assertEq(cachedAt, uint48(block.timestamp), "cached timestamp mismatch");
        assertEq(
            alphaUsdRoundIdAfter,
            alphaUsdRoundIdBefore + 1,
            "Asset/USD round should increment"
        );
        vm.stopPrank();
    }

    function test_whenSuccess_givenBaseIsNonUnitOfAccount() public {
        (uint256 cachedPriceBefore, uint48 cachedAtBefore) = price.getPriceIn(
            address(ohm),
            address(reserve),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 roundIdBefore) = price.getCachedPrice(address(ohm), address(reserve));
        (, , , uint80 ohmUsdRoundIdBefore) = price.getCachedPrice(address(ohm), _UNIT_OF_ACCOUNT);
        (, , , uint80 reserveUsdRoundIdBefore) = price.getCachedPrice(
            address(reserve),
            _UNIT_OF_ACCOUNT
        );

        assertEq(cachedPriceBefore, 0, "Pair should start uncached");
        assertEq(cachedAtBefore, 0, "Pair timestamp should start uncached");
        assertEq(roundIdBefore, 0, "Pair round ID should start uncached");

        (uint256 ohmUsdPrice, ) = price.getPrice(address(ohm), IPRICEv2.Variant.CURRENT);
        (uint256 reserveUsdPrice, ) = price.getPrice(address(reserve), IPRICEv2.Variant.CURRENT);
        uint256 expectedPairPrice = (ohmUsdPrice * 10 ** price.decimals()) / reserveUsdPrice;

        vm.startPrank(priceWriter);

        vm.expectEmit(true, true, true, true);
        emit PricePairCached(
            address(ohm),
            address(reserve),
            ohmUsdPrice,
            reserveUsdPrice,
            uint48(block.timestamp),
            1
        );

        price.cachePrice(address(ohm), address(reserve));

        (uint256 cachedPriceAfter, uint48 cachedAtAfter) = price.getPriceIn(
            address(ohm),
            address(reserve),
            IPRICEv2.Variant.LAST
        );
        (, , , uint80 roundIdAfter) = price.getCachedPrice(address(ohm), address(reserve));

        assertEq(cachedPriceAfter, expectedPairPrice, "Pair price mismatch");
        assertEq(cachedAtAfter, uint48(block.timestamp), "Pair timestamp mismatch");
        assertEq(roundIdAfter, 1, "Pair round ID mismatch");
        _assertAssetUsdCacheUpdated(address(ohm), ohmUsdPrice, ohmUsdRoundIdBefore);
        _assertAssetUsdCacheUpdated(address(reserve), reserveUsdPrice, reserveUsdRoundIdBefore);

        vm.stopPrank();
    }

    function test_whenPairOrderingChanges_updatesSameCacheKey() public {
        vm.startPrank(priceWriter);

        price.cachePrice(address(ohm), address(reserve));

        (
            uint256 ohmReserveQuoteUsd,
            uint256 ohmReserveBaseUsd,
            uint48 firstTimestamp,
            uint80 firstRound
        ) = price.getCachedPrice(address(ohm), address(reserve));
        (
            uint256 reserveOhmQuoteUsd,
            uint256 reserveOhmBaseUsd,
            uint48 reverseTimestamp,
            uint80 reverseRound
        ) = price.getCachedPrice(address(reserve), address(ohm));

        assertEq(firstTimestamp, reverseTimestamp, "Both orientations should share timestamp");
        assertEq(firstRound, reverseRound, "Both orientations should share round ID");
        assertEq(
            ohmReserveQuoteUsd,
            reserveOhmBaseUsd,
            "Reversed orientation should reuse the same quote leg"
        );
        assertEq(
            ohmReserveBaseUsd,
            reserveOhmQuoteUsd,
            "Reversed orientation should reuse the same base leg"
        );

        vm.warp(block.timestamp + 1);
        price.cachePrice(address(reserve), address(ohm));

        (, , uint48 updatedTimestamp, uint80 updatedRound) = price.getCachedPrice(
            address(ohm),
            address(reserve)
        );
        (, , uint48 reversedUpdatedTimestamp, uint80 reversedUpdatedRound) = price.getCachedPrice(
            address(reserve),
            address(ohm)
        );

        assertEq(
            updatedTimestamp,
            reversedUpdatedTimestamp,
            "Canonical pair timestamp should match"
        );
        assertEq(updatedRound, reversedUpdatedRound, "Canonical pair round should match");
        assertEq(
            updatedTimestamp,
            uint48(block.timestamp),
            "Shared pair timestamp should update once"
        );
        assertEq(updatedRound, firstRound + 1, "Shared pair round should increment once");

        vm.stopPrank();
    }
}
