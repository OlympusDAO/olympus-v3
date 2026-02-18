// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {PriceV2BaseTest} from "./PriceV2BaseTest.sol";

// Mocks
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {Kernel, Module} from "src/Kernel.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";
import {toSubKeycode, fromSubKeycode} from "src/Submodules.sol";

contract PriceV2UpdateAssetTest is PriceV2BaseTest {
    using FullMath for uint256;

    // Additional test assets (reusing existing feeds from PriceV2BaseTest)
    MockERC20 internal testAsset1;
    MockERC20 internal testAsset2;

    // Store asset addresses for test use
    address internal asset_SingleFeed_NoStrategy_NoMA;
    address internal asset_SingleFeed_Strategy_WithMA;
    address internal asset_SingleFeed_NoStrategy_StoreMA;
    address internal asset_MultipleFeeds_Strategy_StoreMA;
    address internal asset_MultipleFeeds_Strategy_WithMA;

    function setUp() public virtual override {
        super.setUp();

        // Deploy additional test assets for update tests (reusing existing feeds)
        testAsset1 = new MockERC20("Test Asset 1", "TST1", 18);
        testAsset2 = new MockERC20("Test Asset 2", "TST2", 18);
    }

    // Helper function to create an empty strategy component
    function _emptyStrategy() internal pure returns (IPRICEv2.Component memory) {
        return IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), bytes(""));
    }

    // ========== MODIFIERS: Test Infrastructure (State Setup) ========== //

    // Asset with 1 feed, no strategy, no MA
    modifier givenAsset_SingleFeed_NoStrategy_NoMA() {
        vm.startPrank(priceWriter);

        ChainlinkPriceFeeds.OneFeedParams memory feedParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed, // Reuse existing feed
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(feedParams)
        );

        price.addAsset(
            address(testAsset1),
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0), // movingAverageDuration
            uint48(0), // lastObservationTime
            new uint256[](0), // observations
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // strategy
            feeds
        );

        asset_SingleFeed_NoStrategy_NoMA = address(testAsset1);
        vm.stopPrank();
        _;
    }

    // Asset with 1 feed, strategy, MA used
    modifier givenAsset_SingleFeed_Strategy_WithMA() {
        vm.startPrank(priceWriter);

        ChainlinkPriceFeeds.OneFeedParams memory feedParams = ChainlinkPriceFeeds.OneFeedParams(
            onemaUsdPriceFeed, // Reuse existing feed
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(feedParams)
        );

        price.addAsset(
            address(testAsset1),
            true, // storeMovingAverage
            true, // useMovingAverage
            uint32(2 * OBSERVATION_FREQUENCY), // movingAverageDuration (2 observations)
            uint48(block.timestamp),
            _makeRandomObservations(testAsset1, feeds[0], 1, uint256(2)), // 2 observations
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                abi.encode(0)
            ), // strategy
            feeds
        );

        asset_SingleFeed_Strategy_WithMA = address(testAsset1);
        vm.stopPrank();
        _;
    }

    // Asset with 1 feed, no strategy, MA stored but not used
    modifier givenAsset_SingleFeed_NoStrategy_StoreMA() {
        vm.startPrank(priceWriter);

        ChainlinkPriceFeeds.OneFeedParams memory feedParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed, // Reuse existing feed
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(feedParams)
        );

        price.addAsset(
            address(testAsset1),
            true, // storeMovingAverage
            false, // useMovingAverage (not used in strategy)
            uint32(2 * OBSERVATION_FREQUENCY), // movingAverageDuration (2 observations)
            uint48(block.timestamp),
            _makeRandomObservations(testAsset1, feeds[0], 1, uint256(2)), // 2 observations
            IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no strategy
            feeds
        );

        asset_SingleFeed_NoStrategy_StoreMA = address(testAsset1);
        vm.stopPrank();
        _;
    }

    // Asset with >1 feeds, strategy, MA stored but not used
    modifier givenAsset_MultipleFeeds_Strategy_StoreMA() {
        vm.startPrank(priceWriter);

        ChainlinkPriceFeeds.OneFeedParams memory feed1Params = ChainlinkPriceFeeds.OneFeedParams(
            twomaUsdPriceFeed, // Reuse existing feed
            uint48(24 hours)
        );

        ChainlinkPriceFeeds.TwoFeedParams memory feed2Params = ChainlinkPriceFeeds.TwoFeedParams(
            twomaEthPriceFeed, // Reuse existing feed
            uint48(24 hours),
            ethUsdPriceFeed, // Reuse existing feed
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(feed1Params)
        );
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(feed2Params)
        );

        price.addAsset(
            address(testAsset1),
            true, // storeMovingAverage
            false, // useMovingAverage (not used in strategy)
            uint32(2 * OBSERVATION_FREQUENCY), // movingAverageDuration (2 observations)
            uint48(block.timestamp),
            _makeRandomObservations(testAsset1, feeds[0], 1, uint256(2)), // 2 observations
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                SimplePriceFeedStrategy.getAveragePrice.selector,
                abi.encode(0)
            ), // strategy
            feeds
        );

        asset_MultipleFeeds_Strategy_StoreMA = address(testAsset1);
        vm.stopPrank();
        _;
    }

    // Asset with >1 feeds, strategy, MA used
    modifier givenAsset_MultipleFeeds_Strategy_WithMA() {
        vm.startPrank(priceWriter);

        ChainlinkPriceFeeds.OneFeedParams memory feed1Params = ChainlinkPriceFeeds.OneFeedParams(
            twomaUsdPriceFeed, // Reuse existing feed
            uint48(24 hours)
        );

        ChainlinkPriceFeeds.TwoFeedParams memory feed2Params = ChainlinkPriceFeeds.TwoFeedParams(
            twomaEthPriceFeed, // Reuse existing feed
            uint48(24 hours),
            ethUsdPriceFeed, // Reuse existing feed
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(feed1Params)
        );
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(feed2Params)
        );

        price.addAsset(
            address(testAsset1),
            true, // storeMovingAverage
            true, // useMovingAverage
            uint32(2 * OBSERVATION_FREQUENCY), // movingAverageDuration (2 observations)
            uint48(block.timestamp),
            _makeRandomObservations(testAsset1, feeds[0], 1, uint256(2)), // 2 observations
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                SimplePriceFeedStrategy.getAveragePrice.selector,
                abi.encode(0)
            ), // strategy
            feeds
        );

        asset_MultipleFeeds_Strategy_WithMA = address(testAsset1);
        vm.stopPrank();
        _;
    }

    // ========== TESTS ========== //

    // given the caller is not permissioned
    //  [X] it reverts - not permissioned

    function test_givenCallerNotPermissioned_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), bytes("")),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        // Expect error
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );

        // Call function
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // given the asset is not configured
    //  [X] it reverts - not approved

    function test_whenAssetNotApproved_reverts() public {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true, // Set updateFeeds to true to avoid "no updates" revert
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](1), // Need at least one feed
            strategy: IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), bytes("")),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        // Set up valid feed
        ChainlinkPriceFeeds.OneFeedParams memory feedParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed,
            uint48(24 hours)
        );
        params.feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(feedParams)
        );

        // Expect error
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(testAsset1))
        );

        // Call function
        vm.prank(priceWriter);
        price.updateAsset(address(testAsset1), params);
    }

    // when the price feed configuration is being updated
    //  when the number of price feeds is 0
    //   [X] it reverts - there must be price feeds

    function test_whenUpdatingPriceFeeds_whenZeroFeeds_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0), // Zero feeds
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsPriceFeedInsufficient.selector,
                asset_SingleFeed_NoStrategy_NoMA
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    //  when the submodule of a price feed is not installed
    //   [X] it reverts - submodule not installed

    function test_whenUpdatingPriceFeeds_whenInvalidSubmodule_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        // Create a feed with a non-existent submodule
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.NONEXISTENT"), // Invalid submodule
            bytes4(0),
            bytes("")
        );

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_SubmoduleNotInstalled.selector,
                toSubKeycode("PRICE.NONEXISTENT")
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    //  when the number of price feeds is 1
    //   when the moving average configuration is not being updated
    //    given the moving average is used
    //     when the strategy configuration is not being updated
    //      given the existing strategy configuration is empty
    //       not possible
    //      given the existing strategy configuration is not empty
    //       [X] it replaces the price feed configuration
    //       [X] it emits an AssetPriceFeedsUpdated event

    function test_whenUpdatingPriceFeeds_whenSingleFeed_givenMovingAverageUsed_givenStrategyNotEmpty()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        // Get MA values
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);

        // Set up new feed
        ChainlinkPriceFeeds.OneFeedParams memory newFeedParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed, // Different feed
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(newFeedParams)
        );

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectEmit(true, false, false, true);
        emit AssetPriceFeedsUpdated(asset_SingleFeed_Strategy_WithMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);

        // Verify feed was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);
        IPRICEv2.Component[] memory feeds = abi.decode(assetData.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 1, "feeds length");
        assertEq(feeds[0].params, abi.encode(newFeedParams), "Feed params not updated");

        // Verify strategy is the same
        IPRICEv2.Component memory strategy = abi.decode(assetData.strategy, (IPRICEv2.Component));
        assertEq(
            fromSubKeycode(strategy.target),
            bytes20("PRICE.SIMPLESTRATEGY"),
            "strategy target"
        );
        assertEq(
            strategy.selector,
            ISimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            "strategy selector"
        );

        // Verify moving average is the same
        assertEq(assetData.useMovingAverage, true, "useMovingAverage");
        assertEq(assetData.storeMovingAverage, true, "storeMovingAverage");
        assertEq(assetData.movingAverageDuration, 2, "movingAverageDuration");
        assertEq(
            assetData.lastObservationTime,
            oldAssetData.lastObservationTime,
            "lastObservationTime"
        );
        assertEq(assetData.cumulativeObs, oldAssetData.cumulativeObs, "cumulativeObs");
    }

    //     when the strategy configuration is being updated
    //      when the updated strategy configuration is empty
    //       [X] it reverts - strategy required

    function test_whenUpdatingPriceFeeds_whenUpdatingStrategy_whenSinglePriceFeed_givenMovingAverageUsed_whenStrategyEmpty_reverts()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        // Set up new feed
        ChainlinkPriceFeeds.OneFeedParams memory newFeedParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed, // Different feed
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(newFeedParams)
        );

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStrategyInsufficient.selector,
                asset_SingleFeed_Strategy_WithMA,
                bytes(""),
                uint256(1), // 1 feed being updated
                true // useMovingAverage
            )
        );

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);
    }

    //      when the updated strategy configuration is not empty
    //       [X] it replaces the price feed configuration
    //       [X] it replaces the strategy configuration
    //       [X] it emits an AssetPriceFeedsUpdated event
    //       [X] it emits an AssetStrategyUpdated event

    function test_whenUpdatingPriceFeeds_whenUpdatingStrategy_whenSingleFeed_givenMovingAverageUsed_whenStrategyNotEmpty()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        // Get MA values
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);

        // Set up new feed and new strategy
        ChainlinkPriceFeeds.OneFeedParams memory newFeedParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(newFeedParams)
        );

        IPRICEv2.Component memory newStrategy = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: newStrategy,
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectEmit(true, false, false, true);
        emit AssetPriceFeedsUpdated(asset_SingleFeed_Strategy_WithMA);
        vm.expectEmit(true, false, false, true);
        emit AssetPriceStrategyUpdated(asset_SingleFeed_Strategy_WithMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);

        // Verify feed was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);
        IPRICEv2.Component[] memory feeds = abi.decode(assetData.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 1, "feed count");
        assertEq(feeds[0].params, abi.encode(newFeedParams), "Feed params not updated");

        // Verify strategy was updated
        IPRICEv2.Component memory strategy = abi.decode(assetData.strategy, (IPRICEv2.Component));
        assertEq(
            fromSubKeycode(strategy.target),
            fromSubKeycode(newStrategy.target),
            "Strategy target not updated"
        );
        assertEq(strategy.selector, newStrategy.selector, "Strategy selector not updated");

        // Verify moving average is the same
        assertEq(assetData.useMovingAverage, true, "useMovingAverage");
        assertEq(assetData.storeMovingAverage, true, "storeMovingAverage");
        assertEq(assetData.movingAverageDuration, 2, "movingAverageDuration");
        assertEq(
            assetData.lastObservationTime,
            oldAssetData.lastObservationTime,
            "lastObservationTime"
        );
        assertEq(assetData.cumulativeObs, oldAssetData.cumulativeObs, "cumulativeObs");
    }

    //    given the moving average is not used
    //     when the strategy configuration is not being updated
    //      given the existing strategy configuration is empty
    //       [X] it replaces the price feed configuration
    //       [X] it emits an AssetPriceFeedsUpdated event

    function test_whenUpdatingPriceFeeds_whenSingleFeed_givenMovingAverageNotUsed_givenStrategyEmpty()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        // Get MA values
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);

        // Set up new feed
        ChainlinkPriceFeeds.OneFeedParams memory newFeedParams = ChainlinkPriceFeeds.OneFeedParams(
            onemaUsdPriceFeed, // Different feed
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(newFeedParams)
        );

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectEmit(true, false, false, true);
        emit AssetPriceFeedsUpdated(asset_SingleFeed_NoStrategy_NoMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);

        // Verify feed was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);
        IPRICEv2.Component[] memory feeds = abi.decode(assetData.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 1, "feed count");
        assertEq(feeds[0].params, abi.encode(newFeedParams), "Feed params not updated");

        // Verify strategy is the same
        IPRICEv2.Component memory strategy = abi.decode(assetData.strategy, (IPRICEv2.Component));
        IPRICEv2.Component memory oldStrategy = abi.decode(
            oldAssetData.strategy,
            (IPRICEv2.Component)
        );
        assertEq(
            fromSubKeycode(strategy.target),
            fromSubKeycode(oldStrategy.target),
            "Strategy target"
        );
        assertEq(strategy.selector, oldStrategy.selector, "Strategy selector");

        // Verify moving average is the same
        assertEq(assetData.useMovingAverage, true, "useMovingAverage");
        assertEq(assetData.storeMovingAverage, true, "storeMovingAverage");
        assertEq(assetData.movingAverageDuration, 2, "movingAverageDuration");
        assertEq(
            assetData.lastObservationTime,
            oldAssetData.lastObservationTime,
            "lastObservationTime"
        );
        assertEq(assetData.cumulativeObs, oldAssetData.cumulativeObs, "cumulativeObs");
    }

    //      given the existing strategy configuration is not empty
    //       not possible
    //     when the strategy configuration is being updated
    //      when the updated strategy configuration is empty
    //       [X] it replaces the price feed configuration
    //       [X] it replaces the strategy configuration
    //       [X] it emits an AssetPriceFeedsUpdated event
    //       [X] it emits an AssetStrategyUpdated event

    function test_whenUpdatingPriceFeeds_whenUpdatingStrategy_whenSingleFeed_whenStrategyEmpty()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        // Get MA values
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);

        // Set up new feed (though existing has no strategy, clearing is no-op but should work)
        ChainlinkPriceFeeds.OneFeedParams memory newFeedParams = ChainlinkPriceFeeds.OneFeedParams(
            onemaUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(newFeedParams)
        );

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectEmit(true, false, false, true);
        emit AssetPriceFeedsUpdated(asset_SingleFeed_NoStrategy_NoMA);
        vm.expectEmit(true, false, false, true);
        emit AssetPriceStrategyUpdated(asset_SingleFeed_NoStrategy_NoMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);

        // Verify feed was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);
        IPRICEv2.Component[] memory feeds = abi.decode(assetData.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 1, "feed count");
        assertEq(feeds[0].params, abi.encode(newFeedParams), "Feed params not updated");

        // Verify strategy is updated
        IPRICEv2.Component memory strategy = abi.decode(assetData.strategy, (IPRICEv2.Component));
        assertEq(fromSubKeycode(strategy.target), bytes20(""), "strategy target");
        assertEq(strategy.selector, bytes4(""), "strategy selector");

        // Verify moving average is the same
        assertEq(assetData.useMovingAverage, true, "useMovingAverage");
        assertEq(assetData.storeMovingAverage, true, "storeMovingAverage");
        assertEq(assetData.movingAverageDuration, 2, "movingAverageDuration");
        assertEq(
            assetData.lastObservationTime,
            oldAssetData.lastObservationTime,
            "lastObservationTime"
        );
        assertEq(assetData.cumulativeObs, oldAssetData.cumulativeObs, "cumulativeObs");
    }

    //      when the updated strategy configuration is not empty
    //       [X] it reverts - strategy not supported

    function test_whenUpdatingPriceFeeds_whenUpdatingStrategy_whenSinglePriceFeed_givenMovingAverageNotUsed_givenStrategyNotEmpty_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        // Set up new feed and attempt to set strategy
        ChainlinkPriceFeeds.OneFeedParams memory newFeedParams = ChainlinkPriceFeeds.OneFeedParams(
            onemaUsdPriceFeed,
            uint48(24 hours)
        );

        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(newFeedParams)
        );

        IPRICEv2.Component memory newStrategy = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: newStrategy,
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStrategyNotSupported.selector,
                asset_SingleFeed_NoStrategy_NoMA
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    //     when the strategy configuration is being updated
    //      when the updated strategy configuration is empty
    //       [ ] it reverts - strategy required
    //      when the updated strategy configuration is not empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the strategy configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetStrategyUpdated event
    //    given the moving average is not used
    //     when the strategy configuration is not being updated
    //      given the existing strategy configuration is empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //      given the existing strategy configuration is not empty
    //       not possible
    //     when the strategy configuration is being updated
    //      when the updated strategy configuration is empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the strategy configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetStrategyUpdated event
    //      when the updated strategy configuration is not empty
    //       [ ] it reverts - strategy not supported
    //   when the moving average configuration is being updated
    //    when the moving average is used
    //     when the strategy configuration is not being updated
    //      given the existing strategy configuration is empty
    //       [ ] it reverts - strategy required
    //      given the existing strategy configuration is not empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the moving average configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetMovingAverageUpdated event
    //     when the strategy configuration is being updated
    //      when the updated strategy configuration is empty
    //       [ ] it reverts - strategy required
    //      when the updated strategy configuration is not empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the moving average configuration
    //       [ ] it replaces the strategy configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetStrategyUpdated event
    //       [ ] it emits an AssetMovingAverageUpdated event
    //    when the moving average is not used
    //     when the strategy configuration is not being updated
    //      given the existing strategy configuration is empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the moving average configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetMovingAverageUpdated event
    //      given the existing strategy configuration is not empty
    //       [ ] it reverts - strategy not supported
    //     when the strategy configuration is being updated
    //      when the updated strategy configuration is empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the moving average configuration
    //       [ ] it replaces the strategy configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetStrategyUpdated event
    //       [ ] it emits an AssetMovingAverageUpdated event
    //      when the updated strategy configuration is not empty
    //       [ ] it reverts - strategy not supported
    //  when the number of price feeds is > 1
    //   when there are duplicate price feeds
    //    [ ] it reverts - duplicate price feed
    //   when the strategy configuration is not being updated
    //    given the existing strategy configuration is empty
    //     [ ] it reverts - strategy required
    //    given the existing strategy configuration is not empty
    //     [ ] it replaces the price feed configuration
    //     [ ] it emits an AssetPriceFeedsUpdated event
    //   when the strategy configuration is being updated
    //    when the updated strategy configuration is empty
    //     [ ] it reverts - strategy required
    //    when the updated strategy configuration is not empty
    //     [ ] it replaces the price feed configuration
    //     [ ] it replaces the strategy configuration
    //     [ ] it emits an AssetPriceFeedsUpdated event
    //     [ ] it emits an AssetStrategyUpdated event
    // when the asset strategy configuration is being updated
    //  given the strategy submodule is not installed
    //   [ ] it reverts
    //  when the submodule call reverts
    //   [ ] it reverts
    //  when the moving average configuration is being updated
    //   when useMovingAverage is true
    //    when the updated strategy configuration is empty
    //     [ ] it reverts - strategy required
    //    when the updated strategy configuration is not empty
    //     [ ] it replaces the strategy configuration
    //     [ ] it replaces the moving average configuration
    //     [ ] it emits an AssetStrategyUpdated event
    //     [ ] it emits an AssetMovingAverageUpdated event
    //   when useMovingAverage is false
    //    when the updated strategy configuration is empty
    //     given the number of price feeds is 1
    //      [ ] it replaces the strategy configuration
    //      [ ] it replaces the moving average configuration
    //      [ ] it emits an AssetStrategyUpdated event
    //      [ ] it emits an AssetMovingAverageUpdated event
    //     given the number of price feeds is > 1
    //      [ ] it reverts - strategy required
    //  when the moving average configuration is not being updated
    //   given useMovingAverage is true
    //    when the updated strategy configuration is empty
    //     [ ] it reverts - strategy required
    //    when the updated strategy configuration is not empty
    //     [ ] it replaces the strategy configuration
    //     [ ] it emits an AssetStrategyUpdated event
    //   given useMovingAverage is false
    //    when the updated strategy configuration is empty
    //     given the number of price feeds is 1
    //      [ ] it replaces the strategy configuration
    //      [ ] it emits an AssetStrategyUpdated event
    //     given the number of price feeds is > 1
    //      [ ] it reverts - strategy required
    // when the moving average configuration is being updated
    //  when the last observation time is in the future
    //   [ ] it reverts - invalid observation time
    //  when storeMovingAverage is true
    //   when the moving average duration is zero
    //    [ ] it reverts - invalid moving average duration
    //   when the moving average duration is not a multiple of the observation frequency
    //    [ ] it reverts - invalid moving average duration
    //   when the number of observations is not equal to duration / frequency
    //    [ ] it reverts - invalid observation count
    //   when there is a zero value observation
    //    [ ] it reverts - zero observation
    //   [ ] it replaces the moving average configuration
    //   [ ] it emits an AssetMovingAverageUpdated event
    //  when storeMovingAverage is false
    //   when useMovingAverage is true
    //    [ ] it reverts - storeMovingAverage required
    //   when the number of observations is > 1
    //    [ ] it reverts - invalid observation count
    //   when the number of observations is 1
    //    when the is a zero value observation
    //     [ ] it reverts - zero observation
    //    [ ] it stores the observation as the last price
    //    [ ] it replaces the moving average configuration
    //    [ ] it emits an AssetMovingAverageUpdated event
    //   when the number of observations is 0
    //    [ ] it stores the current price as the last price
    //    [ ] it replaces the moving average configuration
    //    [ ] it emits an AssetMovingAverageUpdated event
    // when getCurrentPrice fails
    //  [ ] it reverts
    // when the price feeds, strategy and moving average are not being updated
    //  [X] it reverts

    function test_whenNoUpdatesRequested_reverts() public givenAsset_SingleFeed_NoStrategy_NoMA {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), bytes("")),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        bytes memory err = abi.encodeWithSelector(
            IPRICEv2.PRICE_NoUpdatesRequested.selector,
            asset_SingleFeed_NoStrategy_NoMA
        );
        vm.expectRevert(err);

        vm.prank(priceWriter); // Use permissioned caller
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    //      when updateFeeds is false, feeds parameter is ignored
    //       [ ] it does not update price feeds
    //      when updateMovingAverage is false, MA parameters are ignored
    //       [ ] it does not update moving average configuration
    //      when updateStrategy is false, strategy parameter is ignored
    //       [ ] it does not update strategy
}
