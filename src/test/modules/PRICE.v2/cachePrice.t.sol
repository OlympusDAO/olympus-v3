// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {PriceV2BaseTest} from "src/test/modules/PRICE.v2/PriceV2BaseTest.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";
import {toSubKeycode} from "src/Submodules.sol";
import {Module} from "src/Kernel.sol";

contract PriceV2CachePriceTest is PriceV2BaseTest {
    function setUp() public override {
        super.setUp();
        _addBaseAssets(0);
    }

    // given the caller is not permissioned: it reverts

    function test_givenCallerNotPermissioned_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        price.cachePrice(address(ohm));
    }

    // given the asset is not approved: it reverts

    function test_givenAssetNotApproved_reverts() public {
        address unapproved = makeAddr("unapproved");
        vm.startPrank(priceWriter);
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapproved)
        );
        price.cachePrice(unapproved);
        vm.stopPrank();
    }

    // when the current price is zero: it reverts

    function test_whenCurrentPriceZero_reverts() public {
        // Use ALPHA asset which has a single feed
        // Set feed price to 0
        alphaUsdPriceFeed.setLatestAnswer(0);

        vm.startPrank(priceWriter);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(alpha)));
        price.cachePrice(address(alpha));
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
        price.cachePrice(address(ohm));
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
        price.cachePrice(address(alpha));

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
        price.cachePrice(address(onema));
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
        price.cachePrice(address(onema));

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
        price.cachePrice(address(onema));
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
        price.cachePrice(address(twoma));
        (uint256 cachedPriceAfterCache, ) = price.getPrice(address(twoma), IPRICEv2.Variant.LAST);

        assertEq(cachedPriceAfterCache, cachedPriceAfterStore, "Consistency mismatch (TWOMA)");
        vm.stopPrank();
    }

    // when everything is correct: it updates the price cache, it emits a PriceCached event

    function test_whenSuccess() public {
        // Use ALPHA
        uint256 newPrice = 60e8; // alphaUsdPriceFeed has 8 decimals
        uint256 expectedPrice = 60e18; // result is in 18 decimals
        /// forge-lint: disable-next-line(unsafe-typecast)
        alphaUsdPriceFeed.setLatestAnswer(int256(newPrice));

        vm.startPrank(priceWriter);

        vm.expectEmit(true, true, true, true);
        emit PriceCached(address(alpha), expectedPrice, uint48(block.timestamp));

        price.cachePrice(address(alpha));

        (uint256 cachedPrice, uint48 cachedAt) = price.getPrice(
            address(alpha),
            IPRICEv2.Variant.LAST
        );
        assertEq(cachedPrice, expectedPrice, "cached price mismatch");
        assertEq(cachedAt, uint48(block.timestamp), "cached timestamp mismatch");
        vm.stopPrank();
    }
}
