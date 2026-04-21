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
        uint48 cachedAt_
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

    function _assertAssetUsdCacheUpdated(address asset_, uint256 expectedPrice_) internal view {
        (, uint48 pairTimestamp) = price.getPriceIn(
            asset_,
            _UNIT_OF_ACCOUNT,
            IPRICEv2.Variant.LAST
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

    // when everything is correct: it updates the price cache, it emits a PricePairCached event

    function test_whenSuccess() public {
        // Use ALPHA
        uint256 newPrice = 60e8; // alphaUsdPriceFeed has 8 decimals
        uint256 expectedPrice = 60e18; // result is in 18 decimals
        /// forge-lint: disable-next-line(unsafe-typecast)
        alphaUsdPriceFeed.setLatestAnswer(int256(newPrice));

        vm.startPrank(priceWriter);

        vm.expectEmit(true, true, true, true);
        emit PricePairCached(address(alpha), _UNIT_OF_ACCOUNT, expectedPrice, 1e18, uint48(block.timestamp));

        price.cachePrice(address(alpha), _UNIT_OF_ACCOUNT);

        (uint256 cachedPrice, uint48 cachedAt) = price.getPrice(
            address(alpha),
            IPRICEv2.Variant.LAST
        );
        assertEq(cachedPrice, expectedPrice, "cached price mismatch");
        assertEq(cachedAt, uint48(block.timestamp), "cached timestamp mismatch");
        vm.stopPrank();
    }

    function test_whenSuccess_givenBaseIsNonUnitOfAccount() public {
        (uint256 cachedPriceBefore, uint48 cachedAtBefore) = price.getPriceIn(
            address(ohm),
            address(reserve),
            IPRICEv2.Variant.LAST
        );

        assertEq(cachedPriceBefore, 0, "Pair should start uncached");
        assertEq(cachedAtBefore, 0, "Pair timestamp should start uncached");

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
            uint48(block.timestamp)
        );

        price.cachePrice(address(ohm), address(reserve));

        (uint256 cachedPriceAfter, uint48 cachedAtAfter) = price.getPriceIn(
            address(ohm),
            address(reserve),
            IPRICEv2.Variant.LAST
        );

        assertEq(cachedPriceAfter, expectedPairPrice, "Pair price mismatch");
        assertEq(cachedAtAfter, uint48(block.timestamp), "Pair timestamp mismatch");
        _assertAssetUsdCacheUpdated(address(ohm), ohmUsdPrice);
        _assertAssetUsdCacheUpdated(address(reserve), reserveUsdPrice);

        vm.stopPrank();
    }

    function test_whenPairOrderingChanges_updatesSameCacheKey() public {
        vm.startPrank(priceWriter);

        price.cachePrice(address(ohm), address(reserve));

        (uint256 ohmReservePrice, uint48 firstTimestamp) = price.getPriceIn(
            address(ohm),
            address(reserve),
            IPRICEv2.Variant.LAST
        );
        (uint256 reserveOhmPrice, uint48 reverseTimestamp) = price.getPriceIn(
            address(reserve),
            address(ohm),
            IPRICEv2.Variant.LAST
        );

        assertEq(firstTimestamp, reverseTimestamp, "Both orientations should share timestamp");
        assertGt(ohmReservePrice, 0, "OHM/Reserve pair should be cached");
        assertGt(reserveOhmPrice, 0, "Reserve/OHM pair should be cached");

        vm.warp(block.timestamp + 1);
        price.cachePrice(address(reserve), address(ohm));

        (, uint48 updatedTimestamp) = price.getPriceIn(
            address(ohm),
            address(reserve),
            IPRICEv2.Variant.LAST
        );
        (, uint48 reversedUpdatedTimestamp) = price.getPriceIn(
            address(reserve),
            address(ohm),
            IPRICEv2.Variant.LAST
        );

        assertEq(
            updatedTimestamp,
            reversedUpdatedTimestamp,
            "Canonical pair timestamp should match"
        );
        assertEq(
            updatedTimestamp,
            uint48(block.timestamp),
            "Shared pair timestamp should update once"
        );

        vm.stopPrank();
    }
}
