// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(unwrapped-modifier-logic,mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.0;

// Test
import {PriceV2BaseTest} from "./PriceV2BaseTest.sol";

// Mocks
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

// Interfaces
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {Module} from "src/Kernel.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {toSubKeycode} from "src/Submodules.sol";

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
    address internal asset_MultipleFeeds_Strategy;

    function setUp() public virtual override {
        super.setUp();

        // Deploy additional test assets for update tests (reusing existing feeds)
        testAsset1 = new MockERC20("Test Asset 1", "TST1", 18);
        testAsset2 = new MockERC20("Test Asset 2", "TST2", 18);
    }

    // ========== MODIFIERS: Test Infrastructure (State Setup) ========== //

    // Asset with 1 feed, no strategy, no MA
    modifier givenAsset_SingleFeed_NoStrategy_NoMA() {
        vm.startPrank(priceWriter);

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = _singleFeed(alphaUsdPriceFeed);

        price.addAsset(
            address(testAsset1),
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0), // movingAverageDuration
            uint48(0), // lastObservationTime
            new uint256[](0), // observations
            _emptyStrategy(), // strategy
            feeds
        );

        asset_SingleFeed_NoStrategy_NoMA = address(testAsset1);
        vm.stopPrank();
        _;
    }

    // Asset with 1 feed, strategy, MA used
    modifier givenAsset_SingleFeed_Strategy_WithMA() {
        vm.startPrank(priceWriter);

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = _singleFeed(onemaUsdPriceFeed);

        price.addAsset(
            address(testAsset1),
            true, // storeMovingAverage
            true, // useMovingAverage
            uint32(2 * OBSERVATION_FREQUENCY), // movingAverageDuration (2 observations)
            uint48(block.timestamp),
            _makeRandomObservations(testAsset1, feeds[0], 1, uint256(2)), // 2 observations
            _simpleStrategyFirstNonZero(), // strategy
            feeds
        );

        asset_SingleFeed_Strategy_WithMA = address(testAsset1);
        vm.stopPrank();
        _;
    }

    // Asset with 1 feed, no strategy, MA stored but not used
    modifier givenAsset_SingleFeed_NoStrategy_StoreMA() {
        vm.startPrank(priceWriter);

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = _singleFeed(alphaUsdPriceFeed);

        price.addAsset(
            address(testAsset1),
            true, // storeMovingAverage
            false, // useMovingAverage (not used in strategy)
            uint32(2 * OBSERVATION_FREQUENCY), // movingAverageDuration (2 observations)
            uint48(block.timestamp),
            _makeRandomObservations(testAsset1, feeds[0], 1, uint256(2)), // 2 observations
            _emptyStrategy(), // no strategy
            feeds
        );

        asset_SingleFeed_NoStrategy_StoreMA = address(testAsset1);
        vm.stopPrank();
        _;
    }

    // Asset with >1 feeds, strategy, MA stored but not used
    modifier givenAsset_MultipleFeeds_Strategy_StoreMA() {
        vm.startPrank(priceWriter);

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = _singleFeed(twomaUsdPriceFeed);
        feeds[1] = _twoFeedMul(twomaEthPriceFeed, ethUsdPriceFeed);

        price.addAsset(
            address(testAsset1),
            true, // storeMovingAverage
            false, // useMovingAverage (not used in strategy)
            uint32(2 * OBSERVATION_FREQUENCY), // movingAverageDuration (2 observations)
            uint48(block.timestamp),
            _makeRandomObservations(testAsset1, feeds[0], 1, uint256(2)), // 2 observations
            _simpleStrategyAverage(), // strategy
            feeds
        );

        asset_MultipleFeeds_Strategy_StoreMA = address(testAsset1);
        vm.stopPrank();
        _;
    }

    // Asset with >1 feeds, strategy, MA used
    modifier givenAsset_MultipleFeeds_Strategy_WithMA() {
        vm.startPrank(priceWriter);

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = _singleFeed(twomaUsdPriceFeed);
        feeds[1] = _twoFeedMul(twomaEthPriceFeed, ethUsdPriceFeed);

        price.addAsset(
            address(testAsset1),
            true, // storeMovingAverage
            true, // useMovingAverage
            uint32(2 * OBSERVATION_FREQUENCY), // movingAverageDuration (2 observations)
            uint48(block.timestamp),
            _makeRandomObservations(testAsset1, feeds[0], 1, uint256(2)), // 2 observations
            _simpleStrategyAverage(), // strategy
            feeds
        );

        asset_MultipleFeeds_Strategy_WithMA = address(testAsset1);
        vm.stopPrank();
        _;
    }

    // Asset with >1 feeds, strategy, MA not stored
    modifier givenAsset_MultipleFeeds_Strategy() {
        vm.startPrank(priceWriter);

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = _singleFeed(twomaUsdPriceFeed);
        feeds[1] = _twoFeedMul(twomaEthPriceFeed, ethUsdPriceFeed);

        price.addAsset(
            address(testAsset1),
            false, // storeMovingAverage
            false, // useMovingAverage (not used in strategy)
            uint32(0), // movingAverageDuration (not used)
            uint48(0),
            new uint256[](0), // not used
            _simpleStrategyAverage(), // strategy
            feeds
        );

        asset_MultipleFeeds_Strategy = address(testAsset1);
        vm.stopPrank();
        _;
    }

    // ========== TESTS ========== //

    // given the caller is not permissioned: it reverts

    function test_givenCallerNotPermissioned_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
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

    // given the asset is not configured: it reverts

    function test_whenAssetNotApproved_reverts() public {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true, // Set updateFeeds to true to avoid "no updates" revert
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](1), // Need at least one feed
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        // Set up valid feed
        params.feeds[0] = _singleFeed(alphaUsdPriceFeed);

        // Expect error
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(testAsset1))
        );

        // Call function
        vm.prank(priceWriter);
        price.updateAsset(address(testAsset1), params);
    }

    // when the price feed configuration is being updated, when the number of price feeds is 0: it reverts

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
                asset_SingleFeed_NoStrategy_NoMA,
                0,
                1
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the price feed configuration is being updated, when the submodule of a price feed is not installed: it reverts

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
                asset_SingleFeed_NoStrategy_NoMA,
                abi.encode(toSubKeycode("PRICE.NONEXISTENT"))
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the price feed configuration is being updated, when the number of price feeds is 1, when the strategy configuration is not being updated, given useMovingAverage is true, given the existing strategy configuration is empty: not possible

    // when the price feed configuration is being updated, when the number of price feeds is 1, when the strategy configuration is not being updated, given useMovingAverage is true, given the existing strategy configuration is not empty: it replaces the price feed configuration, it emits an AssetPriceFeedsUpdated event

    function test_whenUpdatingPriceFeeds_whenSingleFeed_whenNotUpdatingStrategy_givenUseMovingAverageTrue_givenStrategyNotEmpty()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        // Get MA values
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);

        // Set up new feed
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = _singleFeed(alphaUsdPriceFeed);

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

        vm.expectEmit(true, true, true, true);
        emit AssetPriceFeedsUpdated(asset_SingleFeed_Strategy_WithMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);

        // Verify feed was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);
        _assertFeedsUpdated(assetData, newFeeds);

        // Verify strategy is same
        _assertStrategyUnchanged(oldAssetData, assetData);

        // Verify moving average is same
        _assertMovingAverageUnchanged(oldAssetData, assetData);

        // onemaUsdPriceFeed = 5e8 (8 decimals), normalized to PRICE decimals:
        // 5e8 * 1e10 = 5e18.
        // LAST should remain the pre-update latest stored observation.
        _assertLastPrice(asset_SingleFeed_Strategy_WithMA, 5e18, "LAST should remain unchanged");
    }

    // when the price feed configuration is being updated, when the number of price feeds is 1, when the strategy configuration is not being updated, given useMovingAverage is false, given the existing strategy configuration is empty: it replaces the price feed configuration, it emits an AssetPriceFeedsUpdated event

    function test_whenUpdatingPriceFeeds_whenSingleFeed_whenNotUpdatingStrategy_givenUseMovingAverageFalse_givenStrategyEmpty()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        // Get MA values
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);

        // Set up new feed
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = _singleFeed(alphaUsdPriceFeed);

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

        vm.expectEmit(true, true, true, true);
        emit AssetPriceFeedsUpdated(asset_SingleFeed_NoStrategy_NoMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);

        // Verify feed was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);
        _assertFeedsUpdated(assetData, newFeeds);

        // Verify strategy is the same
        _assertStrategyUnchanged(oldAssetData, assetData);

        // Verify moving average is the same
        _assertMovingAverageUnchanged(oldAssetData, assetData);
    }

    // when the price feed configuration is being updated, when the number of price feeds is 1, when the strategy configuration is not being updated, given useMovingAverage is false, given the existing strategy configuration is not empty: not possible

    // when the price feed configuration is being updated, when the number of price feeds is 1, when the strategy configuration is being updated, when useMovingAverage is false, when the strategy configuration is empty: it replaces the price feed configuration, it replaces the strategy configuration, it emits an AssetPriceFeedsUpdated event, it emits an AssetStrategyUpdated event

    function test_whenUpdatingPriceFeeds_whenSingleFeed_whenUpdatingStrategy_whenUseMovingAverageFalse_whenStrategyEmpty()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        // Get old asset values
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);

        // Set up new feed and new strategy
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = _singleFeed(alphaUsdPriceFeed);

        IPRICEv2.Component memory newStrategy = _emptyStrategy();

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

        vm.expectEmit(true, true, true, true);
        emit AssetPriceFeedsUpdated(asset_SingleFeed_Strategy_WithMA);
        vm.expectEmit(true, true, true, true);
        emit AssetPriceStrategyUpdated(asset_SingleFeed_Strategy_WithMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);

        // Verify feed was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);
        _assertFeedsUpdated(assetData, newFeeds);

        // Verify strategy was updated
        _assertStrategyUpdated(assetData, newStrategy, false);

        // Verify moving average is the same
        _assertMovingAverageUnchanged(oldAssetData, assetData);

        // onemaUsdPriceFeed = 5e8 (8 decimals), normalized to PRICE decimals:
        // 5e8 * 1e10 = 5e18.
        // LAST should remain the pre-update latest stored observation.
        _assertLastPrice(asset_SingleFeed_Strategy_WithMA, 5e18, "LAST should remain unchanged");
    }

    // when the price feed configuration is being updated, when the number of price feeds is 1, when the strategy configuration is being updated, when useMovingAverage is false, when the strategy configuration is not empty: reverts

    function test_whenUpdatingPriceFeeds_whenSingleFeed_whenUpdatingStrategy_whenUseMovingAverageFalse_whenStrategyNotEmpty_reverts()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        // Set up new feed
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = _singleFeed(alphaUsdPriceFeed);

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: _simpleStrategyAverage(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStrategyNotSupported.selector,
                asset_SingleFeed_Strategy_WithMA
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);
    }

    // when the price feed configuration is being updated, when the number of price feeds is 1, when the strategy configuration is being updated, when useMovingAverage is true, when the strategy configuration is empty: it reverts

    function test_whenUpdatingPriceFeeds_whenSingleFeed_whenUpdatingStrategy_whenUseMovingAverageTrue_whenStrategyEmpty_reverts()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        // Set up new feed
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = _singleFeed(alphaUsdPriceFeed);

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: _emptyStrategy(),
            useMovingAverage: true,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStrategyInsufficient.selector,
                asset_SingleFeed_Strategy_WithMA,
                abi.encode(_emptyStrategy()),
                uint256(1), // 1 feed being updated
                true // useMovingAverage
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);
    }

    // when the price feed configuration is being updated, when the number of price feeds is 1, when the strategy configuration is being updated, when useMovingAverage is true, when the strategy configuration is not empty: it replaces the price feed configuration, it replaces the strategy configuration, it emits an AssetPriceFeedsUpdated event, it emits an AssetStrategyUpdated event

    function test_whenUpdatingPriceFeeds_whenSingleFeed_whenUpdatingStrategy_whenUseMovingAverageTrue_whenStrategyNotEmpty()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        // Get old asset values
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);

        // Set up new feed and new strategy
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = _singleFeed(alphaUsdPriceFeed);

        IPRICEv2.Component memory newStrategy = _simpleStrategyFirstNonZero();

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: newStrategy,
            useMovingAverage: true,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectEmit(true, true, true, true);
        emit AssetPriceFeedsUpdated(asset_SingleFeed_Strategy_WithMA);
        vm.expectEmit(true, true, true, true);
        emit AssetPriceStrategyUpdated(asset_SingleFeed_Strategy_WithMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);

        // Verify feed was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);
        _assertFeedsUpdated(assetData, newFeeds);

        // Verify strategy was updated
        _assertStrategyUpdated(assetData, newStrategy, true);

        // Verify moving average is same
        _assertMovingAverageUnchanged(oldAssetData, assetData);

        // onemaUsdPriceFeed = 5e8 (8 decimals), normalized to PRICE decimals:
        // 5e8 * 1e10 = 5e18.
        // LAST should remain the pre-update latest stored observation.
        _assertLastPrice(asset_SingleFeed_Strategy_WithMA, 5e18, "LAST should remain unchanged");
    }

    // when the price feed configuration is being updated, when the number of price feeds is > 1, when there are duplicate price feeds: it reverts

    function test_whenUpdatingPriceFeeds_whenMultipleFeeds_whenDuplicateFeeds_reverts()
        public
        givenAsset_MultipleFeeds_Strategy_StoreMA
    {
        // Create duplicate feeds
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](2);
        newFeeds[0] = _singleFeed(twomaUsdPriceFeed);
        newFeeds[1] = _singleFeed(twomaUsdPriceFeed); // Duplicate

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
                IPRICEv2.PRICE_DuplicatePriceFeed.selector,
                asset_MultipleFeeds_Strategy_StoreMA,
                uint256(1) // index of duplicate
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_MultipleFeeds_Strategy_StoreMA, params);
    }

    // when the price feed configuration is being updated, when the number of price feeds is > 1, when the strategy configuration is not being updated, given useMovingAverage is false, given the existing strategy configuration is empty: it reverts

    function test_whenUpdatingPriceFeeds_whenMultipleFeeds_whenNotUpdatingStrategy_givenStrategyEmpty_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](2);
        newFeeds[0] = _singleFeed(twomaUsdPriceFeed);
        newFeeds[1] = _singleFeed(onemaUsdPriceFeed);

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
                IPRICEv2.PRICE_ParamsStrategyInsufficient.selector,
                address(asset_SingleFeed_NoStrategy_NoMA),
                abi.encode(_emptyStrategy()),
                uint256(2), // 2 feeds
                false // useMovingAverage
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the price feed configuration is being updated, when the number of price feeds is > 1, when the strategy configuration is not being updated, given the existing strategy configuration is not empty: it replaces the price feed configuration, it emits an AssetPriceFeedsUpdated event

    function test_whenUpdatingPriceFeeds_whenMultipleFeeds_whenNotUpdatingStrategy_givenStrategyNotEmpty()
        public
        givenAsset_MultipleFeeds_Strategy_StoreMA
    {
        // Get old asset values
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(
            asset_MultipleFeeds_Strategy_StoreMA
        );

        // Update feeds, keep strategy
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](2);
        newFeeds[0] = _singleFeed(onemaUsdPriceFeed);
        newFeeds[1] = _singleFeed(twomaEthPriceFeed);

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

        vm.expectEmit(true, true, true, true);
        emit AssetPriceFeedsUpdated(asset_MultipleFeeds_Strategy_StoreMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_MultipleFeeds_Strategy_StoreMA, params);

        // Verify feed was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_MultipleFeeds_Strategy_StoreMA);
        _assertFeedsUpdated(assetData, newFeeds);

        // Verify strategy was not updated
        _assertStrategyUnchanged(oldAssetData, assetData);

        // Verify moving average was not updated
        _assertMovingAverageUnchanged(oldAssetData, assetData);

        // twomaUsdPriceFeed = 20e8 (8 decimals), normalized to PRICE decimals:
        // 20e8 * 1e10 = 20e18.
        // LAST should remain the pre-update latest stored observation.
        _assertLastPrice(
            asset_MultipleFeeds_Strategy_StoreMA,
            20e18,
            "LAST should remain unchanged"
        );
    }

    // when the price feed configuration is being updated, when the number of price feeds is > 1, when the strategy configuration is being updated, when the strategy configuration is empty: it reverts

    function test_whenUpdatingPriceFeeds_whenMultipleFeeds_whenUpdatingStrategy_whenStrategyEmpty_reverts()
        public
        givenAsset_MultipleFeeds_Strategy_StoreMA
    {
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](2);
        newFeeds[0] = _singleFeed(onemaUsdPriceFeed);
        newFeeds[1] = _singleFeed(twomaEthPriceFeed);

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
                asset_MultipleFeeds_Strategy_StoreMA,
                abi.encode(_emptyStrategy()),
                uint256(2), // 1 feed
                false // useMovingAverage
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_MultipleFeeds_Strategy_StoreMA, params);
    }

    // when the price feed configuration is being updated, when the number of price feeds is > 1, when the strategy configuration is being updated, when the strategy configuration is not empty, when useMovingAverage is false: it replaces the price feed configuration, it replaces the strategy configuration, it emits an AssetPriceFeedsUpdated event, it emits an AssetStrategyUpdated event

    function test_whenUpdatingPriceFeeds_whenMultipleFeeds_whenUpdatingStrategy_whenStrategyNotEmpty_whenUseMovingAverageFalse()
        public
        givenAsset_MultipleFeeds_Strategy_StoreMA
    {
        // Get old asset values
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(
            asset_MultipleFeeds_Strategy_StoreMA
        );

        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](2);
        newFeeds[0] = _singleFeed(onemaUsdPriceFeed);
        newFeeds[1] = _singleFeed(twomaEthPriceFeed);

        IPRICEv2.Component memory newStrategy = _simpleStrategyFirstNonZero();

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

        vm.expectEmit(true, true, true, true);
        emit AssetPriceFeedsUpdated(asset_MultipleFeeds_Strategy_StoreMA);
        vm.expectEmit(true, true, true, true);
        emit AssetPriceStrategyUpdated(asset_MultipleFeeds_Strategy_StoreMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_MultipleFeeds_Strategy_StoreMA, params);

        // Verify feed was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_MultipleFeeds_Strategy_StoreMA);
        _assertFeedsUpdated(assetData, newFeeds);

        // Verify strategy was updated
        _assertStrategyUpdated(assetData, newStrategy, false);

        // Verify moving average was not updated
        _assertMovingAverageUnchanged(oldAssetData, assetData);

        // twomaUsdPriceFeed = 20e8 (8 decimals), normalized to PRICE decimals:
        // 20e8 * 1e10 = 20e18.
        // LAST should remain the pre-update latest stored observation.
        _assertLastPrice(
            asset_MultipleFeeds_Strategy_StoreMA,
            20e18,
            "LAST should remain unchanged"
        );
    }

    // when the price feed configuration is being updated, when the number of price feeds is > 1, when the strategy configuration is being updated, when the strategy configuration is not empty, when useMovingAverage is true: it replaces the price feed configuration, it replaces the strategy configuration, it emits an AssetPriceFeedsUpdated event, it emits an AssetStrategyUpdated event

    function test_whenUpdatingPriceFeeds_whenMultipleFeeds_whenUpdatingStrategy_whenStrategyNotEmpty_whenUseMovingAverageTrue()
        public
        givenAsset_MultipleFeeds_Strategy_StoreMA
    {
        // Get old asset values
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(
            asset_MultipleFeeds_Strategy_StoreMA
        );

        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](2);
        newFeeds[0] = _singleFeed(onemaUsdPriceFeed);
        newFeeds[1] = _singleFeed(twomaEthPriceFeed);

        IPRICEv2.Component memory newStrategy = _simpleStrategyFirstNonZero();

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: newStrategy,
            useMovingAverage: true,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectEmit(true, true, true, true);
        emit AssetPriceFeedsUpdated(asset_MultipleFeeds_Strategy_StoreMA);
        vm.expectEmit(true, true, true, true);
        emit AssetPriceStrategyUpdated(asset_MultipleFeeds_Strategy_StoreMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_MultipleFeeds_Strategy_StoreMA, params);

        // Verify feed was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_MultipleFeeds_Strategy_StoreMA);
        _assertFeedsUpdated(assetData, newFeeds);

        // Verify strategy was updated
        _assertStrategyUpdated(assetData, newStrategy, true);

        // Verify moving average was not updated
        _assertMovingAverageUnchanged(oldAssetData, assetData);

        // twomaUsdPriceFeed = 20e8 (8 decimals), normalized to PRICE decimals:
        // 20e8 * 1e10 = 20e18.
        // LAST should remain the pre-update latest stored observation.
        _assertLastPrice(
            asset_MultipleFeeds_Strategy_StoreMA,
            20e18,
            "LAST should remain unchanged"
        );
    }

    // when the price feed configuration is being updated, when the strategy configuration is not being updated: it ignores any strategy configuration parameters

    function test_whenUpdatingPriceFeeds_whenNotUpdatingStrategy()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);

        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = _singleFeed(onemaUsdPriceFeed);

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: true,
            updateStrategy: false, // Don't update strategy
            updateMovingAverage: false,
            feeds: newFeeds,
            strategy: _simpleStrategyAverage(), // This should be ignored
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);

        // Verify strategy was NOT updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);
        _assertStrategyUnchanged(oldAssetData, assetData);
        _assertMovingAverageUnchanged(oldAssetData, assetData);

        // LAST should remain the previous stored observation because updateMovingAverage=false.
        // In the fixture, observations are seeded via _makeRandomObservations with numObs=2:
        // - obs[1] is set from the current feed value before any random-walk adjustment.
        // - onemaUsdPriceFeed initial answer = 5e8 (8 decimals), normalized to 18 decimals:
        //   5e8 * 1e10 = 5e18.
        // - nextObsIndex is 0 after addAsset, so LAST reads obs[numObservations - 1] = obs[1].
        assertEq(oldAssetData.obs.length, 2, "fixture should seed two observations");
        assertEq(oldAssetData.obs[1], 5e18, "fixture latest observation should be 5e18");
        _assertLastPrice(
            asset_SingleFeed_Strategy_WithMA,
            5e18,
            "LAST should remain previous stored observation when MA is not updated"
        );
    }

    // when the price feed configuration is being updated, when the strategy configuration is not
    // being updated, given useMovingAverage is true, when the moving average is stale: it still
    // updates feeds and emits AssetPriceFeedsUpdated

    function test_whenUpdatingPriceFeeds_whenNotUpdatingStrategy_givenUseMovingAverageTrue_whenMovingAverageStale()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);

        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](1);
        newFeeds[0] = _singleFeed(alphaUsdPriceFeed);

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

        // Make the stored MA stale relative to observation frequency.
        vm.warp(block.timestamp + OBSERVATION_FREQUENCY);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_MovingAverageStale.selector,
                asset_SingleFeed_Strategy_WithMA,
                oldAssetData.lastObservationTime
            )
        );
        price.getPrice(asset_SingleFeed_Strategy_WithMA, IPRICEv2.Variant.CURRENT);

        vm.expectEmit(true, true, true, true);
        emit AssetPriceFeedsUpdated(asset_SingleFeed_Strategy_WithMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);

        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);
        _assertFeedsUpdated(assetData, newFeeds);
        _assertStrategyUnchanged(oldAssetData, assetData);
        _assertMovingAverageUnchanged(oldAssetData, assetData);
    }

    // when the asset strategy configuration is being updated, given the strategy submodule is not installed: it reverts

    function test_whenUpdatingStrategy_givenSubmoduleNotInstalled_reverts()
        public
        givenAsset_MultipleFeeds_Strategy_StoreMA
    {
        IPRICEv2.Component memory invalidStrategy = IPRICEv2.Component(
            toSubKeycode("PRICE.NONEXISTENT"), // Invalid submodule
            ISimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: invalidStrategy,
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_SubmoduleNotInstalled.selector,
                asset_MultipleFeeds_Strategy_StoreMA,
                abi.encode(toSubKeycode("PRICE.NONEXISTENT"))
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_MultipleFeeds_Strategy_StoreMA, params);
    }

    // when the asset strategy configuration is being updated, when the submodule call reverts: it reverts

    function test_whenUpdatingStrategy_whenSubmoduleCallReverts_reverts()
        public
        givenAsset_MultipleFeeds_Strategy
    {
        IPRICEv2.Component memory revertStrategy = IPRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            ISimplePriceFeedStrategy.getMedianPrice.selector,
            abi.encode("") // Missing params
        );

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: revertStrategy,
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_StrategyFailed.selector,
                asset_MultipleFeeds_Strategy,
                abi.encodeWithSelector(
                    ISimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector,
                    uint256(2),
                    uint256(3)
                )
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_MultipleFeeds_Strategy, params);
    }

    // when the asset strategy configuration is being updated, when useMovingAverage is true, when the moving average configuration is not being updated, given storeMovingAverage is true, when the updated strategy configuration is empty: it reverts

    function test_whenUpdatingStrategy_whenUseMovingAverageTrue_whenNotUpdatingMovingAverage_givenStoreMovingAverageTrue_whenStrategyEmpty_reverts()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: true,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStrategyInsufficient.selector,
                asset_SingleFeed_Strategy_WithMA,
                abi.encode(_emptyStrategy()),
                uint256(1), // 1 feed
                true // useMovingAverage
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);
    }

    // when the asset strategy configuration is being updated, when useMovingAverage is true, when the moving average configuration is not being updated, given storeMovingAverage is true, when the updated strategy configuration is not empty: it replaces the strategy configuration, it emits an AssetStrategyUpdated event

    function test_whenUpdatingStrategy_whenUseMovingAverageTrue_whenNotUpdatingMovingAverage_givenStoreMovingAverageTrue_whenStrategyNotEmpty()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);

        IPRICEv2.Component memory newStrategy = _simpleStrategyAverage();

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: newStrategy,
            useMovingAverage: true,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectEmit(true, true, true, true);
        emit AssetPriceStrategyUpdated(asset_SingleFeed_Strategy_WithMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);

        // Verify updates
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);
        _assertFeedsUnchanged(oldAssetData, assetData);
        _assertStrategyUpdated(assetData, newStrategy, true);
        _assertMovingAverageUnchanged(oldAssetData, assetData);
    }

    // when the asset strategy configuration is being updated, when useMovingAverage is true, when the moving average configuration is not being updated, given storeMovingAverage is false: it reverts

    function test_whenUpdatingStrategy_whenUseMovingAverageTrue_whenNotUpdatingMovingAverage_givenStoreMovingAverageFalse_reverts()
        public
        givenAsset_MultipleFeeds_Strategy
    {
        IPRICEv2.Component memory newStrategy = _simpleStrategyAverage();

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: newStrategy,
            useMovingAverage: true,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStoreMovingAverageRequired.selector,
                asset_MultipleFeeds_Strategy
            )
        );

        // Call function
        vm.prank(priceWriter);
        price.updateAsset(asset_MultipleFeeds_Strategy, params);
    }

    // when the asset strategy configuration is being updated, when useMovingAverage is true, when the moving average configuration is being updated, when storeMovingAverage is true, when the updated strategy configuration is empty: it reverts

    function test_whenUpdatingStrategy_whenUseMovingAverageTrue_whenUpdatingMovingAverage_whenStoreMovingAverageTrue_whenStrategyEmpty_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        uint256[] memory newObs = new uint256[](3);
        newObs[0] = 100e18;
        newObs[1] = 110e18;
        newObs[2] = 120e18;

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: true,
            storeMovingAverage: true,
            movingAverageDuration: uint32(3 * OBSERVATION_FREQUENCY),
            lastObservationTime: uint48(block.timestamp),
            observations: newObs
        });

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStrategyInsufficient.selector,
                asset_SingleFeed_NoStrategy_NoMA,
                abi.encode(_emptyStrategy()),
                uint256(1),
                true
            )
        );

        // Call function
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the asset strategy configuration is being updated, when useMovingAverage is true, when the moving average configuration is being updated, when storeMovingAverage is true, when the updated strategy configuration is not empty: it replaces the strategy configuration, it replaces the moving average configuration, it emits an AssetStrategyUpdated event, it emits an AssetMovingAverageUpdated event

    function test_whenUpdatingStrategy_whenUseMovingAverageTrue_whenUpdatingMovingAverage_whenStoreMovingAverageTrue_whenStrategyNotEmpty()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);

        IPRICEv2.Component memory newStrategy = _simpleStrategyAverage();

        uint256[] memory newObs = new uint256[](3);
        newObs[0] = 100e18;
        newObs[1] = 110e18;
        newObs[2] = 120e18;

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: newStrategy,
            useMovingAverage: true,
            storeMovingAverage: true,
            movingAverageDuration: uint32(3 * OBSERVATION_FREQUENCY),
            lastObservationTime: uint48(block.timestamp),
            observations: newObs
        });

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit AssetPriceStrategyUpdated(asset_SingleFeed_NoStrategy_NoMA);
        vm.expectEmit(true, true, true, true);
        emit AssetMovingAverageUpdated(asset_SingleFeed_NoStrategy_NoMA);

        // Call function
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);

        // Verify updates
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);
        _assertFeedsUnchanged(oldAssetData, assetData);
        _assertStrategyUpdated(assetData, newStrategy, true);
        _assertMovingAverageUpdated(
            assetData,
            true,
            uint32(3 * OBSERVATION_FREQUENCY),
            uint48(block.timestamp),
            newObs[0] + newObs[1] + newObs[2],
            3
        );

        _assertLastPrice(
            asset_SingleFeed_NoStrategy_NoMA,
            120e18,
            "LAST should be the most recent stored observation"
        );
    }

    // when the asset strategy configuration is being updated, when useMovingAverage is true, when the moving average configuration is being updated, when storeMovingAverage is false: it reverts

    function test_whenUpdatingStrategy_whenUseMovingAverageTrue_whenUpdatingMovingAverage_whenStoreMovingAverageFalse_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        uint256[] memory newObs = new uint256[](3);
        newObs[0] = 100e18;
        newObs[1] = 110e18;
        newObs[2] = 120e18;

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: true,
            storeMovingAverage: false,
            movingAverageDuration: uint32(3 * OBSERVATION_FREQUENCY),
            lastObservationTime: uint48(block.timestamp),
            observations: newObs
        });

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStoreMovingAverageRequired.selector,
                asset_SingleFeed_NoStrategy_NoMA
            )
        );

        // Call function
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the asset strategy configuration is being updated, when useMovingAverage is false, when the price feed configuration is not being updated, given there is one price feed, when the strategy is not empty: it reverts

    function test_whenUpdatingStrategy_whenUseMovingAverageFalse_whenNotUpdatingPriceFeeds_givenSingleFeed_whenStrategyNotEmpty_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: _simpleStrategyAverage(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStrategyNotSupported.selector,
                asset_SingleFeed_NoStrategy_NoMA
            )
        );

        // Call function
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the asset strategy configuration is being updated, when useMovingAverage is false, when the price feed configuration is not being updated, given there is one price feed, when the strategy is empty: it replaces the strategy configuration, it emits an AssetStrategyUpdated event

    function test_whenUpdatingStrategy_whenUseMovingAverageFalse_whenNotUpdatingPriceFeeds_givenSingleFeed_whenStrategyEmpty()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectEmit(true, true, true, true);
        emit AssetPriceStrategyUpdated(asset_SingleFeed_NoStrategy_NoMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);

        // Verify updates
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);
        _assertFeedsUnchanged(oldAssetData, assetData);
        _assertStrategyUpdated(assetData, _emptyStrategy(), false);
        _assertMovingAverageNotStored(assetData);
    }

    // when the asset strategy configuration is being updated, when useMovingAverage is false, when the price feed configuration is not being updated, given there is > 1 price feed, when the strategy is empty: it reverts

    function test_whenUpdatingStrategy_whenUseMovingAverageFalse_whenNotUpdatingPriceFeeds_givenMultipleFeeds_whenStrategyEmpty_reverts()
        public
        givenAsset_MultipleFeeds_Strategy_StoreMA
    {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStrategyInsufficient.selector,
                asset_MultipleFeeds_Strategy_StoreMA,
                abi.encode(_emptyStrategy()),
                uint256(2),
                false
            )
        );

        // Call function
        vm.prank(priceWriter);
        price.updateAsset(asset_MultipleFeeds_Strategy_StoreMA, params);
    }

    // when the asset strategy configuration is being updated, when useMovingAverage is false, when the price feed configuration is not being updated, given there is > 1 price feed, when the strategy is not empty: it replaces the strategy configuration, it emits an AssetStrategyUpdated event

    function test_whenUpdatingStrategy_whenUseMovingAverageFalse_whenNotUpdatingPriceFeeds_givenMultipleFeeds_whenStrategyNotEmpty()
        public
        givenAsset_MultipleFeeds_Strategy_StoreMA
    {
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(
            asset_MultipleFeeds_Strategy_StoreMA
        );

        IPRICEv2.Component memory newStrategy = _simpleStrategyAverage();

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: newStrategy,
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectEmit(true, true, true, true);
        emit AssetPriceStrategyUpdated(asset_MultipleFeeds_Strategy_StoreMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_MultipleFeeds_Strategy_StoreMA, params);

        // Verify updates
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_MultipleFeeds_Strategy_StoreMA);
        _assertFeedsUnchanged(oldAssetData, assetData);
        _assertStrategyUpdated(assetData, newStrategy, false);
        _assertMovingAverageUnchanged(oldAssetData, assetData);

        // Feed values at 18 decimals:
        // twomaUsd = 20e18
        // twomaEth * ethUsd = 20e18
        // Strategy is Average over two feeds:
        // (20e18 + 20e18) / 2 = 20e18.
        _assertLastPrice(
            asset_MultipleFeeds_Strategy_StoreMA,
            20e18,
            "LAST should remain the latest stored observation"
        );
    }

    // when the asset strategy configuration is being updated, when not updating price feeds configuration: feeds parameter is ignored

    function test_whenUpdatingStrategy_whenNotUpdatingFeeds()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);

        // Create new feeds that should be ignored
        IPRICEv2.Component[] memory newFeeds = new IPRICEv2.Component[](2);
        newFeeds[0] = _singleFeed(onemaUsdPriceFeed);
        newFeeds[1] = _singleFeed(twomaEthPriceFeed);

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
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

        vm.expectEmit(true, true, true, true);
        emit AssetPriceStrategyUpdated(asset_SingleFeed_NoStrategy_NoMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);

        // Verify updates
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);
        _assertFeedsUnchanged(oldAssetData, assetData);
    }

    // when the asset strategy configuration is being updated, when not updating moving average configuration: moving average parameters are ignored

    function test_whenUpdatingStrategy_whenNotUpdatingMovingAverage()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);

        uint256[] memory newObs = new uint256[](3);
        newObs[0] = 100e18;
        newObs[1] = 110e18;
        newObs[2] = 120e18;

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true,
            updateMovingAverage: false, // Don't update MA
            feeds: new IPRICEv2.Component[](0),
            strategy: _simpleStrategyAverage(),
            useMovingAverage: true,
            storeMovingAverage: false, // These should be ignored
            movingAverageDuration: uint32(3 * OBSERVATION_FREQUENCY), // These should be ignored
            lastObservationTime: uint48(block.timestamp), // These should be ignored
            observations: newObs // These should be ignored
        });

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);

        // Verify moving average was NOT updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_Strategy_WithMA);
        _assertMovingAverageUnchanged(oldAssetData, assetData);

        // Verify LAST remains available after the strategy update.
        (uint256 lastPrice, ) = price.getPrice(
            asset_SingleFeed_Strategy_WithMA,
            IPRICEv2.Variant.LAST
        );
        assertGt(lastPrice, 0, "LAST price should be non-zero");
    }

    // when the moving average configuration is being updated, when the last observation time is in the future: it reverts

    function test_whenUpdatingMovingAverage_whenObservationTimeInFuture_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        uint256[] memory newObs = new uint256[](2);
        newObs[0] = 100e18;
        newObs[1] = 110e18;

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: true,
            movingAverageDuration: uint32(2 * OBSERVATION_FREQUENCY),
            lastObservationTime: uint48(block.timestamp + 1), // Future timestamp
            observations: newObs
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsLastObservationTimeInvalid.selector,
                asset_SingleFeed_NoStrategy_NoMA,
                uint48(block.timestamp + 1),
                uint48(0), // earliestTimestamp
                uint48(block.timestamp) // latestTimestamp
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the moving average configuration is being updated, when storeMovingAverage is true, when the moving average duration is zero: it reverts

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageTrue_givenDurationZero_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        uint256[] memory newObs = new uint256[](2);
        newObs[0] = 100e18;
        newObs[1] = 110e18;

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: true,
            movingAverageDuration: uint32(0), // Zero duration
            lastObservationTime: uint48(block.timestamp),
            observations: newObs
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsMovingAverageDurationInvalid.selector,
                asset_SingleFeed_NoStrategy_NoMA,
                uint32(0),
                uint48(OBSERVATION_FREQUENCY)
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the moving average configuration is being updated, when storeMovingAverage is true, when the moving average duration is not a multiple of the observation frequency: it reverts

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageTrue_whenDurationNotMultipleOfFrequency_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        uint256[] memory newObs = new uint256[](2);
        newObs[0] = 100e18;
        newObs[1] = 110e18;

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: true,
            movingAverageDuration: uint32(OBSERVATION_FREQUENCY + 1), // Not a multiple
            lastObservationTime: uint48(block.timestamp),
            observations: newObs
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsMovingAverageDurationInvalid.selector,
                asset_SingleFeed_NoStrategy_NoMA,
                uint32(OBSERVATION_FREQUENCY + 1),
                uint48(OBSERVATION_FREQUENCY)
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the moving average configuration is being updated, when storeMovingAverage is true, when the number of observations is not equal to duration / frequency: it reverts

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageTrue_whenObservationCountMismatch_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        uint256[] memory newObs = new uint256[](2);
        newObs[0] = 100e18;
        newObs[1] = 110e18;

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: true,
            movingAverageDuration: uint32(3 * OBSERVATION_FREQUENCY), // 3 expected
            lastObservationTime: uint48(block.timestamp),
            observations: newObs // Only 2 observations
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsInvalidObservationCount.selector,
                asset_SingleFeed_NoStrategy_NoMA,
                uint256(2), // actual count
                uint256(3), // minimum (duration/frequency)
                uint256(3) // maximum (duration/frequency)
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the moving average configuration is being updated, when storeMovingAverage is true, when there is a zero value observation: it reverts

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageTrue_whenZeroObservation_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        uint256[] memory newObs = new uint256[](2);
        newObs[0] = 100e18;
        newObs[1] = 0; // Zero observation

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: true,
            movingAverageDuration: uint32(2 * OBSERVATION_FREQUENCY),
            lastObservationTime: uint48(block.timestamp),
            observations: newObs
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsObservationZero.selector,
                asset_SingleFeed_NoStrategy_NoMA,
                uint256(1) // index of zero observation
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the moving average configuration is being updated, when storeMovingAverage is true: it replaces the moving average configuration, it emits an AssetMovingAverageUpdated event

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageTrue()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);

        uint256[] memory newObs = new uint256[](3);
        newObs[0] = 100e18;
        newObs[1] = 110e18;
        newObs[2] = 120e18;

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: true,
            movingAverageDuration: uint32(3 * OBSERVATION_FREQUENCY),
            lastObservationTime: uint48(block.timestamp),
            observations: newObs
        });

        vm.expectEmit(true, true, true, true);
        emit AssetMovingAverageUpdated(asset_SingleFeed_NoStrategy_NoMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);

        // Verify updates
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);
        _assertFeedsUnchanged(oldAssetData, assetData);
        _assertStrategyUnchanged(oldAssetData, assetData);
        _assertMovingAverageUpdated(
            assetData,
            true,
            uint32(3 * OBSERVATION_FREQUENCY),
            uint48(block.timestamp),
            newObs[0] + newObs[1] + newObs[2],
            3
        );

        _assertLastPrice(
            asset_SingleFeed_NoStrategy_NoMA,
            120e18,
            "LAST should be the most recent stored observation"
        );
    }

    // when the moving average configuration is being updated, when store moving average is true, when use moving average is false, when the strategy configuration is being updated: LAST remains observation-based

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageTrue_lastRemainsObservationBased()
        public
    {
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

        // Initial add: MA stored and used
        onemaUsdPriceFeed.setLatestAnswer(int256(5e8));
        price.addAsset(
            address(onema),
            true,
            true,
            uint32(observations.length) * OBSERVATION_FREQUENCY,
            uint48(block.timestamp),
            observations,
            _simpleStrategyFirstNonZero(),
            feeds
        );

        // Update: Stop using MA
        onemaUsdPriceFeed.setLatestAnswer(int256(10e8)); // Feed returns 10e18

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: true, // Need to update strategy to stop using MA in aggregate
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false, // STOP using MA
            storeMovingAverage: true,
            movingAverageDuration: uint32(observations.length) * OBSERVATION_FREQUENCY,
            lastObservationTime: uint48(block.timestamp),
            observations: observations
        });

        price.updateAsset(address(onema), params);
        vm.stopPrank();

        (uint256 lastPrice, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(lastPrice, 5e18, "LAST should remain the most recent stored observation");
    }

    // when the moving average configuration is being updated, when the strategy configuration is not being updated, when params.useMovingAverage is false but existing strategy uses MA: LAST remains observation-based

    function test_whenUpdatingMovingAverage_whenNotUpdatingStrategy_whenParamsUseMovingAverageFalse_lastRemainsObservationBased()
        public
    {
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

        // Initial add with strategy using MA and observation price 5e18.
        onemaUsdPriceFeed.setLatestAnswer(int256(5e8));
        price.addAsset(
            address(onema),
            true, // storeMovingAverage
            true, // useMovingAverage
            uint32(observations.length) * OBSERVATION_FREQUENCY,
            uint48(block.timestamp),
            observations,
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                ISimplePriceFeedStrategy.getAveragePrice.selector,
                abi.encode(0)
            ),
            feeds
        );

        // Update moving average only. `useMovingAverage` in params should be ignored.
        onemaUsdPriceFeed.setLatestAnswer(int256(10e8)); // Feed returns 10e18.

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false, // Should be ignored because updateStrategy = false.
            storeMovingAverage: true,
            movingAverageDuration: uint32(observations.length) * OBSERVATION_FREQUENCY,
            lastObservationTime: uint48(block.timestamp),
            observations: observations
        });

        price.updateAsset(address(onema), params);
        vm.stopPrank();

        (uint256 lastPrice, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(lastPrice, 5e18, "LAST should remain the most recent stored observation");
    }

    // when the moving average configured is being updated, when store moving average is true: LAST remains observation-based

    function test_whenUpdatingMovingAverage_whenUseMovingAverageTrue_lastRemainsObservationBased()
        public
    {
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

        // Initial add with 5e18
        onemaUsdPriceFeed.setLatestAnswer(int256(5e8));
        price.addAsset(
            address(onema),
            true, // storeMovingAverage
            true, // useMovingAverage
            uint32(observations.length) * OBSERVATION_FREQUENCY,
            uint48(block.timestamp),
            observations,
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                ISimplePriceFeedStrategy.getAveragePrice.selector,
                abi.encode(0)
            ),
            feeds
        );

        // Update asset
        onemaUsdPriceFeed.setLatestAnswer(int256(10e8)); // Feed returns 10e18

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true, // triggers re-caching
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: true, // Should remain true or be updated to true
            storeMovingAverage: true,
            movingAverageDuration: uint32(observations.length) * OBSERVATION_FREQUENCY,
            lastObservationTime: uint48(block.timestamp),
            observations: observations
        });

        price.updateAsset(address(onema), params);
        vm.stopPrank();

        (uint256 lastPrice, ) = price.getPrice(address(onema), IPRICEv2.Variant.LAST);
        assertEq(lastPrice, 5e18, "LAST should remain the most recent stored observation");
    }

    // when the moving average configuration is being updated, when storeMovingAverage is false, when the strategy configuration is not being updated, given useMovingAverage is true: it reverts

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageFalse_whenNotUpdatingStrategy_givenUseMovingAverageTrue_reverts()
        public
        givenAsset_SingleFeed_Strategy_WithMA
    {
        uint256[] memory newObs = new uint256[](2);
        newObs[0] = 100e18;
        newObs[1] = 110e18;

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false, // but storeMovingAverage is false
            movingAverageDuration: uint32(2 * OBSERVATION_FREQUENCY),
            lastObservationTime: uint48(block.timestamp),
            observations: newObs
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsStoreMovingAverageRequired.selector,
                asset_SingleFeed_Strategy_WithMA
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_Strategy_WithMA, params);
    }

    // when the moving average configuration is being updated, when storeMovingAverage is false:
    // any non-empty observations array reverts (regardless of observation count)

    function testFuzz_whenUpdatingMovingAverage_whenStoreMovingAverageFalse_whenObservationsProvided_reverts(
        uint8 observationCount_
    ) public givenAsset_SingleFeed_NoStrategy_NoMA {
        uint256 observationCount = bound(observationCount_, 1, 32);
        uint256[] memory newObs = new uint256[](observationCount);
        for (uint256 i; i < observationCount; ) {
            newObs[i] = 100e18;
            unchecked {
                ++i;
            }
        }

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: newObs
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsInvalidObservationCount.selector,
                asset_SingleFeed_NoStrategy_NoMA,
                observationCount, // actual count
                uint256(0), // minimum
                uint256(0) // maximum
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the moving average configuration is being updated, when storeMovingAverage is false:
    // validation should still reject non-empty observations before observation-value checks

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageFalse_whenObservationIsZero_revertsWithInvalidObservationCount()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        uint256[] memory newObs = new uint256[](1);
        newObs[0] = 0; // Zero observation

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: newObs
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsInvalidObservationCount.selector,
                asset_SingleFeed_NoStrategy_NoMA,
                uint256(1), // actual count
                uint256(0), // minimum
                uint256(0) // maximum
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the moving average configuration is being updated, when storeMovingAverage is false:
    // validation should still reject non-empty observations before timestamp checks

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageFalse_whenLastObservationTimeIsZero_revertsWithInvalidObservationCount()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        uint256[] memory newObs = new uint256[](1);
        newObs[0] = 105e18;

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: newObs
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsInvalidObservationCount.selector,
                asset_SingleFeed_NoStrategy_NoMA,
                uint256(1), // actual count
                uint256(0), // minimum
                uint256(0) // maximum
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the moving average configuration is being updated, when storeMovingAverage is false, when the number of observations is 0: it replaces the moving average configuration, and LAST/MOVINGAVERAGE remain unavailable

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageFalse_whenZeroObservations()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0) // Empty observations
        });

        vm.expectEmit(true, true, true, true);
        emit AssetMovingAverageUpdated(asset_SingleFeed_NoStrategy_NoMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);

        // Verify moving average was updated
        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);
        _assertFeedsUnchanged(oldAssetData, assetData);
        _assertStrategyUnchanged(oldAssetData, assetData);

        // Verify MA and observations are fully cleared
        _assertMovingAverageNotStored(assetData);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_MovingAverageNotStored.selector,
                asset_SingleFeed_NoStrategy_NoMA
            )
        );
        price.getPrice(asset_SingleFeed_NoStrategy_NoMA, IPRICEv2.Variant.LAST);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_MovingAverageNotStored.selector,
                asset_SingleFeed_NoStrategy_NoMA
            )
        );
        price.getPrice(asset_SingleFeed_NoStrategy_NoMA, IPRICEv2.Variant.MOVINGAVERAGE);
    }

    // when the moving average configuration is being updated from stored to not-stored:
    // empty observations are required, duration/timestamp must be zero, and state is cleared

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageFalse_whenZeroObservations_clearsState()
        public
        givenAsset_SingleFeed_NoStrategy_StoreMA
    {
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(
            asset_SingleFeed_NoStrategy_StoreMA
        );
        assertEq(oldAssetData.storeMovingAverage, true, "precondition: MA should be stored");
        assertGt(oldAssetData.obs.length, 0, "precondition: observations should exist");
        assertGt(
            oldAssetData.numObservations,
            0,
            "precondition: observation count should be non-zero"
        );

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectEmit(true, true, true, true);
        emit AssetMovingAverageUpdated(asset_SingleFeed_NoStrategy_StoreMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_StoreMA, params);

        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_NoStrategy_StoreMA);
        _assertFeedsUnchanged(oldAssetData, assetData);
        _assertStrategyUnchanged(oldAssetData, assetData);
        _assertMovingAverageNotStored(assetData);
        assertEq(
            assetData.obs.length,
            0,
            "observations should be cleared when storeMovingAverage is disabled"
        );
        assertEq(
            assetData.numObservations,
            0,
            "observation count should be reset when storeMovingAverage is disabled"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_MovingAverageNotStored.selector,
                asset_SingleFeed_NoStrategy_StoreMA
            )
        );
        price.getPrice(asset_SingleFeed_NoStrategy_StoreMA, IPRICEv2.Variant.LAST);
    }

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageFalse_afterObservationStored_clearsMetadata()
        public
        givenAsset_SingleFeed_NoStrategy_StoreMA
    {
        vm.warp(block.timestamp + 1);

        vm.prank(priceWriter);
        price.storeObservation(asset_SingleFeed_NoStrategy_StoreMA);

        IPRICEv2.Asset memory oldAssetData = price.getAssetData(
            asset_SingleFeed_NoStrategy_StoreMA
        );
        assertEq(oldAssetData.storeMovingAverage, true, "precondition: MA should be stored");
        assertEq(
            oldAssetData.nextObsIndex,
            uint16(1),
            "precondition: nextObsIndex should advance after storing an observation"
        );
        assertGt(
            oldAssetData.movingAverageDuration,
            uint32(0),
            "precondition: movingAverageDuration should be non-zero"
        );
        assertGt(
            oldAssetData.numObservations,
            uint16(0),
            "precondition: numObservations should be non-zero"
        );
        assertGt(
            oldAssetData.lastObservationTime,
            uint48(0),
            "precondition: lastObservationTime should be non-zero"
        );

        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectEmit(true, true, true, true);
        emit AssetMovingAverageUpdated(asset_SingleFeed_NoStrategy_StoreMA);

        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_StoreMA, params);

        IPRICEv2.Asset memory assetData = price.getAssetData(asset_SingleFeed_NoStrategy_StoreMA);
        _assertFeedsUnchanged(oldAssetData, assetData);
        _assertStrategyUnchanged(oldAssetData, assetData);
        _assertMovingAverageNotStored(assetData);
    }

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageFalse_whenDurationIsNonZero_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_StoreMA
    {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(2 * OBSERVATION_FREQUENCY),
            lastObservationTime: uint48(0),
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsMovingAverageDurationInvalid.selector,
                asset_SingleFeed_NoStrategy_StoreMA,
                uint32(2 * OBSERVATION_FREQUENCY),
                uint48(0)
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_StoreMA, params);
    }

    function test_whenUpdatingMovingAverage_whenStoreMovingAverageFalse_whenLastObservationTimeIsNonZero_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_StoreMA
    {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(block.timestamp + 1),
            observations: new uint256[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsLastObservationTimeInvalid.selector,
                asset_SingleFeed_NoStrategy_StoreMA,
                uint48(block.timestamp + 1),
                uint48(0),
                uint48(0)
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_StoreMA, params);
    }

    // when the moving average configuration is being updated, when calling getCurrentPrice fails: it reverts

    function test_whenUpdatingMovingAverage_whenGetCurrentPriceFails_reverts()
        public
        givenAsset_SingleFeed_NoStrategy_NoMA
    {
        // Get the current asset's feed configuration to extract the feed address
        IPRICEv2.Asset memory oldAssetData = price.getAssetData(asset_SingleFeed_NoStrategy_NoMA);
        IPRICEv2.Component[] memory oldFeeds = abi.decode(
            oldAssetData.feeds,
            (IPRICEv2.Component[])
        );

        // Decode the feed params to get the feed address
        ChainlinkPriceFeeds.OneFeedParams memory feedParams = abi.decode(
            oldFeeds[0].params,
            (ChainlinkPriceFeeds.OneFeedParams)
        );
        AggregatorV2V3Interface feedAddress = feedParams.feed;

        // Set the price feed to return 0 (zero price causes failure)
        MockPriceFeed(address(feedAddress)).setLatestAnswer(0);

        // Call updateAsset with zero observations to trigger getCurrentPrice
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: true,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
            useMovingAverage: false,
            storeMovingAverage: false,
            movingAverageDuration: uint32(0),
            lastObservationTime: uint48(0),
            observations: new uint256[](0) // Zero observations triggers getCurrentPrice
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_PriceZero.selector,
                asset_SingleFeed_NoStrategy_NoMA
            )
        );
        vm.prank(priceWriter);
        price.updateAsset(asset_SingleFeed_NoStrategy_NoMA, params);
    }

    // when the moving average configuration is not being updated, when the strategy configuration is not being updated, when the price feed configuration is not being updated: it reverts

    function test_whenNoUpdatesRequested_reverts() public givenAsset_SingleFeed_NoStrategy_NoMA {
        IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
            updateFeeds: false,
            updateStrategy: false,
            updateMovingAverage: false,
            feeds: new IPRICEv2.Component[](0),
            strategy: _emptyStrategy(),
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
}
/// forge-lint: disable-end(unwrapped-modifier-logic,mixed-case-function,mixed-case-variable)
