// SPDX-License-Identifier: Unlicense
// solhint-disable max-states-count
// solhint-disable custom-errors
/// forge-lint: disable-start(mixed-case-variable,mixed-case-function)
pragma solidity >=0.8.0;

// Test
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {PriceV2BaseTest} from "./PriceV2BaseTest.sol";

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";

// Bophades
import {Module} from "src/Kernel.sol";
import {fromSubKeycode, toSubKeycode} from "src/Submodules.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {UniswapV3Price} from "modules/PRICE/submodules/feeds/UniswapV3Price.sol";

// Tests for OlympusPrice v2
//
// Asset Information
// [X] getAssets - returns all assets configured on the PRICE module
//      [X] zero assets
//      [X] one asset
//      [X] many assets
// [X] getAssetData - returns the price configuration data for a given asset
//
// Asset Prices
// [X] getPrice(address, Variant) - returns the price of an asset in terms of the unit of account (USD)
//      [X] current variant - dynamically calculates price from strategy and components
//           [X] no strategy submodule (only one price source)
//              [X] single price feed
//              [X] single price feed with recursive calls
//              [X] reverts if price is zero
//           [X] with strategy submodule
//              [X] two feeds (two separate feeds)
//              [X] two feeds (one feed + MA)
//              [X] three feeds (three separate feeds)
//              [X] three feeds (two feeds + MA)
//              [X] reverts if strategy fails
//              [X] reverts if price is zero
//           [X] reverts if no address is given
//      [X] last variant - loads price from cache
//           [X] single observation stored
//           [X] multiple observations stored
//           [X] multiple observations stored, nextObsIndex != 0
//           [X] reverts if asset not configured
//           [X] reverts if no address is given
//      [X] moving average variant - returns the moving average from stored observations
//           [X] single observation stored
//           [X] multiple observations stored
//           [X] reverts if moving average isn't stored
//           [X] reverts if asset not configured
//           [X] reverts if no address is given
//      [X] reverts if invalid variant provided
//      [X] reverts if asset not configured on PRICE module (not approved)
// [X] getPrice(address) - convenience function for current price
//      [X] returns cached value if updated this timestamp
//      [X] calculates and returns current price if not updated this timestamp
//      [X] reverts if asset not configured on PRICE module (not approved)
// [X] getPriceIn(asset, base, Variant) - returns the price of an asset in terms of another asset
//      [X] current variant - dynamically calculates price from strategy and components
//      [X] last variant - loads price from cache
//      [X] moving average variant - returns the moving average from stored observations
//      [X] reverts if invalid variant provided for either asset
//      [X] reverts if either asset price is zero
//      [X] reverts if either asset is not configured on PRICE module (not approved)
// [X] getPriceIn(asset, base) - returns cached value if updated this timestamp, otherwise calculates dynamically
//      [X] returns cached value if both assets updated this timestamp
//      [X] calculates and returns current price if either asset not updated this timestamp
// [X] storeObservation - caches the price of an asset (stores a new observation if the asset uses a moving average)
//      [X] reverts if asset not configured on PRICE module (not approved)
//      [X] reverts if price is zero
//      [X] reverts if caller is not permissioned
//      [X] reverts if observationFrequency has not elapsed since last observation
//      [X] updates stored observations
//           [X] single observation stored (no moving average)
//           [X] multiple observations stored (moving average configured)
//      [X] price stored event emitted
//
// Asset Management
// [X] addAsset - add an asset to the PRICE module
//      [X] reverts if asset already configured (approved)
//      [X] reverts if asset address is not a contract
//      [X] reverts if no strategy is set, moving average is disabled and multiple feeds (MA + feeds > 1)
//      [X] reverts if no strategy is set, moving average is enabled and single feed (MA + feeds > 1)
//      [X] reverts if caller is not permissioned
//      [X] reverts if moving average is used, but not stored
//      [X] reverts if a non-functioning configuration is provided
//      [X] reverts if a submodule call fails when attempting to get the price feeds
//      [ ] reverts if there are duplicate price feeds
//      [X] all asset data is stored correctly
//      [X] asset added to assets array
//      [X] asset added with no strategy, moving average disabled, single feed
//      [X] asset added with strategy, moving average enabled, single feed
//      [X] asset added with strategy, moving average enabled, mutiple feeds
//      [X] reverts if moving average contains any zero observations
//      [X] if not storing moving average and no cached value provided, dynamically calculates cache and stores so no zero cache values are stored
// [X] removeAsset
//      [X] reverts if asset not configured (not approved)
//      [X] reverts if caller is not permissioned
//      [X] all asset data is removed
//      [X] asset removed from assets array
//
// Note: Tests for updateAsset are in updateAsset.t.sol
//

// In order to create the necessary configuration to test above scenarios, the following assets/feed combinations are created on the price module:
// - OHM: Three feed using the getMedianPriceIfDeviation strategy
// - RSV: Two feed using the getAveragePriceIfDeviation strategy
// - WETH: One feed with no strategy
// - ALPHA: One feed with no strategy
// - BPT: One feed (has recursive calls) with no strategy
// - ONEMA: One feed + MA using the getFirstNonZeroPrice strategy
// - TWOMA: Two feed + MA using the getAveragePrice strategy

contract PriceV2Test is PriceV2BaseTest {
    // =========  TESTS ========= //

    function test_constructor_observationFrequency_zero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            IPRICEv2.PRICE_ObservationFrequencyInvalid.selector,
            0
        );
        vm.expectRevert(err);

        // Create a new module
        new OlympusPricev2(kernel, 18, 0);
    }

    function test_constructor_setsUnitOfAccountAndRegistersIt() public {
        OlympusPricev2 newPrice = new OlympusPricev2(kernel, 18, OBSERVATION_FREQUENCY);

        assertEq(
            newPrice.unitOfAccount(),
            _UNIT_OF_ACCOUNT,
            "Unit of account should use the reserved constant"
        );
        assertEq(
            newPrice.isNonContractAsset(_UNIT_OF_ACCOUNT),
            true,
            "Unit of account should be registered as a non-contract asset"
        );
    }

    // =========  getAssets  ========= //

    function test_getAssets_zero() public view {
        // Get assets from price module and check that they match
        address[] memory assets = price.getAssets();
        assertEq(assets.length, 0);
    }

    function test_getAssets_one() public {
        // Add one asset to the price module
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        vm.prank(priceWriter);
        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_ // don't track WETH MA
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );

        // Get assets from price module and check that they match
        address[] memory assets = price.getAssets();
        assertEq(assets[0], address(weth));
        assertEq(assets.length, 1);
    }

    function test_getAssets_many(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Get assets from price module and check that they match
        address[] memory assets = price.getAssets();
        assertEq(assets[0], address(weth));
        assertEq(assets[1], address(alpha));
        assertEq(assets[2], address(ohm));
        assertEq(assets[3], address(reserve));
        assertEq(assets[4], address(bpt));
        assertEq(assets[5], address(onema));
        assertEq(assets[6], address(twoma));
        assertEq(assets.length, 7);
    }

    // =========  getAssetData  ========= //

    function test_getAssetData(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Get asset data from price module and check that it matches
        IPRICEv2.Asset memory assetData = price.getAssetData(address(ohm));
        _assertAssetData(
            assetData,
            true,
            true,
            false,
            uint32(30 days),
            uint48(block.timestamp),
            0,
            90,
            assetData.cumulativeObs,
            "ohm"
        );
        IPRICEv2.Component memory assetStrategy = abi.decode(
            assetData.strategy,
            (IPRICEv2.Component)
        );
        /// forge-lint: disable-next-line(unsafe-typecast)
        assertEq(fromSubKeycode(assetStrategy.target), bytes20("PRICE.SIMPLESTRATEGY"));
        assertEq(
            assetStrategy.selector,
            ISimplePriceFeedStrategy.getMedianPriceIfDeviation.selector
        );
        assertEq(
            assetStrategy.params,
            abi.encode(
                ISimplePriceFeedStrategy.DeviationParams({
                    deviationBps: 300,
                    revertOnInsufficientCount: false
                })
            )
        );
        IPRICEv2.Component[] memory feeds = abi.decode(assetData.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 3);
        /// forge-lint: disable-next-line(unsafe-typecast)
        assertEq(fromSubKeycode(feeds[0].target), bytes20("PRICE.CHAINLINK"));
        assertEq(feeds[0].selector, ChainlinkPriceFeeds.getOneFeedPrice.selector);
        assertEq(
            feeds[0].params,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(ohmUsdPriceFeed, uint48(24 hours)))
        );
        /// forge-lint: disable-next-line(unsafe-typecast)
        assertEq(fromSubKeycode(feeds[1].target), bytes20("PRICE.CHAINLINK"));
        assertEq(feeds[1].selector, ChainlinkPriceFeeds.getTwoFeedPriceMul.selector);
        assertEq(
            feeds[1].params,
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams(
                    ohmEthPriceFeed,
                    uint48(24 hours),
                    ethUsdPriceFeed,
                    uint48(24 hours)
                )
            )
        );
        /// forge-lint: disable-next-line(unsafe-typecast)
        assertEq(fromSubKeycode(feeds[2].target), bytes20("PRICE.UNIV3"));
        assertEq(feeds[2].selector, UniswapV3Price.getTokenTWAP.selector);
        assertEq(
            feeds[2].params,
            abi.encode(UniswapV3Price.UniswapV3Params(ohmEthUniV3Pool, TWAP_PERIOD))
        );
    }

    // =========  getPrice (with current variant) ========= //

    function test_getPrice_current_noStrat_oneFeed(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Get current price from price module and check that it matches
        (uint256 price_, uint48 timestamp) = price.getPrice(
            address(weth),
            IPRICEv2.Variant.CURRENT
        );
        assertEq(price_, uint256(2000e18));
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testRevert_getPrice_current_noStrat_oneFeed_priceZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Set price feed to zero
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(weth));
        vm.expectRevert(err);
        price.getPrice(address(weth), IPRICEv2.Variant.CURRENT);
    }

    function test_getPrice_current_noStrat_oneFeedRecursive(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Get current price from price module and check that it matches
        (uint256 price_, uint48 timestamp) = price.getPrice(address(bpt), IPRICEv2.Variant.CURRENT);
        assertApproxEqAbsDecimal(price_, uint256(20e18), 1e6, 18); // allow for some imprecision due to AMM math and imprecise inputs
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testRevert_getPrice_current_noStrat_oneFeedRecursive_priceZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Set price feeds to zero
        ethUsdPriceFeed.setLatestAnswer(int256(0));
        ohmEthPriceFeed.setLatestAnswer(int256(0));
        ohmUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(bpt));
        vm.expectRevert(err);
        price.getPrice(address(bpt), IPRICEv2.Variant.CURRENT);
    }

    function test_getPrice_current_strat_twoFeed(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Price feeds are initialized with same value so there should be no deviation

        // Get current price from price module and check that it matches
        (uint256 price_, uint48 timestamp) = price.getPrice(
            address(reserve),
            IPRICEv2.Variant.CURRENT
        );
        assertEq(price_, uint256(1e18));
        assertEq(timestamp, uint48(block.timestamp));

        // Set price feeds at a small deviation to each other
        reserveUsdPriceFeed.setLatestAnswer(int256(1.1e8));
        // Other price feed is still 1e18

        // Get current price again, expect average of two feeds because deviation is more than 3%
        (price_, timestamp) = price.getPrice(address(reserve), IPRICEv2.Variant.CURRENT);
        assertEq(price_, uint256(1.05e18));
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testRevert_getPrice_current_strat_twoFeed_stratFailed(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Set all feeds to zero to trigger strategy failure (0 non-zero prices)
        // With the new strategy, 0 non-zero prices causes SimpleStrategy_PriceCountInvalid
        reserveUsdPriceFeed.setLatestAnswer(int256(0));
        reserveEthPriceFeed.setLatestAnswer(int256(0));
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        // Strategy fails with SimpleStrategy_PriceCountInvalid when all prices are zero
        // This is wrapped in PRICE_StrategyFailed
        // Construct the full expected revert data
        bytes memory innerError = abi.encodeWithSelector(
            bytes4(keccak256("SimpleStrategy_PriceCountInvalid(uint256,uint256)")),
            uint256(0),
            uint256(2)
        );
        bytes memory expectedRevert = abi.encodeWithSelector(
            bytes4(keccak256("PRICE_StrategyFailed(address,bytes)")),
            address(reserve),
            innerError
        );
        vm.expectRevert(expectedRevert);
        price.getPrice(address(reserve), IPRICEv2.Variant.CURRENT);
    }

    function test_getPrice_current_strat_oneFeedPlusMA(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // First feed is up so it should be returned on the first call
        (uint256 price_, uint48 timestamp) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.CURRENT
        );
        assertEq(price_, uint256(5e18));
        assertEq(timestamp, uint48(block.timestamp));

        // Get moving average
        (uint256 movingAverage, ) = price.getPrice(address(onema), IPRICEv2.Variant.MOVINGAVERAGE);

        // Set price feed to zero
        onemaUsdPriceFeed.setLatestAnswer(int256(0));

        // Get current price again, expect moving average because feed is down
        (price_, timestamp) = price.getPrice(address(onema), IPRICEv2.Variant.CURRENT);
        assertEq(price_, movingAverage);
    }

    function test_getPrice_current_strat_oneFeedPlusMA_staleMA(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        uint32 startTimestamp = uint32(block.timestamp);

        // Warp forward to just before the end of the observation frequency
        vm.warp(startTimestamp + OBSERVATION_FREQUENCY - 1);

        // Update the Chainlink price feed
        onemaUsdPriceFeed.setLatestAnswer(int256(5e8));
        onemaUsdPriceFeed.setTimestamp(block.timestamp);

        // Value is as expected
        (uint256 t1_price, uint48 t1_timestamp) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.CURRENT
        );
        assertEq(t1_price, uint256(5e18));
        assertEq(t1_timestamp, uint48(block.timestamp));

        // Get the moving average
        (, uint48 t1_movingAverageTimestamp) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.MOVINGAVERAGE
        );

        // Warp forward to the observation frequency
        vm.warp(startTimestamp + OBSERVATION_FREQUENCY);

        // Update the Chainlink price feed
        onemaUsdPriceFeed.setLatestAnswer(int256(5e8));
        onemaUsdPriceFeed.setTimestamp(block.timestamp);

        // As useMovingAverage is enabled, calling the current price will
        // use the MA, which is now stale, and revert
        bytes memory err = abi.encodeWithSelector(
            IPRICEv2.PRICE_MovingAverageStale.selector,
            address(onema),
            startTimestamp
        );
        vm.expectRevert(err);
        price.getPrice(address(onema), IPRICEv2.Variant.CURRENT);

        // Get the moving average, which is stale
        (, uint48 t2_movingAverageTimestamp) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.MOVINGAVERAGE
        );
        assertEq(t2_movingAverageTimestamp, t1_movingAverageTimestamp);

        // Store the MA price
        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        // Get the current price again
        // Will have been updated
        (uint256 t2_price, uint48 t2_timestamp) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.CURRENT
        );
        assertEq(t2_price, uint256(5e18));
        assertEq(t2_timestamp, uint48(block.timestamp));

        // Moving average is now updated
        (, uint48 t3_movingAverageTimestamp) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.MOVINGAVERAGE
        );
        assertEq(t3_movingAverageTimestamp, t2_timestamp);
    }

    // MA cannot be zero so we cannot test PriceZero error on assets that use MA in a fallback strategy

    function test_getPrice_current_strat_threeFeed(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Price feeds are initialized with same value so there should be no deviation

        // Get current price from price module and check that it matches
        (uint256 price_, uint48 timestamp) = price.getPrice(address(ohm), IPRICEv2.Variant.CURRENT);
        assertEq(price_, uint256(10e18));

        // Set price feeds at a deviation to each other
        ohmUsdPriceFeed.setLatestAnswer(int256(11e8)); // $11
        ohmEthPriceFeed.setLatestAnswer(int256(0.0045e18)); // effectively $9

        // Get current price again, expect median of the three feeds because deviation is more than 3%
        // In this case, it should be the price of the UniV3 pool
        (price_, timestamp) = price.getPrice(address(ohm), IPRICEv2.Variant.CURRENT);
        uint256 expectedPrice = univ3Price.getTokenTWAP(
            address(ohm),
            price.decimals(),
            abi.encode(UniswapV3Price.UniswapV3Params(ohmEthUniV3Pool, TWAP_PERIOD))
        );
        assertEq(price_, expectedPrice);
    }

    function testRevert_getPrice_current_strat_threeFeed_stratFailed(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Set all feeds to zero to trigger strategy failure (0 non-zero prices)
        // With the new strategy, 0 non-zero prices causes SimpleStrategy_PriceCountInvalid
        ohmUsdPriceFeed.setLatestAnswer(int256(0));
        ohmEthPriceFeed.setLatestAnswer(int256(0));
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        // Strategy fails with SimpleStrategy_PriceCountInvalid when all prices are zero
        // This is wrapped in PRICE_StrategyFailed
        // Construct the full expected revert data
        bytes memory innerError = abi.encodeWithSelector(
            bytes4(keccak256("SimpleStrategy_PriceCountInvalid(uint256,uint256)")),
            uint256(0),
            uint256(3)
        );
        bytes memory expectedRevert = abi.encodeWithSelector(
            bytes4(keccak256("PRICE_StrategyFailed(address,bytes)")),
            address(ohm),
            innerError
        );
        vm.expectRevert(expectedRevert);
        price.getPrice(address(ohm), IPRICEv2.Variant.CURRENT);
    }

    function test_getPrice_current_strat_twoFeedPlusMA(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // All feeds are up, so the first call should return the average of all feeds & moving average
        (uint256 price_, uint48 timestamp) = price.getPrice(
            address(twoma),
            IPRICEv2.Variant.CURRENT
        );

        (uint256 movingAverage, ) = price.getPrice(address(twoma), IPRICEv2.Variant.MOVINGAVERAGE);
        uint256 expectedPrice = (uint256(20e18) + uint256(20e18) + movingAverage) / 3;
        assertEq(price_, expectedPrice);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function test_getPrice_current_useMovingAverageTrue_whenObservationStoredSameBlock_isInclusive()
        public
    {
        _addBaseAssets(1);

        // Configure the two live feeds so the raw observation (feed-only average) is deterministic.
        // twoma USD feed: 30e18
        twomaUsdPriceFeed.setLatestAnswer(int256(30e8));
        // twoma/ETH feed * ETH/USD feed: 0.02 * 2000 = 40e18
        twomaEthPriceFeed.setLatestAnswer(int256(0.02e18));

        IPRICEv2.Asset memory twomaData = price.getAssetData(address(twoma));
        uint256 rawObservation = (uint256(30e18) + uint256(40e18)) / 2;
        uint256 oldestObservation = twomaData.obs[twomaData.nextObsIndex];
        uint256 updatedMovingAverage = (twomaData.cumulativeObs -
            oldestObservation +
            rawObservation) / twomaData.numObservations;
        uint256 expectedCurrent = (uint256(30e18) + uint256(40e18) + updatedMovingAverage) / 3;

        vm.prank(priceWriter);
        price.storeObservation(address(twoma));

        (uint256 currentPrice, uint48 currentTimestamp) = price.getPrice(
            address(twoma),
            IPRICEv2.Variant.CURRENT
        );
        (uint256 lastPrice, ) = price.getPrice(address(twoma), IPRICEv2.Variant.LAST);

        assertEq(currentPrice, expectedCurrent, "CURRENT should include moving average");
        assertEq(currentTimestamp, uint48(block.timestamp), "CURRENT timestamp should be current");
        assertEq(lastPrice, rawObservation, "LAST should be the raw stored observation");
        assertNotEq(currentPrice, rawObservation, "CURRENT should not equal raw observation");
    }

    function test_getPrice_current_strat_twoFeedPlusMA_priceZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Set price feeds to zero
        twomaUsdPriceFeed.setLatestAnswer(int256(0));
        twomaEthPriceFeed.setLatestAnswer(int256(0));
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price
        (uint256 returnedPrice, ) = price.getPrice(address(twoma), IPRICEv2.Variant.CURRENT);

        // Grab the historical moving average
        (uint256 movingAverage, ) = price.getPrice(address(twoma), IPRICEv2.Variant.MOVINGAVERAGE);

        // As all price feeds are down, the moving average is returned
        assertEq(returnedPrice, movingAverage);
    }

    function testRevert_getPrice_current_unconfiguredAsset() public {
        // No base assets

        // Try to call getPrice with the current variant and expect revert
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(twoma)
        );
        vm.expectRevert(err);
        price.getPrice(address(twoma), IPRICEv2.Variant.CURRENT);
    }

    function testRevert_getPrice_current_addressZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Try to call getPrice with the last variant and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(0));
        vm.expectRevert(err);
        price.getPrice(address(0), IPRICEv2.Variant.CURRENT);
    }

    // =========  getPrice (with last variant) ========= //

    function test_getPrice_last_singleObservation(uint256 nonce_) public {
        // Add base asset with only 1 observation stored
        _addOneMAAsset(nonce_, 2);

        // Get the stored observation
        IPRICEv2.Asset memory asset = price.getAssetData(address(onema));
        uint256 storedObservation = asset.obs[1];
        uint48 start = uint48(block.timestamp);

        // Get last price, expect the only observation to be returned
        (uint256 price_, uint48 timestamp) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);

        assertEq(price_, storedObservation);
        assertEq(timestamp, start);

        // Warp forward in time and expect the same answer, even in the feed changes
        vm.warp(start + 1);
        onemaUsdPriceFeed.setLatestAnswer(int256(0));
        (price_, timestamp) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(price_, storedObservation);
        assertEq(timestamp, start);
    }

    function test_getPrice_last_multipleObservations(uint256 nonce_) public {
        // Add base asset with multiple observations stored
        _addOneMAAsset(nonce_, 10);

        // Get the stored observation
        IPRICEv2.Asset memory asset = price.getAssetData(address(onema));
        uint256 storedObservation = asset.obs[9];
        uint48 start = uint48(block.timestamp);

        // Get last price, expect the last observation to be returned
        (uint256 price_, uint48 timestamp) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);

        assertEq(price_, storedObservation);
        assertEq(timestamp, start);

        // Warp forward in time and expect the same answer, even in the feed changes
        vm.warp(start + 1);
        onemaUsdPriceFeed.setLatestAnswer(int256(0));
        (price_, timestamp) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(price_, storedObservation);
        assertEq(timestamp, start);
    }

    function test_getPrice_last_multipleObservations_nextObsIndexNotZero() public {
        // Add base asset with multiple observations stored
        uint256[] memory observations = new uint256[](2);
        observations[0] = 1e18;
        observations[1] = 2e18;
        _addOneMAAssetWithObservations(observations);

        // Get the current price, which is 5e8 from onemaUsdPriceFeed
        (uint256 price_, ) = price.getPrice(address(onema), IPRICEv2.Variant.CURRENT);
        assertEq(price_, 5e18);

        // LAST returns the most recent stored observation.
        (price_, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(price_, 2e18);

        // Warp OBSERVATION_FREQUENCY seconds forward, store the price, to increment nextObsIndex to 1
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);
        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        // LAST now points at the newly-stored observation.
        (price_, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);

        assertEq(price_, 5e18);
    }

    function testRevert_getPrice_last_unconfiguredAsset() public {
        // No base assets

        // Try to call getPrice with the last variant and expect revert
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(twoma)
        );
        vm.expectRevert(err);
        price.getPrice(address(twoma), IPRICEv2.Variant.LAST);
    }

    function testRevert_getPrice_last_addressZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Try to call getPrice with the last variant and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(0));
        vm.expectRevert(err);
        price.getPrice(address(0), IPRICEv2.Variant.LAST);
    }

    function testRevert_getPrice_last_movingAverageNotStored(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_MovingAverageNotStored.selector, address(weth))
        );
        price.getPrice(address(weth), IPRICEv2.Variant.LAST);
    }

    function test_getPrice_variants_useMovingAverageTrue_consistentSemantics(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        IPRICEv2.Asset memory twomaData = price.getAssetData(address(twoma));
        uint256 twomaLastIdx = twomaData.nextObsIndex == 0
            ? twomaData.numObservations - 1
            : twomaData.nextObsIndex - 1;

        uint256 expectedLast = twomaData.obs[twomaLastIdx];
        uint256 expectedMovingAverage = twomaData.cumulativeObs / twomaData.numObservations;
        uint256 expectedCurrent = (uint256(20e18) + uint256(20e18) + expectedMovingAverage) / 3;

        (uint256 currentPrice, uint48 currentTimestamp) = price.getPrice(
            address(twoma),
            IPRICEv2.Variant.CURRENT
        );
        (uint256 lastPrice, uint48 lastTimestamp) = price.getPrice(
            address(twoma),
            IPRICEv2.Variant.LAST
        );
        (uint256 movingAveragePrice, uint48 movingAverageTimestamp) = price.getPrice(
            address(twoma),
            IPRICEv2.Variant.MOVINGAVERAGE
        );

        assertEq(
            currentPrice,
            expectedCurrent,
            "CURRENT should use the inclusive feed+moving-average set"
        );
        assertEq(currentTimestamp, uint48(block.timestamp), "CURRENT timestamp should be current");

        assertEq(lastPrice, expectedLast, "LAST should use only the latest stored observation");
        assertEq(
            lastTimestamp,
            twomaData.lastObservationTime,
            "LAST timestamp should be the stored observation timestamp"
        );

        assertEq(
            movingAveragePrice,
            expectedMovingAverage,
            "MOVINGAVERAGE should use only historical observations"
        );
        assertEq(
            movingAverageTimestamp,
            twomaData.lastObservationTime,
            "MOVINGAVERAGE timestamp should be the stored observation timestamp"
        );
    }

    // =========  getPrice (with moving average variant) ========= //

    function test_getPrice_movingAverage_singleObservation() public {
        ChainlinkPriceFeeds.OneFeedParams memory onemaFeedParams = ChainlinkPriceFeeds
            .OneFeedParams(onemaUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(onemaFeedParams) // bytes memory params_
        );

        uint256[] memory observations = new uint256[](1);
        observations[0] = 5e18;

        // Expect an error
        bytes memory err = abi.encodeWithSelector(
            IPRICEv2.PRICE_ParamsInvalidObservationCount.selector,
            address(onema),
            1,
            1,
            1
        );
        vm.expectRevert(err);

        vm.prank(priceWriter);
        price.addAsset(
            address(onema), // address asset_
            true, // bool storeMovingAverage_ // track ONEMA MA
            true, // bool useMovingAverage_ // use MA in strategy
            uint32(observations.length) * OBSERVATION_FREQUENCY, // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            observations, // uint256[] memory observations_
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                ISimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds // Component[] feeds_
        );
    }

    function test_getPrice_movingAverage_minimumObservations(uint256 nonce_) public {
        // Add base asset with only 2 observations stored
        _addOneMAAsset(nonce_, 2);

        // Get the stored observation
        IPRICEv2.Asset memory asset = price.getAssetData(address(onema));
        uint256 storedObservation = (asset.obs[0] + asset.obs[1]) / 2;

        // Get moving average price
        (uint256 price_, ) = price.getPrice(address(onema), IPRICEv2.Variant.MOVINGAVERAGE);

        assertEq(price_, storedObservation);
    }

    function test_getPrice_movingAverage_multipleObservations(uint256 nonce_) public {
        // Add base asset with multiple observations stored
        _addOneMAAsset(nonce_, 10);

        // Get the stored observation
        IPRICEv2.Asset memory asset = price.getAssetData(address(onema));
        uint256 cumulativeObservations;
        for (uint256 i; i < asset.numObservations; i++) {
            cumulativeObservations += asset.obs[i];
        }
        uint256 movingAverage = cumulativeObservations / asset.numObservations;

        // Get moving average price, expect the only observation to be returned
        (uint256 price_, ) = price.getPrice(address(onema), IPRICEv2.Variant.MOVINGAVERAGE);

        assertEq(price_, movingAverage);
    }

    function testRevert_getPrice_movingAverage_movingAverageNotStored(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Try to call getPrice with the moving average variant and expect revert
        bytes memory err = abi.encodeWithSelector(
            IPRICEv2.PRICE_MovingAverageNotStored.selector,
            address(weth)
        );
        vm.expectRevert(err);
        price.getPrice(address(weth), IPRICEv2.Variant.MOVINGAVERAGE);
    }

    function testRevert_getPrice_movingAverage_unconfiguredAsset() public {
        // No base assets

        // Try to call getPrice with the moving average variant and expect revert
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(twoma)
        );
        vm.expectRevert(err);
        price.getPrice(address(twoma), IPRICEv2.Variant.MOVINGAVERAGE);
    }

    function testRevert_getPrice_movingAverage_addressZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Try to call getPrice with the last variant and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(0));
        vm.expectRevert(err);
        price.getPrice(address(0), IPRICEv2.Variant.MOVINGAVERAGE);
    }

    function test_getPrice_current_unitOfAccount() public view {
        (uint256 price_, uint48 timestamp) = price.getPrice(
            _UNIT_OF_ACCOUNT,
            IPRICEv2.Variant.CURRENT
        );

        assertEq(price_, 10 ** price.decimals());
        assertEq(timestamp, uint48(block.timestamp));
    }

    function test_getPrice_last_unitOfAccount() public view {
        (uint256 price_, uint48 timestamp) = price.getPrice(
            _UNIT_OF_ACCOUNT,
            IPRICEv2.Variant.LAST
        );

        assertEq(price_, 10 ** price.decimals());
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testRevert_getPrice_movingAverage_unitOfAccount() public {
        bytes memory err = abi.encodeWithSelector(
            IPRICEv2.PRICE_MovingAverageNotStored.selector,
            _UNIT_OF_ACCOUNT
        );
        vm.expectRevert(err);
        price.getPrice(_UNIT_OF_ACCOUNT, IPRICEv2.Variant.MOVINGAVERAGE);
    }

    function testRevert_getPrice_invalidVariant() public {
        // No base assets
        _addOneMAAsset(1, 15);

        // Try to call getPrice with an invalid invariant and expect revert
        // Have to build with a raw call since the getPrice function is overloaded
        (bool success, bytes memory data) = address(price).staticcall(
            abi.encodeWithSignature("getPrice(address,uint8)", address(onema), uint8(3))
        );

        assertFalse(success);
        // the function fails on converting the input to the Variant enum type,
        // therefore, it is an EvmError and no error data is returned
        assertEq(data.length, 0);

        // Show that this call works with a valid enum value and returns the price +
        // timestamp which is only returned from the getPrice(address,Variant) version
        (success, data) = address(price).staticcall(
            abi.encodeWithSignature("getPrice(address,uint8)", address(onema), uint8(0))
        );

        assertTrue(success);
        (uint256 price_, uint48 timestamp) = abi.decode(data, (uint256, uint48));
        assertEq(price_, uint256(5e18));
        assertEq(timestamp, uint48(block.timestamp));
    }

    // =========  getPrice (convenience) ========= //

    function test_getPrice_conv(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);
        uint48 start = uint48(block.timestamp);

        // Get current price from price module and check that it matches
        uint256 price_ = price.getPrice(address(weth));
        assertEq(price_, uint256(2000e18));

        // Warp time forward slightly and check that we get a new dynamic value
        vm.warp(uint256(start) + 1);
        ethUsdPriceFeed.setLatestAnswer(int256(2001e8));

        price_ = price.getPrice(address(weth));
        assertEq(price_, uint256(2001e18));
    }

    function test_getPrice_conv_whenFeedChangesInSameBlock_returnsCurrentValue(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        ethUsdPriceFeed.setLatestAnswer(int256(2100e8));
        ethUsdPriceFeed.setTimestamp(block.timestamp);

        uint256 price_ = price.getPrice(address(weth));
        assertEq(price_, uint256(2100e18));
    }

    function test_getPrice_conv_whenMovingAverageAssetObservationStoredSameBlock_returnsInclusiveCurrent()
        public
    {
        _addBaseAssets(1);

        // Configure TWOMA feeds so the raw stored observation is deterministic.
        twomaUsdPriceFeed.setLatestAnswer(int256(30e8));
        twomaEthPriceFeed.setLatestAnswer(int256(0.02e18)); // second feed => 40e18

        IPRICEv2.Asset memory twomaData = price.getAssetData(address(twoma));
        uint256 rawObservation = (uint256(30e18) + uint256(40e18)) / 2;
        uint256 oldestObservation = twomaData.obs[twomaData.nextObsIndex];
        uint256 updatedMovingAverage = (twomaData.cumulativeObs -
            oldestObservation +
            rawObservation) / twomaData.numObservations;
        uint256 expectedCurrent = (uint256(30e18) + uint256(40e18) + updatedMovingAverage) / 3;

        vm.prank(priceWriter);
        price.storeObservation(address(twoma));

        uint256 currentPrice = price.getPrice(address(twoma));
        (uint256 lastPrice, ) = price.getPrice(address(twoma), IPRICEv2.Variant.LAST);

        // Convenience getPrice should return inclusive CURRENT (feed prices + moving average).
        assertEq(
            currentPrice,
            expectedCurrent,
            "getPrice(asset) should return CURRENT, not a stale/non-inclusive fallback"
        );
        // LAST should still reflect the raw stored observation value.
        assertEq(lastPrice, rawObservation, "LAST should return the raw stored observation");
        // Same-timestamp reads must not fall back to LAST, or CURRENT loses MA inclusivity.
        assertNotEq(
            currentPrice,
            lastPrice,
            "getPrice(asset) should not return LAST when timestamps match"
        );
    }

    function testRevert_getPrice_conv_unconfiguredAsset() public {
        // No base assets

        // Try to call the getPrice convenience method and expect revert
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(twoma)
        );
        vm.expectRevert(err);
        price.getPrice(address(twoma));
    }

    // ==========  getPriceIn (asset, base, variant)  ========== //

    function test_getPriceIn_current(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Get current price of weth in ohm
        (uint256 price_, uint48 timestamp) = price.getPriceIn(
            address(weth),
            address(ohm),
            IPRICEv2.Variant.CURRENT
        );

        assertEq(price_, uint256(200e18));
        assertEq(timestamp, uint48(block.timestamp));
    }

    function test_getPriceIn_current_useMovingAverageTrue_whenObservationStoredSameBlock_isInclusive()
        public
    {
        _addBaseAssets(1);

        // Configure TWOMA feeds so the raw stored observation is deterministic.
        twomaUsdPriceFeed.setLatestAnswer(int256(30e8));
        twomaEthPriceFeed.setLatestAnswer(int256(0.02e18)); // second feed => 40e18

        IPRICEv2.Asset memory twomaData = price.getAssetData(address(twoma));
        uint256 rawObservation = (uint256(30e18) + uint256(40e18)) / 2;
        uint256 oldestObservation = twomaData.obs[twomaData.nextObsIndex];
        uint256 updatedMovingAverage = (twomaData.cumulativeObs -
            oldestObservation +
            rawObservation) / twomaData.numObservations;
        uint256 expectedTwomaCurrent = (uint256(30e18) + uint256(40e18) + updatedMovingAverage) / 3;

        vm.prank(priceWriter);
        price.storeObservation(address(twoma));

        (uint256 onemaCurrent, ) = price.getPrice(address(onema), IPRICEv2.Variant.CURRENT);
        uint256 scale = 10 ** price.decimals();
        uint256 expectedInclusivePair = (expectedTwomaCurrent * scale) / onemaCurrent;
        uint256 rawObservationPair = (rawObservation * scale) / onemaCurrent;

        (uint256 pairPrice, uint48 pairTimestamp) = price.getPriceIn(
            address(twoma),
            address(onema),
            IPRICEv2.Variant.CURRENT
        );

        assertEq(
            pairPrice,
            expectedInclusivePair,
            "Pair CURRENT should use inclusive per-asset values"
        );
        assertEq(
            pairTimestamp,
            uint48(block.timestamp),
            "Pair CURRENT timestamp should be current"
        );
        assertNotEq(pairPrice, rawObservationPair, "Pair CURRENT should not use raw observation");
    }

    function test_getPriceIn_current_sameAsset_returnsUnitPriceAndCurrentTimestamp(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        (uint256 price_, uint48 timestamp) = price.getPriceIn(
            address(ohm),
            address(ohm),
            IPRICEv2.Variant.CURRENT
        );

        assertEq(price_, uint256(10 ** price.decimals()));
        assertEq(timestamp, uint48(block.timestamp));
    }

    function test_getPriceIn_last_sameAsset_returnsUnitPriceAndLastTimestamp(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        (, uint48 lastTimestamp) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        vm.warp(block.timestamp + 6 hours);

        (uint256 pairPrice, uint48 pairTimestamp) = price.getPriceIn(
            address(onema),
            address(onema),
            IPRICEv2.Variant.LAST
        );

        assertEq(
            pairPrice,
            uint256(10 ** price.decimals()),
            "Same-asset quote should remain unit price"
        );
        assertEq(
            pairTimestamp,
            lastTimestamp,
            "Same-asset LAST quote should return the asset-side LAST timestamp"
        );
    }

    function testRevert_getPriceIn_current_priceZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Set weth price feed to zero
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(weth));
        vm.expectRevert(err);
        price.getPriceIn(address(weth), address(ohm), IPRICEv2.Variant.CURRENT);

        // Set weth price back to normal
        ethUsdPriceFeed.setLatestAnswer(int256(2000e8));

        // Set alpha price to zero
        alphaUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(alpha));
        vm.expectRevert(err);
        price.getPriceIn(address(weth), address(alpha), IPRICEv2.Variant.CURRENT);
    }

    function testRevert_getPriceIn_current_unconfiguredAsset() public {
        // No base assets

        // Try to call getPriceIn with the current variant and expect revert on the first asset
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(onema)
        );
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), IPRICEv2.Variant.CURRENT);

        // Add onema so it is approved
        _addOneMAAsset(1, 10);

        // Try to call getPriceIn with the current variant and expect revert on the second asset
        err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(twoma));
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), IPRICEv2.Variant.CURRENT);
    }

    function testRevert_getPriceIn_current_sameAsset_unconfiguredAsset() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(onema))
        );
        price.getPriceIn(address(onema), address(onema), IPRICEv2.Variant.CURRENT);
    }

    function testRevert_getPriceIn_last_sameAsset_unconfiguredAsset() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(onema))
        );
        price.getPriceIn(address(onema), address(onema), IPRICEv2.Variant.LAST);
    }

    function test_getPriceIn_last(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        (uint256 onemaLast, uint48 onemaTimestamp) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.LAST
        );
        (uint256 twomaLast, uint48 twomaTimestamp) = price.getPrice(
            address(twoma),
            IPRICEv2.Variant.LAST
        );

        // Get last price of ONEMA in TWOMA
        (uint256 price_, uint48 timestamp) = price.getPriceIn(
            address(onema),
            address(twoma),
            IPRICEv2.Variant.LAST
        );

        assertEq(price_, (onemaLast * (10 ** price.decimals())) / twomaLast);
        assertEq(timestamp, onemaTimestamp < twomaTimestamp ? onemaTimestamp : twomaTimestamp);

        // Update feeds and expect the LAST variant to remain unchanged until observations are stored.
        onemaUsdPriceFeed.setLatestAnswer(int256(9e8));
        twomaUsdPriceFeed.setLatestAnswer(int256(30e8));
        twomaEthPriceFeed.setLatestAnswer(int256(0.015e18));

        (price_, timestamp) = price.getPriceIn(
            address(onema),
            address(twoma),
            IPRICEv2.Variant.LAST
        );

        assertEq(price_, (onemaLast * (10 ** price.decimals())) / twomaLast);
        assertEq(timestamp, onemaTimestamp < twomaTimestamp ? onemaTimestamp : twomaTimestamp);
    }

    function testRevert_getPriceIn_last_sameAsset_nonMovingAverageAsset(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_MovingAverageNotStored.selector, address(weth))
        );
        price.getPriceIn(address(weth), address(weth), IPRICEv2.Variant.LAST);
    }

    function test_getPriceIn_movingAverage_sameAsset_returnsUnitPriceAndLastTimestamp(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        (, uint48 movingAverageTimestamp) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.MOVINGAVERAGE
        );
        vm.warp(block.timestamp + 6 hours);

        (uint256 pairPrice, uint48 pairTimestamp) = price.getPriceIn(
            address(onema),
            address(onema),
            IPRICEv2.Variant.MOVINGAVERAGE
        );

        // Same-asset MOVINGAVERAGE should still normalize to one unit of account.
        assertEq(pairPrice, uint256(10 ** price.decimals()), "Pair price should remain unit price");
        // Timestamp should come from the moving-average observation path, not the current block.
        assertEq(
            pairTimestamp,
            movingAverageTimestamp,
            "Pair timestamp should match the moving-average observation timestamp"
        );
    }

    function testRevert_getPriceIn_movingAverage_sameAsset_nonMovingAverageAsset(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_MovingAverageNotStored.selector, address(weth))
        );
        price.getPriceIn(address(weth), address(weth), IPRICEv2.Variant.MOVINGAVERAGE);
    }

    function testRevert_getPriceIn_last_unconfiguredAsset() public {
        // No base assets

        // Try to call getPriceIn with the current variant and expect revert on the first asset
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(onema)
        );
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), IPRICEv2.Variant.LAST);

        // Add onema so it is approved
        _addOneMAAsset(1, 10);

        // Try to call getPriceIn with the current variant and expect revert on the second asset
        err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(twoma));
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), IPRICEv2.Variant.LAST);
    }

    function testRevert_getPriceIn_last_movingAverageNotStored(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Asset side without stored MA must fail for LAST quotes.
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_MovingAverageNotStored.selector, address(weth))
        );
        price.getPriceIn(address(weth), address(onema), IPRICEv2.Variant.LAST);

        // Quote asset without stored MA must also fail.
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_MovingAverageNotStored.selector, address(weth))
        );
        price.getPriceIn(address(onema), address(weth), IPRICEv2.Variant.LAST);

        // Another non-MA quote asset should follow the same revert behavior.
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_MovingAverageNotStored.selector, address(alpha))
        );
        price.getPriceIn(address(onema), address(alpha), IPRICEv2.Variant.LAST);
    }

    function test_getPriceIn_last_withoutDirectPairCache_usesStoredObservations(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        IPRICEv2.Asset memory onemaData = price.getAssetData(address(onema));
        IPRICEv2.Asset memory twomaData = price.getAssetData(address(twoma));

        uint256 onemaLastIdx = onemaData.nextObsIndex == 0
            ? onemaData.numObservations - 1
            : onemaData.nextObsIndex - 1;
        uint256 twomaLastIdx = twomaData.nextObsIndex == 0
            ? twomaData.numObservations - 1
            : twomaData.nextObsIndex - 1;

        uint256 expectedPrice = (onemaData.obs[onemaLastIdx] * (10 ** price.decimals())) /
            twomaData.obs[twomaLastIdx];
        uint48 expectedTimestamp = onemaData.lastObservationTime < twomaData.lastObservationTime
            ? onemaData.lastObservationTime
            : twomaData.lastObservationTime;

        (uint256 price_, uint48 timestamp_) = price.getPriceIn(
            address(onema),
            address(twoma),
            IPRICEv2.Variant.LAST
        );

        assertEq(price_, expectedPrice, "Pair LAST should use stored observations");
        assertEq(timestamp_, expectedTimestamp, "Pair LAST timestamp should use observation time");
    }

    function test_getPriceIn_movingAverage(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Manually calculate moving average of ohm in reserve (both are configured for Moving Averages)
        IPRICEv2.Asset memory ohmData = price.getAssetData(address(ohm));
        IPRICEv2.Asset memory reserveData = price.getAssetData(address(reserve));
        uint48 start = uint48(block.timestamp);

        uint256 ohmMovingAverage = ohmData.cumulativeObs / ohmData.numObservations;
        uint256 reserveMovingAverage = reserveData.cumulativeObs / reserveData.numObservations;
        uint256 expectedMovingAverage = (ohmMovingAverage * 10 ** price.decimals()) /
            reserveMovingAverage;

        // Get moving average price of ohm in reserve
        (uint256 movingAverage, uint48 timestamp) = price.getPriceIn(
            address(ohm),
            address(reserve),
            IPRICEv2.Variant.MOVINGAVERAGE
        );

        assertEq(movingAverage, expectedMovingAverage);
        assertEq(timestamp, start);

        // Warp forward in time and expect to get the same value since no new prices are stored
        vm.warp(uint256(start) + 1 hours);
        (movingAverage, timestamp) = price.getPriceIn(
            address(ohm),
            address(reserve),
            IPRICEv2.Variant.MOVINGAVERAGE
        );

        assertEq(movingAverage, expectedMovingAverage);
        assertEq(timestamp, start);
    }

    function test_getPriceIn_variants_useMovingAverageTrue_consistentSemantics(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        IPRICEv2.Asset memory onemaData = price.getAssetData(address(onema));
        IPRICEv2.Asset memory twomaData = price.getAssetData(address(twoma));

        uint256 scale = 10 ** price.decimals();
        uint48 expectedHistoricalTimestamp = onemaData.lastObservationTime <
            twomaData.lastObservationTime
            ? onemaData.lastObservationTime
            : twomaData.lastObservationTime;

        {
            (uint256 onemaCurrent, uint48 onemaCurrentTimestamp) = price.getPrice(
                address(onema),
                IPRICEv2.Variant.CURRENT
            );
            (uint256 twomaCurrent, uint48 twomaCurrentTimestamp) = price.getPrice(
                address(twoma),
                IPRICEv2.Variant.CURRENT
            );

            uint48 expectedCurrentTimestamp = onemaCurrentTimestamp < twomaCurrentTimestamp
                ? onemaCurrentTimestamp
                : twomaCurrentTimestamp;

            (uint256 currentPairPrice, uint48 currentPairTimestamp) = price.getPriceIn(
                address(onema),
                address(twoma),
                IPRICEv2.Variant.CURRENT
            );

            assertEq(
                currentPairPrice,
                (onemaCurrent * scale) / twomaCurrent,
                "CURRENT pair should derive from per-asset CURRENT values"
            );
            assertEq(
                currentPairTimestamp,
                expectedCurrentTimestamp,
                "CURRENT pair timestamp should be the min current timestamp"
            );
        }

        {
            uint256 onemaLastIdx = onemaData.nextObsIndex == 0
                ? onemaData.numObservations - 1
                : onemaData.nextObsIndex - 1;
            uint256 twomaLastIdx = twomaData.nextObsIndex == 0
                ? twomaData.numObservations - 1
                : twomaData.nextObsIndex - 1;

            (uint256 lastPairPrice, uint48 lastPairTimestamp) = price.getPriceIn(
                address(onema),
                address(twoma),
                IPRICEv2.Variant.LAST
            );

            assertEq(
                lastPairPrice,
                (onemaData.obs[onemaLastIdx] * scale) / twomaData.obs[twomaLastIdx],
                "LAST pair should use only last observations"
            );
            assertEq(
                lastPairTimestamp,
                expectedHistoricalTimestamp,
                "LAST pair timestamp should be the min observation timestamp"
            );
        }

        {
            uint256 onemaMovingAverage = onemaData.cumulativeObs / onemaData.numObservations;
            uint256 twomaMovingAverage = twomaData.cumulativeObs / twomaData.numObservations;

            (uint256 movingAveragePairPrice, uint48 movingAveragePairTimestamp) = price.getPriceIn(
                address(onema),
                address(twoma),
                IPRICEv2.Variant.MOVINGAVERAGE
            );

            assertEq(
                movingAveragePairPrice,
                (onemaMovingAverage * scale) / twomaMovingAverage,
                "MOVINGAVERAGE pair should use only moving-average values"
            );
            assertEq(
                movingAveragePairTimestamp,
                expectedHistoricalTimestamp,
                "MOVINGAVERAGE pair timestamp should be the min observation timestamp"
            );
        }
    }

    function testRevert_getPriceIn_movingAverage_notStored(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Try to call getPriceIn with the moving average variant and expect revert on the first asset
        bytes memory err = abi.encodeWithSelector(
            IPRICEv2.PRICE_MovingAverageNotStored.selector,
            address(weth)
        );
        // Asset side without stored MA must fail for MOVINGAVERAGE quotes.
        vm.expectRevert(err);
        price.getPriceIn(address(weth), address(ohm), IPRICEv2.Variant.MOVINGAVERAGE);

        // Try with positions reversed
        // Quote asset without stored MA must also fail.
        vm.expectRevert(err);
        price.getPriceIn(address(ohm), address(weth), IPRICEv2.Variant.MOVINGAVERAGE);

        // Both assets without stored moving averages should also revert.
        // Both non-MA assets: fail on the first argument (weth).
        vm.expectRevert(err);
        price.getPriceIn(address(weth), address(alpha), IPRICEv2.Variant.MOVINGAVERAGE);

        err = abi.encodeWithSelector(
            IPRICEv2.PRICE_MovingAverageNotStored.selector,
            address(alpha)
        );
        // Both non-MA assets in reverse order: fail on the first argument (alpha).
        vm.expectRevert(err);
        price.getPriceIn(address(alpha), address(weth), IPRICEv2.Variant.MOVINGAVERAGE);
    }

    function testRevert_getPriceIn_movingAverage_unconfiguredAsset() public {
        // No base assets

        // Try to call getPriceIn with the current variant and expect revert on the first asset
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(onema)
        );
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), IPRICEv2.Variant.MOVINGAVERAGE);

        // Add onema so it is approved
        _addOneMAAsset(1, 10);

        // Try to call getPriceIn with the current variant and expect revert on the second asset
        err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(twoma));
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), IPRICEv2.Variant.MOVINGAVERAGE);
    }

    // ==========  getPriceIn (asset, base) ========== //

    function testRevert_getPriceIn_conv_unconfiguredAssets() public {
        // No base assets

        // Add onema so it is approved
        _addOneMAAsset(1, 10);

        // Try to call getPriceIn and expect revert on the second asset
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(twoma)
        );
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma));

        // Reverse positions
        vm.expectRevert(err);
        price.getPriceIn(address(twoma), address(onema));
    }

    function testRevert_getPriceIn_conv_sameAsset_unconfiguredAsset() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(onema))
        );
        price.getPriceIn(address(onema), address(onema));
    }

    function test_getPriceIn_conv_sameAsset_configuredAsset_returnsUnitPrice(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        uint256 pairPrice = price.getPriceIn(address(weth), address(weth));

        // Same-asset convenience quotes should normalize to one unit of account.
        assertEq(pairPrice, uint256(10 ** price.decimals()), "Pair price should remain unit price");
    }

    function testRevert_getPriceIn_conv_priceZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Timestamp is the same as initialized so it should return the stored (last) value, which would be the current one

        // Move forward in time so that the stored value is stale for both assets
        vm.warp(uint256(block.timestamp) + 1);

        // Set WETH price to zero
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to call getPriceIn and expect revert on the first
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(weth));
        vm.expectRevert(err);
        price.getPriceIn(address(weth), address(alpha));

        // Reverse positions
        vm.expectRevert(err);
        price.getPriceIn(address(alpha), address(weth));

        // Set ALPHA price to zero
        alphaUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to call getPriceIn and expect revert on whichever asset is first
        vm.expectRevert(err);
        price.getPriceIn(address(weth), address(alpha));

        // Reverse positions
        err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(alpha));
        vm.expectRevert(err);
        price.getPriceIn(address(alpha), address(weth));
    }

    function test_getPriceIn_conv_whenFeedsChangeInSameBlock_returnsCurrentPairValue(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        ethUsdPriceFeed.setLatestAnswer(int256(2100e8));
        ethUsdPriceFeed.setTimestamp(block.timestamp);
        alphaUsdPriceFeed.setLatestAnswer(int256(60e8));
        alphaUsdPriceFeed.setTimestamp(block.timestamp);

        uint256 price_ = price.getPriceIn(address(weth), address(alpha));
        assertEq(price_, uint256(35e18));
    }

    function test_getPriceIn_conv_whenBothAssetsUseCurrentVariant_updatesWithFeedChangesSameBlock(
        uint256 nonce_
    ) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // WETH/ALPHA are not moving-average assets, so convenience pricing uses current feeds.
        uint256 price_ = price.getPriceIn(address(weth), address(alpha));

        assertEq(price_, uint256(40e18));

        // Change price of both assets
        ethUsdPriceFeed.setLatestAnswer(int256(1600e8));
        alphaUsdPriceFeed.setLatestAnswer(int256(20e8));

        // Since there is no stored-observation branch for these assets, the updated feeds are used.
        price_ = price.getPriceIn(address(weth), address(alpha));
        assertEq(price_, uint256(80e18));
    }

    function test_getPriceIn_conv_whenBothAssetsUseCurrentVariant_afterTimestampAdvance_updatesWithFeedChanges(
        uint256 nonce_
    ) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Warp forward in time so that the stored prices are stale (but non-zero)
        vm.warp(block.timestamp + 1);

        // Change price of both assets
        ethUsdPriceFeed.setLatestAnswer(int256(1600e8));
        alphaUsdPriceFeed.setLatestAnswer(int256(20e8));

        // Non-moving-average assets resolve to current feeds regardless of timestamp.
        uint256 price_ = price.getPriceIn(address(weth), address(alpha));
        assertEq(price_, uint256(80e18));
    }

    function test_getPriceIn_conv_whenAssetHasFreshObservation_stillUsesCurrentForBothLegs(
        uint256 nonce_
    ) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        vm.warp(block.timestamp + 1);

        // Refresh ONEMA only.
        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        // Change live feed values after observation storage.
        onemaUsdPriceFeed.setLatestAnswer(int256(16e8));
        alphaUsdPriceFeed.setLatestAnswer(int256(20e8));

        // Convenience pricing always resolves from CURRENT for both legs.
        uint256 price_ = price.getPriceIn(address(onema), address(alpha));
        uint256 onemaCurrent = price.getPrice(address(onema));
        uint256 alphaCurrent = price.getPrice(address(alpha));

        assertEq(price_, (onemaCurrent * (10 ** price.decimals())) / alphaCurrent);
    }

    function test_getPriceIn_conv_whenQuoteHasFreshObservation_stillUsesCurrentForBothLegs(
        uint256 nonce_
    ) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        vm.warp(block.timestamp + 1);

        // Refresh ONEMA only.
        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        // Change live feed values after observation storage.
        onemaUsdPriceFeed.setLatestAnswer(int256(16e8));
        ethUsdPriceFeed.setLatestAnswer(int256(1600e8));

        // Convenience pricing always resolves from CURRENT for both legs.
        uint256 price_ = price.getPriceIn(address(weth), address(onema));
        uint256 wethCurrent = price.getPrice(address(weth));
        uint256 onemaCurrent = price.getPrice(address(onema));

        assertEq(price_, (wethCurrent * (10 ** price.decimals())) / onemaCurrent);
    }

    // ==========  storeObservation  ========== //

    function testRevert_storeObservation_unconfiguredAsset() public {
        // No base assets

        // Try to call storeObservation for an asset not added and expect revert
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(twoma)
        );
        vm.expectRevert(err);
        vm.prank(priceWriter);
        price.storeObservation(address(twoma));
    }

    function testRevert_storeObservation_priceZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);

        // Set onema price feed to zero
        onemaUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to call storeObservation with onema and expect revert (single feed)
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(onema));
        vm.expectRevert(err);
        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        // Set ohm price feeds to zero (including ETH/USD which is used by recursive feeds)
        ohmUsdPriceFeed.setLatestAnswer(int256(0));
        ohmEthPriceFeed.setLatestAnswer(int256(0));
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        // Strategy fails with SimpleStrategy_PriceCountInvalid when all prices are zero
        // This is wrapped in PRICE_StrategyFailed
        // Construct the full expected revert data
        bytes memory innerError = abi.encodeWithSelector(
            bytes4(keccak256("SimpleStrategy_PriceCountInvalid(uint256,uint256)")),
            uint256(0),
            uint256(3)
        );
        bytes memory expectedRevert = abi.encodeWithSelector(
            bytes4(keccak256("PRICE_StrategyFailed(address,bytes)")),
            address(ohm),
            innerError
        );
        vm.expectRevert(expectedRevert);
        vm.prank(priceWriter);
        price.storeObservation(address(ohm));
    }

    function testRevert_storeObservation_onlyPermissioned(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);

        // Try to call storeObservation with non-permissioned address (this contract) and expect revert
        bytes memory err = abi.encodeWithSelector(
            Module.Module_PolicyNotPermitted.selector,
            address(this)
        );
        vm.expectRevert(err);
        price.storeObservation(address(onema));

        // Try to call storeObservation with permissioned address (priceWriter) and expect to succeed
        vm.prank(priceWriter);
        price.storeObservation(address(onema));
    }

    function test_storeObservation_insufficientTimeElapsed(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);

        // Cache the current price of onema
        vm.prank(priceWriter);
        price.storeObservation(address(onema));
        uint48 start = uint48(block.timestamp);

        // Warp forward in time and store a new price
        vm.warp(uint256(start) + 1);
        onemaUsdPriceFeed.setLatestAnswer(int256(2001e8));

        // Call the function
        // Should not revert
        vm.prank(priceWriter);
        price.storeObservation(address(onema));
    }

    function test_storeObservation_noMovingAverage_reverts(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);

        // Try to call storeObservation with a non-moving average asset expect revert
        bytes memory err = abi.encodeWithSignature(
            "PRICE_MovingAverageNotStored(address)",
            address(weth)
        );
        vm.expectRevert(err);
        vm.prank(priceWriter);
        price.storeObservation(address(weth));
    }

    function test_storeObservation_movingAverage(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Get current cached data for onema from initialization
        uint48 start = uint48(block.timestamp);
        IPRICEv2.Asset memory asset = price.getAssetData(address(onema));
        _assertAssetData(
            asset,
            true,
            true,
            true,
            uint32(5 days),
            start,
            0,
            15,
            asset.cumulativeObs,
            "initial"
        );
        assertEq(asset.obs[14], uint256(5e18));
        // cumulative obs is random based on the nonce, store for comparison after new value added (which will be larger)
        uint256 cumulativeObs = asset.cumulativeObs;

        // Warp forward in time and store a new price
        onemaUsdPriceFeed.setLatestAnswer(int256(50e8));

        vm.warp(uint256(start) + OBSERVATION_FREQUENCY);
        onemaUsdPriceFeed.setTimestamp(block.timestamp);

        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        // Get updated cached data for onema
        asset = price.getAssetData(address(onema));
        _assertAssetData(
            asset,
            true,
            true,
            true,
            uint32(5 days),
            uint48(start + OBSERVATION_FREQUENCY),
            1,
            15,
            asset.cumulativeObs,
            "after first store"
        );
        assertEq(asset.obs[0], uint256(50e18));
        assertEq(asset.obs[14], uint256(5e18));
        assertGt(asset.cumulativeObs, cumulativeObs); // new cumulative obs is larger than the previous one due to adding a high ob

        // Add several new values to test ring buffer
        for (uint256 i; i < 14; i++) {
            asset = price.getAssetData(address(onema));

            vm.warp(block.timestamp + OBSERVATION_FREQUENCY);
            onemaUsdPriceFeed.setTimestamp(block.timestamp);

            vm.prank(priceWriter);
            price.storeObservation(address(onema));
        }

        uint48 lastStore = uint48(block.timestamp);

        // Get updated cached data for onema
        asset = price.getAssetData(address(onema));
        _assertAssetData(
            asset,
            true,
            true,
            true,
            uint32(5 days),
            lastStore,
            0,
            15,
            uint256(50e18) * 15,
            "after loop"
        );
        assertEq(asset.obs[14], uint256(50e18));
        assertEq(asset.cumulativeObs, uint256(50e18) * 15); // all data points should be 50e18 now

        // Warp forward in time and store a new price
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);
        onemaUsdPriceFeed.setTimestamp(block.timestamp);

        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        // Get updated cached data for onema
        asset = price.getAssetData(address(onema));
        assertEq(asset.nextObsIndex, 1, "next index should be 1 since we added a new value");

        // Store price again and check that event is emitted
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);
        vm.prank(priceWriter);
        vm.expectEmit(true, false, false, true);
        emit PriceStored(address(onema), uint256(50e18), uint48(block.timestamp));
        price.storeObservation(address(onema));
    }

    function test_storeObservation_includesMovingAverage() public {
        // Initial observations that return the same value as the Chainlink price feeds
        uint256[] memory observations = new uint256[](2);
        observations[0] = 5e18;
        observations[1] = 5e18;

        // Add an asset that uses the moving average
        // The strategy is the average price of the single price feed
        // 2 observations are stored at any time
        vm.startPrank(priceWriter);
        ChainlinkPriceFeeds.OneFeedParams memory onemaFeedParams = ChainlinkPriceFeeds
            .OneFeedParams(onemaUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(onemaFeedParams) // bytes memory params_
        );

        price.addAsset(
            address(onema), // address asset_
            true, // bool storeMovingAverage_ // track ONEMA MA
            true, // bool useMovingAverage_ // use MA in strategy
            uint32(observations.length) * OBSERVATION_FREQUENCY, // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            observations, // uint256[] memory observations_
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                ISimplePriceFeedStrategy.getAveragePrice.selector,
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds // Component[] feeds_
        );

        vm.stopPrank();

        // Warp forward in time and store a new price (5e8)
        uint48 start = uint48(block.timestamp);
        vm.warp(uint256(start) + OBSERVATION_FREQUENCY);
        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        // Check LAST observation value.
        // 1. Initial observations passed to addAsset: [5e18, 5e18]. Total = 10e18.
        // 2. storeObservation called: feed returns 5e18.
        // 3. Oldest observation at nextObsIndex (0) is 5e18.
        // 4. New cumulativeObs = 10e18 + 5e18 - 5e18 = 10e18.
        // 5. MA = 10e18 / 2 = 5e18.
        uint256 t1_expectedPrice = 5e18;
        (uint256 t1_lastPrice, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(t1_lastPrice, t1_expectedPrice, "t1: last price did not match");

        // Check MA
        (uint256 t1_movingAverage, ) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.MOVINGAVERAGE
        );
        assertEq(t1_movingAverage, 5e18, "t1: moving average did not match");

        // Warp forward in time and store a different price (10e8)
        vm.warp(uint256(start) + OBSERVATION_FREQUENCY + OBSERVATION_FREQUENCY);
        onemaUsdPriceFeed.setLatestAnswer(int256(10e8));
        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        // Check LAST observation value.
        // 1. Current cumulativeObs = 10e18.
        // 2. storeObservation called: feed now returns 10e18.
        // 3. Oldest observation at nextObsIndex (1) is 5e18.
        // 4. New cumulativeObs = 10e18 + 10e18 - 5e18 = 15e18.
        // 5. MA = 15e18 / 2 = 7.5e18.
        uint256 t2_expectedPrice = 10e18;
        (uint256 t2_lastPrice, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(t2_lastPrice, t2_expectedPrice, "t2: last price did not match");

        // Check MA
        (uint256 t2_movingAverage, ) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.MOVINGAVERAGE
        );
        assertEq(t2_movingAverage, 7.5e18, "t2: moving average did not match");
    }

    function test_storeObservation_twoPriceFeeds_includesMovingAverage() public {
        // Initial observations that return the same value as the Chainlink price feeds
        uint256[] memory observations = new uint256[](2);
        observations[0] = 5e18;
        observations[1] = 5e18;

        // Add an asset that uses the moving average
        // The strategy is the average price of the two price feeds
        // 2 observations are stored at any time
        vm.startPrank(priceWriter);
        ChainlinkPriceFeeds.OneFeedParams memory onemaFeedParams = ChainlinkPriceFeeds
            .OneFeedParams(onemaUsdPriceFeed, uint48(24 hours));
        ChainlinkPriceFeeds.OneFeedParams memory ohmUsdFeedParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(onemaFeedParams) // bytes memory params_
        );
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ohmUsdFeedParams) // bytes memory params_
        );

        price.addAsset(
            address(onema), // address asset_
            true, // bool storeMovingAverage_ // track ONEMA MA
            true, // bool useMovingAverage_ // use MA in strategy
            uint32(observations.length) * OBSERVATION_FREQUENCY, // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            observations, // uint256[] memory observations_
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                ISimplePriceFeedStrategy.getAveragePrice.selector,
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds // Component[] feeds_
        );

        vm.stopPrank();

        // Warp forward in time and store a new price
        uint48 start = uint48(block.timestamp);
        vm.warp(uint256(start) + OBSERVATION_FREQUENCY);
        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        // Check LAST observation value.
        // 1. Initial observations passed to addAsset: [5e18, 5e18]. Total = 10e18.
        // 2. storeObservation called:
        //    - Feed1 = 5e18, Feed2 = 10e18.
        //    - Aggregated observation price = Average(5, 10) = 7.5e18.
        // 3. Oldest observation at nextObsIndex (0) is 5e18.
        // 4. New cumulativeObs = 10e18 + 7.5e18 - 5e18 = 12.5e18.
        // 5. MA = 12.5e18 / 2 = 6.25e18.
        uint256 t1_expectedPrice = 7.5e18;
        (uint256 t1_lastPrice, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(t1_lastPrice, t1_expectedPrice, "t1: last price did not match");

        // Check MA
        (uint256 t1_movingAverage, ) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.MOVINGAVERAGE
        );
        assertEq(t1_movingAverage, 6.25e18, "t1: moving average did not match");

        // Warp forward in time and store a new price
        vm.warp(uint256(start) + OBSERVATION_FREQUENCY + OBSERVATION_FREQUENCY);
        onemaUsdPriceFeed.setLatestAnswer(int256(20e8));
        vm.prank(priceWriter);
        price.storeObservation(address(onema));

        // Check LAST observation value.
        // 1. Current cumulativeObs = 12.5e18.
        // 2. storeObservation called:
        //    - Feed1 = 20e18, Feed2 = 10e18.
        //    - Aggregated observation price = Average(20, 10) = 15e18.
        // 3. Oldest observation at nextObsIndex (1) is 5e18.
        // 4. New cumulativeObs = 12.5e18 + 15e18 - 5e18 = 22.5e18.
        // 5. MA = 22.5e18 / 2 = 11.25e18.
        uint256 t2_expectedPrice = 15e18;
        (uint256 t2_lastPrice, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(t2_lastPrice, t2_expectedPrice, "t2: last price did not match");

        // Check MA
        (uint256 t2_movingAverage, ) = price.getPrice(
            address(onema),
            IPRICEv2.Variant.MOVINGAVERAGE
        );
        assertEq(t2_movingAverage, 11.25e18, "t2: moving average did not match");
    }

    function _addWEth() internal {
        // Add one asset to the price module
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        vm.prank(priceWriter);
        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_ // don't track WETH MA
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function test_storeObservations(uint256 nonce_) public {
        // Add a non-MA asset
        _addWEth();

        // Add an MA asset
        _addOneMAAsset(nonce_, 10);

        uint48 start = uint48(block.timestamp);

        // Warp forward in time and store a new price
        vm.warp(uint256(start) + OBSERVATION_FREQUENCY);
        onemaUsdPriceFeed.setLatestAnswer(int256(50e8));
        onemaUsdPriceFeed.setTimestamp(block.timestamp);

        vm.prank(priceWriter);
        price.storeObservations();

        // Non-MA assets should not have any effect
        IPRICEv2.Asset memory asset = price.getAssetData(address(weth));
        _assertAssetData(asset, true, false, false, 0, 0, 0, 0, 0, "weth");

        // MA asset should have been updated
        asset = price.getAssetData(address(onema));
        _assertAssetData(
            asset,
            true,
            true,
            true,
            uint32(10 * OBSERVATION_FREQUENCY),
            uint48(start + OBSERVATION_FREQUENCY),
            1,
            10,
            asset.cumulativeObs,
            "onema"
        );
    }

    // ========== addAsset ========== //

    function testRevert_addAsset_exists(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        // Try and add the an asset again
        vm.startPrank(priceWriter);

        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetAlreadyApproved(address)",
            address(weth)
        );
        vm.expectRevert(err);

        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_ // don't track WETH MA
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_unregisteredNonContract() public {
        address nonContract = makeAddr("NON_CONTRACT");

        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        // Try and add the unregistered non-contract asset
        vm.startPrank(priceWriter);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_InvalidAsset.selector, nonContract));

        price.addAsset(
            nonContract, // address asset_
            false, // bool storeMovingAverage_ // don't track WETH MA
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function test_addAsset_registeredNonContract() public {
        address nonContract = makeAddr("NON_CONTRACT");

        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ethParams)
        );

        vm.prank(priceWriter);
        price.registerNonContractAsset(nonContract);
        vm.startPrank(priceWriter);
        price.addAsset(
            nonContract,
            false,
            false,
            uint32(0),
            uint48(0),
            new uint256[](0),
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)),
            feeds
        );
        vm.stopPrank();

        assertEq(price.isAssetApproved(nonContract), true, "Non-contract asset should be approved");
    }

    function test_addAsset_registeredNonContract_thenDeployContractAtSameAddress_getPriceStillWorks()
        public
    {
        address nonContract = makeAddr("NON_CONTRACT");

        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory initialFeeds = new IPRICEv2.Component[](1);
        initialFeeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ethParams)
        );

        vm.prank(priceWriter);
        price.registerNonContractAsset(nonContract);

        vm.prank(priceWriter);
        price.addAsset(
            nonContract,
            false,
            false,
            uint32(0),
            uint48(0),
            new uint256[](0),
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)),
            initialFeeds
        );

        assertEq(price.getPrice(nonContract), 2000e18, "Price should use the initial feed");

        MockERC20 replacement = new MockERC20("Replacement", "RPL", 6);
        vm.etch(nonContract, address(replacement).code);

        assertEq(
            price.getPrice(nonContract),
            2000e18,
            "Price should still work after code is deployed at the address"
        );
    }

    function test_removeAsset_registeredNonContract_thenDeployContractAtSameAddress_thenDeregisters()
        public
    {
        address nonContract = makeAddr("NON_CONTRACT");

        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ethParams)
        );

        vm.prank(priceWriter);
        price.registerNonContractAsset(nonContract);

        vm.prank(priceWriter);
        price.addAsset(
            nonContract,
            false,
            false,
            uint32(0),
            uint48(0),
            new uint256[](0),
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)),
            feeds
        );

        MockERC20 replacement = new MockERC20("Replacement", "RPL", 6);
        vm.etch(nonContract, address(replacement).code);

        vm.startPrank(priceWriter);
        price.removeAsset(nonContract);
        price.unregisterNonContractAsset(nonContract);
        vm.stopPrank();

        assertEq(
            price.isAssetApproved(nonContract),
            false,
            "Non-contract asset should be removable after code is deployed at the address"
        );
        assertEq(
            price.isNonContractAsset(nonContract),
            false,
            "Non-contract asset should be deregisterable after asset removal"
        );
    }

    function testRevert_addAsset_notPermissioned() public {
        MockERC20 asset = new MockERC20("Asset", "ASSET", 18);

        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            ethUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        // Try and add the asset
        bytes memory err = abi.encodeWithSelector(
            Module.Module_PolicyNotPermitted.selector,
            address(this)
        );
        vm.expectRevert(err);

        price.addAsset(
            address(asset), // address asset_
            false, // bool storeMovingAverage_ // don't track WETH MA
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_noStrategy_noMovingAverage_multiplePriceFeeds() public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        ChainlinkPriceFeeds.TwoFeedParams memory ohmFeedTwoParams = ChainlinkPriceFeeds
            .TwoFeedParams(ohmEthPriceFeed, uint48(24 hours), ethUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 selector
            abi.encode(ohmFeedTwoParams) // bytes memory params
        );

        // Try and add the asset
        vm.startPrank(priceWriter);

        // Reverts as there is no strategy, but no MA + 2 price feeds > 1 requires a strategy
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsStrategyInsufficient(address,bytes,uint256,bool)",
            address(weth),
            abi.encode(IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0))),
            2,
            false
        );
        vm.expectRevert(err);

        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_useMovingAverage_noStoreMovingAverage() public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        // Try and add the asset
        vm.startPrank(priceWriter);

        // Reverts as useMovingAverage is enabled, but storeMovingAverage is not
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsStoreMovingAverageRequired(address)",
            address(weth)
        );
        vm.expectRevert(err);

        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_
            true, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            IPRICEv2.Component( // Add a strategy so that addAsset has no other reason to revert
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    ISimplePriceFeedStrategy.getAveragePrice.selector,
                    abi.encode(0) // no params required
                ), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_noStrategy_movingAverage_singlePriceFeed() public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        // Try and add the asset
        vm.startPrank(priceWriter);

        // Reverts as there is no strategy, but MA + single price feed > 1 requires a strategy
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsStrategyInsufficient(address,bytes,uint256,bool)",
            address(weth),
            abi.encode(IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0))),
            1,
            true
        );
        vm.expectRevert(err);

        price.addAsset(
            address(weth), // address asset_
            true, // bool storeMovingAverage_
            true, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function test_addAsset_noStrategy_noMovingAverage_singlePriceFeed() public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        IPRICEv2.Component memory strategyEmpty = IPRICEv2.Component(
            toSubKeycode(bytes20(0)),
            bytes4(0),
            abi.encode(0)
        );

        // Try and add the asset
        vm.startPrank(priceWriter);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetAdded(address(weth));

        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            strategyEmpty, // Component memory strategy_
            feeds //
        );

        uint256 currentPrice = price.getPrice(address(weth));
        assertEq(currentPrice, 10e18);

        // Configuration should be stored correctly
        IPRICEv2.Asset memory asset = price.getAssetData(address(weth));
        _assertAssetData(asset, true, false, false, 0, 0, 0, 0, 0, "weth");
        assertEq(asset.strategy, abi.encode(strategyEmpty), "strategy");
        assertEq(asset.feeds, abi.encode(feeds), "feeds");

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_MovingAverageNotStored.selector, address(weth))
        );
        price.getPrice(address(weth), IPRICEv2.Variant.LAST);
    }

    function testRevert_addAsset_noStrategy_noMovingAverage_singlePriceFeed_nonZeroMovingAverageDuration()
        public
    {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ohmFeedOneParams)
        );

        IPRICEv2.Component memory strategyEmpty = IPRICEv2.Component(
            toSubKeycode(bytes20(0)),
            bytes4(0),
            abi.encode(0)
        );

        vm.startPrank(priceWriter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsMovingAverageDurationInvalid.selector,
                address(weth),
                uint32(2 * OBSERVATION_FREQUENCY),
                uint48(0)
            )
        );
        price.addAsset(
            address(weth),
            false, // storeMovingAverage_
            false, // useMovingAverage_
            uint32(2 * OBSERVATION_FREQUENCY), // must be zero when not storing MA
            uint48(0),
            new uint256[](0), // observations_ must be empty
            strategyEmpty,
            feeds
        );
        vm.stopPrank();
    }

    function testRevert_addAsset_noStrategy_noMovingAverage_singlePriceFeed_nonZeroLastObservationTime()
        public
    {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ohmFeedOneParams)
        );

        IPRICEv2.Component memory strategyEmpty = IPRICEv2.Component(
            toSubKeycode(bytes20(0)),
            bytes4(0),
            abi.encode(0)
        );

        vm.startPrank(priceWriter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsLastObservationTimeInvalid.selector,
                address(weth),
                uint48(block.timestamp + 1),
                uint48(0),
                uint48(0)
            )
        );
        price.addAsset(
            address(weth),
            false, // storeMovingAverage_
            false, // useMovingAverage_
            uint32(0),
            uint48(block.timestamp + 1), // must be zero when not storing MA
            new uint256[](0), // observations_ must be empty
            strategyEmpty,
            feeds
        );
        vm.stopPrank();
    }

    function testRevert_addAsset_noStrategy_noMovingAverage_singlePriceFeed_singleObservation()
        public
    {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        uint256[] memory observations = new uint256[](1);
        observations[0] = 9e18; // Junk number that should be different to anything from price feeds
        uint48 observationTimestamp = uint48(block.timestamp) - 1;

        vm.startPrank(priceWriter);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsInvalidObservationCount.selector,
                address(weth),
                observations.length,
                uint256(0),
                uint256(0)
            )
        );
        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            observationTimestamp, // uint48 lastObservationTime_
            observations, // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_noStrategy_noMovingAverage_singlePriceFeed_multipleObservations()
        public
    {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        uint256[] memory observations = new uint256[](2);
        observations[0] = 9e18;
        observations[1] = 8e18;

        vm.startPrank(priceWriter);

        // Reverts because no observations are permitted when moving average storage is disabled
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsInvalidObservationCount(address,uint256,uint256,uint256)",
            address(weth),
            observations.length,
            0,
            0
        );
        vm.expectRevert(err);

        // Try and add the asset
        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            observations, // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_noStrategy_noMovingAverage_singlePriceFeed_singleObservationZero()
        public
    {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        uint256[] memory observations = new uint256[](1);
        observations[0] = 0;

        vm.startPrank(priceWriter);

        // Reverts because no observations are permitted when moving average storage is disabled
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsInvalidObservationCount(address,uint256,uint256,uint256)",
            address(weth),
            observations.length,
            0,
            0
        );
        vm.expectRevert(err);

        // Try and add the asset
        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            observations, // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_noStrategy_noMovingAverage_singlePriceFeed_singleObservationZeroTimestamp()
        public
    {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        uint256[] memory observations = new uint256[](1);
        observations[0] = 9e18;

        vm.startPrank(priceWriter);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsInvalidObservationCount.selector,
                address(weth),
                observations.length,
                uint256(0),
                uint256(0)
            )
        );

        // Try and add the asset
        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            observations, // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function test_addAsset_strategy_movingAverage_multiplePriceFeeds(uint256 nonce_) public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        ChainlinkPriceFeeds.TwoFeedParams memory ohmFeedTwoParams = ChainlinkPriceFeeds
            .TwoFeedParams(ohmEthPriceFeed, uint48(24 hours), ethUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 selector
            abi.encode(ohmFeedTwoParams) // bytes memory params
        );

        // Try and add the asset
        vm.startPrank(priceWriter);

        uint256[] memory obs = _makeRandomObservations(weth, feeds[0], nonce_, uint256(2));

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetAdded(address(weth));

        price.addAsset(
            address(weth), // address asset_
            true, // bool storeMovingAverage_
            true, // bool useMovingAverage_
            uint32(16 hours), // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            obs, // uint256[] memory observations_
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                ISimplePriceFeedStrategy.getAveragePrice.selector,
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds //
        );

        // LAST returns the most recent stored observation.
        uint256 expectedPrice = obs[1];
        (uint256 price_, ) = price.getPrice(address(weth), IPRICEv2.Variant.LAST);
        assertEq(price_, expectedPrice);
    }

    function testRevert_addAsset_multiplePriceFeeds_oneSubmoduleCallFails(uint256 nonce_) public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        ChainlinkPriceFeeds.TwoFeedParams memory ohmFeedTwoParams = ChainlinkPriceFeeds
            .TwoFeedParams(ohmEthPriceFeed, uint48(24 hours), ethUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            bytes4(0), // incorrect bytes4 selector
            abi.encode(ohmFeedTwoParams) // bytes memory params
        );
        uint256[] memory obs = _makeRandomObservations(weth, feeds[0], nonce_, uint256(2));

        // Try and add the asset
        vm.startPrank(priceWriter);

        // Reverts as one price feed call will fail due to invalid selector
        bytes memory err = abi.encodeWithSignature(
            "PRICE_PriceFeedCallFailed(address)",
            address(weth)
        );
        vm.expectRevert(err);

        price.addAsset(
            address(weth), // address asset_
            true, // bool storeMovingAverage_
            true, // bool useMovingAverage_
            uint32(16 hours), // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            obs, // uint256[] memory observations_
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                ISimplePriceFeedStrategy.getFirstNonZeroPrice.selector, // Won't complain if there is only one result
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_singlePriceFeed_movingAverage_submoduleCallReturnsZero(
        uint256 nonce_
    ) public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );
        uint256[] memory obs = _makeRandomObservations(weth, feeds[0], nonce_, uint256(2));

        // Mock the price feed to return 0
        // The Chainlink price feed will revert upon a 0 price, so this circumvents that
        vm.mockCall(
            address(chainlinkPrice),
            abi.encodeWithSelector(ChainlinkPriceFeeds.getOneFeedPrice.selector),
            abi.encode(uint256(0))
        );

        // Try and add the asset
        vm.startPrank(priceWriter);

        // Reverts as one price feed call will fail due to zero price
        bytes memory err = abi.encodeWithSelector(
            IPRICEv2.PRICE_PriceFeedCallFailed.selector,
            address(weth)
        );
        vm.expectRevert(err);

        price.addAsset(
            address(weth), // address asset_
            true, // bool storeMovingAverage_
            true, // bool useMovingAverage_
            uint32(16 hours), // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            obs, // uint256[] memory observations_
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                ISimplePriceFeedStrategy.getFirstNonZeroPrice.selector, // Won't complain if there is only one result
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_singlePriceFeed_noMovingAverage_submoduleCallReturnsZero() public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );
        uint256[] memory obs = new uint256[](0);

        // Mock the price feed to return 0
        // The Chainlink price feed will revert upon a 0 price, so this circumvents that
        vm.mockCall(
            address(chainlinkPrice),
            abi.encodeWithSelector(ChainlinkPriceFeeds.getOneFeedPrice.selector),
            abi.encode(uint256(0))
        );

        // Try and add the asset
        vm.startPrank(priceWriter);

        // Reverts as one price feed call will fail due to zero price
        bytes memory err = abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(weth));
        vm.expectRevert(err);

        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            0, // uint48 lastObservationTime_
            obs, // uint256[] memory observations_
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_multiplePriceFeeds_movingAverage_oneSubmoduleCallReturnsZero(
        uint256 nonce_
    ) public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        ChainlinkPriceFeeds.TwoFeedParams memory ohmFeedTwoParams = ChainlinkPriceFeeds
            .TwoFeedParams(ohmEthPriceFeed, uint48(24 hours), ethUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 selector
            abi.encode(ohmFeedTwoParams) // bytes memory params
        );
        uint256[] memory obs = _makeRandomObservations(weth, feeds[0], nonce_, uint256(2));

        // Mock the price feed to return 0
        // The Chainlink price feed will revert upon a 0 price, so this circumvents that
        vm.mockCall(
            address(chainlinkPrice),
            abi.encodeWithSelector(ChainlinkPriceFeeds.getOneFeedPrice.selector),
            abi.encode(uint256(0))
        );

        // Try and add the asset
        vm.startPrank(priceWriter);

        // Reverts as one price feed call will fail due to zero price
        bytes memory err = abi.encodeWithSelector(
            IPRICEv2.PRICE_PriceFeedCallFailed.selector,
            address(weth)
        );
        vm.expectRevert(err);

        price.addAsset(
            address(weth), // address asset_
            true, // bool storeMovingAverage_
            true, // bool useMovingAverage_
            uint32(16 hours), // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            obs, // uint256[] memory observations_
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                ISimplePriceFeedStrategy.getFirstNonZeroPrice.selector, // Won't complain if there is only one result
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_multiplePriceFeeds_noMovingAverage_oneSubmoduleCallReturnsZero()
        public
    {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        ChainlinkPriceFeeds.TwoFeedParams memory ohmFeedTwoParams = ChainlinkPriceFeeds
            .TwoFeedParams(ohmEthPriceFeed, uint48(24 hours), ethUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 selector
            abi.encode(ohmFeedTwoParams) // bytes memory params
        );
        uint256[] memory obs = new uint256[](0);

        // Mock the price feed to return 0
        // The Chainlink price feed will revert upon a 0 price, so this circumvents that
        vm.mockCall(
            address(chainlinkPrice),
            abi.encodeWithSelector(ChainlinkPriceFeeds.getOneFeedPrice.selector),
            abi.encode(uint256(0))
        );

        // Try and add the asset
        vm.startPrank(priceWriter);

        // Reverts as one price feed call will fail due to zero price
        bytes memory err = abi.encodeWithSelector(
            IPRICEv2.PRICE_PriceFeedCallFailed.selector,
            address(weth)
        );
        vm.expectRevert(err);

        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            obs, // uint256[] memory observations_
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                ISimplePriceFeedStrategy.getFirstNonZeroPrice.selector, // Won't complain if there is only one result
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds //
        );
    }

    function test_addAsset_strategy_movingAverage_singlePriceFeed(uint256 nonce_) public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        IPRICEv2.Component memory averageStrategy = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            ISimplePriceFeedStrategy.getAveragePrice.selector,
            abi.encode(0) // no params required
        );

        uint256[] memory observations = _makeRandomObservations(weth, feeds[0], nonce_, uint256(2));
        uint256 expectedCumulativeObservations = observations[0] + observations[1];

        // Try and add the asset
        vm.startPrank(priceWriter);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetAdded(address(weth));

        price.addAsset(
            address(weth), // address asset_
            true, // bool storeMovingAverage_
            true, // bool useMovingAverage_
            uint32(16 hours), // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            observations, // uint256[] memory observations_
            averageStrategy, // Component memory strategy_
            feeds //
        );

        // LAST returns the most recent stored observation.
        uint256 expectedPrice = observations[1];
        (uint256 price_, ) = price.getPrice(address(weth), IPRICEv2.Variant.LAST);
        assertEq(price_, expectedPrice);

        // Configuration should be stored correctly
        IPRICEv2.Asset memory asset = price.getAssetData(address(weth));
        _assertAssetData(
            asset,
            true,
            true,
            true,
            uint32(16 hours),
            uint48(block.timestamp),
            0,
            2,
            expectedCumulativeObservations,
            "weth"
        );
        assertEq(asset.strategy, abi.encode(averageStrategy), "strategy");
        assertEq(asset.feeds, abi.encode(feeds), "feeds");
    }

    function test_addAsset_withMedianStrategy_twoFeeds_movingAverage(uint256 nonce_) public {
        // Test that 2 feeds + moving average + getMedian works correctly
        // getMedian requires 3 inputs: 2 feeds + 1 moving average
        // This verifies that the validation in addAsset() includes the moving average
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        ChainlinkPriceFeeds.TwoFeedParams memory ohmFeedTwoParams = ChainlinkPriceFeeds
            .TwoFeedParams(ohmEthPriceFeed, uint48(24 hours), ethUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ohmFeedOneParams)
        );
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(ohmFeedTwoParams)
        );

        IPRICEv2.Component memory medianStrategy = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            ISimplePriceFeedStrategy.getMedianPrice.selector,
            abi.encode(0)
        );

        uint256[] memory observations = _makeRandomObservations(weth, feeds[0], nonce_, uint256(2));

        vm.startPrank(priceWriter);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetAdded(address(weth));

        price.addAsset(
            address(weth),
            true, // storeMovingAverage
            true, // useMovingAverage
            uint32(16 hours),
            uint48(block.timestamp),
            observations,
            medianStrategy,
            feeds
        );

        // Verify the asset was added correctly
        IPRICEv2.Asset memory asset = price.getAssetData(address(weth));
        assertEq(asset.approved, true);
        assertEq(asset.storeMovingAverage, true);
        assertEq(asset.useMovingAverage, true);

        // Feed1 = 10e18 and Feed2 = 10e18.
        // MA = (obs[0] + obs[1]) / 2 = (10.512e18 + 10e18) / 2 = 10.256e18.
        // Median strategy sorts [10e18, 10e18, 10.256e18] and selects middle => 10e18.
        uint256 expectedPrice = 10e18;
        (uint256 price_, ) = price.getPrice(address(weth), IPRICEv2.Variant.LAST);
        assertEq(price_, expectedPrice, "Cached price should equal median of feeds and MA");

        vm.stopPrank();
    }

    function test_addAsset_withMedianStrategy_twoFeeds_noMovingAverage_reverts() public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        ChainlinkPriceFeeds.TwoFeedParams memory ohmFeedTwoParams = ChainlinkPriceFeeds
            .TwoFeedParams(ohmEthPriceFeed, uint48(24 hours), ethUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ohmFeedOneParams)
        );
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(ohmFeedTwoParams)
        );

        IPRICEv2.Component memory medianStrategy = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            ISimplePriceFeedStrategy.getMedianPrice.selector, // Requires 3 inputs
            abi.encode(true) // strict mode
        );

        // Expect a revert as the strategy requires 3 inputs
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_StrategyFailed.selector,
                address(weth),
                abi.encodeWithSelector(
                    ISimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector,
                    2,
                    3
                )
            )
        );

        vm.startPrank(priceWriter);
        price.addAsset(
            address(weth),
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0),
            uint48(0),
            new uint256[](0),
            medianStrategy,
            feeds
        );
    }

    function test_addAsset_withStrategy_singlePriceFeed_reverts() public {
        // Bug #2 test: Strategy with single price source should be rejected
        // Currently this test demonstrates the bug - the configuration is accepted
        // when it should revert with PRICE_ParamsStrategyNotSupported
        // Using getFirstNonZeroPrice which would support a single price feed,
        // but the strategy should still be rejected since it's unnecessary
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ohmFeedOneParams)
        );

        IPRICEv2.Component memory strategies = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            ISimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        // Expect a revert as the strategy is not supported
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStrategyNotSupported.selector,
                address(weth)
            )
        );

        vm.startPrank(priceWriter);
        price.addAsset(
            address(weth),
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0),
            uint48(0),
            new uint256[](0),
            strategies, // Strategy provided but only 1 input source
            feeds
        );

        vm.stopPrank();
    }

    function test_addAsset_withAverageStrategy_withMovingAverage_singlePriceFeed(
        uint256 nonce_
    ) public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(ohmFeedOneParams)
        );

        IPRICEv2.Component memory strategies = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            ISimplePriceFeedStrategy.getAveragePrice.selector, // Requires 2+ inputs
            abi.encode(0)
        );

        uint256[] memory observations = _makeRandomObservations(weth, feeds[0], nonce_, uint256(2));

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetAdded(address(weth));

        vm.startPrank(priceWriter);
        price.addAsset(
            address(weth),
            true, // storeMovingAverage
            true, // useMovingAverage
            uint32(16 hours),
            uint48(block.timestamp),
            observations,
            strategies,
            feeds
        );

        vm.stopPrank();

        // Verify the asset was added correctly
        IPRICEv2.Asset memory asset = price.getAssetData(address(weth));
        assertEq(asset.approved, true);
        assertEq(asset.storeMovingAverage, true);
        assertEq(asset.useMovingAverage, true);

        uint256 expectedPrice = observations[1];
        (uint256 lastPrice, ) = price.getPrice(address(weth), IPRICEv2.Variant.LAST);
        assertEq(lastPrice, expectedPrice, "LAST should equal latest stored observation");
    }

    function testRevert_addAsset_invalidPriceFeed() public {
        // Set up a new feed that will revert when run
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_ // Will revert as these parameters are not sufficient
        );

        IPRICEv2.Component memory strategyEmpty = IPRICEv2.Component(
            toSubKeycode(bytes20(0)),
            bytes4(0),
            abi.encode(0)
        );

        // No observations are permitted when moving average storage is disabled.
        // This forces addAsset to validate via live feed lookup.
        uint256[] memory observations = new uint256[](0);

        // Try and add the asset
        vm.startPrank(priceWriter);
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(weth));
        vm.expectRevert(err);

        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            observations, // uint256[] memory observations_
            strategyEmpty, // Component memory strategy_
            feeds //
        );
    }

    // ========== removeAsset ========== //

    function testRevert_removeAsset_notPermissioned(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Try and remove the asset
        bytes memory err = abi.encodeWithSelector(
            Module.Module_PolicyNotPermitted.selector,
            address(this)
        );
        vm.expectRevert(err);

        price.removeAsset(address(weth));
    }

    function testRevert_removeAsset_notApproved() public {
        // No assets registered

        // Try and remove the asset
        vm.startPrank(priceWriter);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(weth)
        );
        vm.expectRevert(err);

        price.removeAsset(address(weth));
    }

    function test_removeAsset(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Remove the asset
        vm.startPrank(priceWriter);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetRemoved(address(weth));

        price.removeAsset(address(weth));

        // Asset data is removed
        IPRICEv2.Asset memory asset = price.getAssetData(address(weth));
        assertEq(asset.approved, false);

        address[] memory assetAddresses = price.getAssets();
        for (uint256 i; i < assetAddresses.length; i++) {
            assertFalse(
                assetAddresses[i] == address(weth),
                "assetAddresses[i] should not equal address(weth) after removeAsset(address(weth))"
            );
        }
    }

    function test_removeAsset_clearsStoredObservations(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        IPRICEv2.Asset memory oldAsset = price.getAssetData(address(onema));
        // Sanity check fixture: ONEMA begins with MA storage and seeded observations.
        assertEq(oldAsset.storeMovingAverage, true, "precondition: MA should be stored");
        assertGt(oldAsset.obs.length, 0, "precondition: observations should exist");

        vm.startPrank(priceWriter);

        vm.expectEmit(true, false, false, true);
        emit AssetRemoved(address(onema));

        price.removeAsset(address(onema));

        IPRICEv2.Asset memory asset = price.getAssetData(address(onema));
        // Removing the asset should clear all stored moving-average observation state.
        _assertAssetData(asset, false, false, false, 0, 0, 0, 0, 0, "onema");

        address[] memory assetAddresses = price.getAssets();
        for (uint256 i; i < assetAddresses.length; i++) {
            assertFalse(
                assetAddresses[i] == address(onema),
                "assetAddresses[i] should not equal address(onema) after removeAsset(address(onema))"
            );
        }
    }

    function test_addAsset_useMovingAverageFalse() public {
        uint256[] memory observations = new uint256[](2);
        observations[0] = 5e18;
        observations[1] = 5e18;

        vm.startPrank(priceWriter);
        ChainlinkPriceFeeds.OneFeedParams memory onemaFeedParams = ChainlinkPriceFeeds
            .OneFeedParams(onemaUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(onemaFeedParams)
        );

        onemaUsdPriceFeed.setLatestAnswer(int256(10e8)); // Feed returns 10e18

        // Expected price:
        // 1. Initial observations: [5e18, 5e18]. MA = 5e18.
        // 2. Feed returns: 10e18.
        // 3. storeMovingAverage is true, but useMovingAverage is false.
        // 4. Since there is only one feed and useMovingAverage is false, the number of sources is 1.
        // 5. Strategy must be empty. Result is simply the feed price = 10e18.

        price.addAsset(
            address(onema),
            true, // storeMovingAverage
            false, // useMovingAverage (MA should be excluded from strategy)
            uint32(observations.length) * OBSERVATION_FREQUENCY,
            uint48(block.timestamp),
            observations,
            _emptyStrategy(),
            feeds
        );
        vm.stopPrank();

        (uint256 cachedPrice, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(cachedPrice, 5e18, "LAST should equal latest stored observation");
    }

    function test_addAsset_useMovingAverageTrue() public {
        uint256[] memory observations = new uint256[](2);
        observations[0] = 5e18;
        observations[1] = 5e18;

        vm.startPrank(priceWriter);
        ChainlinkPriceFeeds.OneFeedParams memory onemaFeedParams = ChainlinkPriceFeeds
            .OneFeedParams(onemaUsdPriceFeed, uint48(24 hours));

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(onemaFeedParams)
        );

        onemaUsdPriceFeed.setLatestAnswer(int256(10e8)); // Feed returns 10e18

        // Expected inclusive price:
        // 1. Initial observations: [5e18, 5e18]. MA = 5e18.
        // 2. Feed returns: 10e18.
        // 3. Strategy result: Average(Feed=10e18, MA=5e18) = (10 + 5) / 2 = 7.5e18.

        price.addAsset(
            address(onema),
            true, // storeMovingAverage
            true, // useMovingAverage
            uint32(observations.length) * OBSERVATION_FREQUENCY,
            uint48(block.timestamp),
            observations,
            _simpleStrategyAverage(),
            feeds
        );
        vm.stopPrank();

        (uint256 cachedPrice, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(cachedPrice, 5e18, "LAST should equal latest stored observation");
    }

    // Note: Tests for updateAsset are in updateAsset.t.sol
}
/// forge-lint: disable-end(mixed-case-variable,mixed-case-function)
