// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FullMath} from "libraries/FullMath.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockVault, MockBalancerPool} from "test/mocks/BalancerMocks.sol";
import {MockUniV3Pair} from "test/mocks/MockUniV3Pair.sol";

import "modules/PRICE/OlympusPrice.v2.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {UniswapV3Price} from "modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {BalancerPoolTokenPrice, IVault, IWeightedPool} from "modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

// Tests for OlympusPrice v2
// TODO
// Asset Information
// [X] getAssets - returns all assets configured on the PRICE module
//      [X] zero assets
//      [X] one asset
//      [X] many assets
// [X] getAssetData - returns the price configuration data for a given asset
//
// Asset Prices
// [ ] getPrice(address, Variant) - returns the price of an asset in terms of the unit of account (USD)
//      [ ] current variant - dynamically calculates price from strategy and components
//           [ ] no strategy submodule (only one price source)
//              [ ] single price feed
//              [ ] multiple price feeds
//              [ ] single price feed with recursive calls
//              [ ] multiple price feeds with recursive calls
//              [ ] reverts if price is zero
//           [ ] with strategy submodule
//              [ ] two feeds (two separate feeds)
//              [ ] two feeds (one feed + MA)
//              [ ] three feeds (three separate feeds)
//              [ ] three feeds (two feeds + MA)
//              [ ] reverts if strategy fails
//              [ ] reverts if price is zero
//      [ ] last variant - loads price from cache
//           [ ] single observation stored
//           [ ] multiple observations stored
//           [ ] reverts if cached value is zero
//      [ ] moving average variant - returns the moving average from stored observations
//           [ ] single observation stored
//           [ ] multiple observations stored
//           [ ] reverts if moving average isn't stored
//           [ ] reverts if cached value is zero
//      [ ] reverts if invalid variant provided
//      [ ] reverts if asset not configured on PRICE module (not approved)
// [ ] getPrice(address) - convenience function for current price
//      [ ] returns cached value if updated this timestamp
//      [ ] calculates and returns current price if not updated this timestamp
// [ ] getPrice(address, uint48) - convenience function for price up to a certain age
//      [ ] returns cached value if updated within the provided age
//      [ ] calculates and returns current price if not updated within the provided age
// [ ] getPriceIn - returns the price of an asset in terms of another asset
//      [ ] current variant - dynamically calculates price from strategy and components
//      [ ] last variant - loads price from cache
//      [ ] moving average variant - returns the moving average from stored observations
//      [ ] reverts if invalid variant provided for either asset
//      [ ] reverts if either asset is not configured on PRICE module (not approved)
// [ ] getPriceIn(address) - returns cached value if updated this timestamp, otherwise calculates dynamically
//      [ ] returns cached value if both assets updated this timestamp
//      [ ] calculates and returns current price if either asset not updated this timestamp
// [ ] getPriceIn(address, uint48) - returns cached value if updated within the provided age, otherwise calculates dynamically
//      [ ] returns cached value if both assets updated within the provided age
//      [ ] calculates and returns current price if either asset not updated within the provided age
// [ ] storePrice - caches the price of an asset (stores a new observation if the asset uses a moving average)
//      [ ] reverts if asset not configured on PRICE module (not approved)
//      [ ] reverts if price is zero
//      [ ] reverts if caller is not permissioned
//      [ ] updates stored observations
//           [ ] single observation stored (no moving average)
//           [ ] multiple observations stored (moving average configured)
//      [ ] price stored event emitted
//
// Asset Management
// [ ] addAsset - add an asset to the PRICE module
//      [ ] reverts if asset already configured (approved)
//      [ ] reverts if asset address is not a contract
//      [ ] reverts if moving average is being used by strategy but not being stored on the contract
//      [ ] reverts if caller is not permissioned
//      [ ] all asset data is stored correctly
//      [ ] asset added to assets array
// [ ] removeAsset
//      [ ] reverts if asset not configured (not approved)
//      [ ] reverts if caller is not permissioned
//      [ ] all asset data is removed
//      [ ] asset removed from assets array
// [ ] updateAssetPriceFeeds
//      [ ] reverts if asset not configured (not approved)
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if no feeds are provided
//      [ ] reverts if any feed is not installed as a submodule
//      [ ] stores new feeds in asset data as abi-encoded bytes of the feed address array
// [ ] updateAssetPriceStrategy
//      [ ] reverts if asset not configured (not approved)
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if strategy is not installed as a submodule
//      [ ] reverts if uses moving average but moving average is not stored for asset
//      [ ] stores new strategy in asset data as abi-encoded bytes of the strategy component
// [ ] updateAssetMovingAverage
//      [ ] reverts if asset not configured (not approved)
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if last observation time is in the future
//      [ ] previous configuratio and observations cleared
//      [ ] if storing moving average
//           [ ] reverts if moving average duration and observation frequency are invalid
//           [ ] reverts if implied observations does not equal the amount of observations provided
//           [ ] stores moving average data, including observations, in asset data
//      [ ] if not storing moving average
//           [ ] reverts if more than one observation is provided
//           [ ] one observation provided
//              [ ] stores observation and last observation time in asset data
//              [ ] emits price stored event
//           [ ] no observations provided
//              [ ] stores last observation time in asset data

// In order to create the necessary configuration to test above scenarios, the following assets/feed combinations are created on the price module:
// - OHM: Three feed using the getMedianIfDeviation strategy
// - RSV: Two feed using the getAverageIfDeviation strategy
// - WETH: One feed with no strategy
// - BPT: One feed (has recursive calls) with no strategy
// - ONEMA: One feed + MA using the getPriceWithFallback strategy
// - TWOMA: Two feed + MA using the getAveragePrice strategy

contract PriceV2Test is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusPricev2;

    MockPriceFeed internal ohmUsdPriceFeed;
    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal reserveUsdPriceFeed;
    MockPriceFeed internal reserveEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;
    MockPriceFeed internal onemaUsdPriceFeed;
    MockPriceFeed internal twomaUsdPriceFeed;
    MockPriceFeed internal twomaEthPriceFeed;
    MockUniV3Pair internal ohmEthUniV3Pool;
    MockBalancerPool internal bpt;
    MockVault internal balVault;

    MockERC20 internal ohm;
    MockERC20 internal reserve;
    MockERC20 internal weth;
    MockERC20 internal onema;
    MockERC20 internal twoma;

    Kernel internal kernel;
    OlympusPricev2 internal price;
    ChainlinkPriceFeeds internal chainlinkPrice;
    BalancerPoolTokenPrice internal bptPrice;
    UniswapV3Price internal univ3Price;
    SimplePriceFeedStrategy internal strategy;

    address internal writer;

    int256 internal constant CHANGE_DECIMALS = 1e4;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        {
            // Deploy mocks for testing PRICEv2

            // Tokens
            ohm = new MockERC20("Olympus", "OHM", 9);
            reserve = new MockERC20("Reserve", "RSV", 18);
            weth = new MockERC20("Wrapped ETH", "WETH", 18);

            onema = new MockERC20("One + MA", "ONEMA", 18);
            twoma = new MockERC20("Two + MA", "TWOMA", 18);

            // Balancer
            bpt = new MockBalancerPool();
            balVault = new MockVault(address(bpt), address(ohm), address(reserve));

            // Chainlink
            ethUsdPriceFeed = new MockPriceFeed();
            ethUsdPriceFeed.setDecimals(8);
            ethUsdPriceFeed.setLatestAnswer(int256(2000e8));
            ethUsdPriceFeed.setTimestamp(block.timestamp);
            ethUsdPriceFeed.setRoundId(1);
            ethUsdPriceFeed.setAnsweredInRound(1);

            ohmUsdPriceFeed = new MockPriceFeed();
            ohmUsdPriceFeed.setDecimals(8);
            ohmUsdPriceFeed.setLatestAnswer(int256(10e8));
            ohmUsdPriceFeed.setTimestamp(block.timestamp);
            ohmUsdPriceFeed.setRoundId(1);
            ohmUsdPriceFeed.setAnsweredInRound(1);

            ohmEthPriceFeed = new MockPriceFeed();
            ohmEthPriceFeed.setDecimals(18);
            ohmEthPriceFeed.setLatestAnswer(int256(0.005e18));
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            ohmEthPriceFeed.setRoundId(1);
            ohmEthPriceFeed.setAnsweredInRound(1);

            reserveUsdPriceFeed = new MockPriceFeed();
            reserveUsdPriceFeed.setDecimals(8);
            reserveUsdPriceFeed.setLatestAnswer(int256(1e8));
            reserveUsdPriceFeed.setTimestamp(block.timestamp);
            reserveUsdPriceFeed.setRoundId(1);
            reserveUsdPriceFeed.setAnsweredInRound(1);

            reserveEthPriceFeed = new MockPriceFeed();
            reserveEthPriceFeed.setDecimals(18);
            reserveEthPriceFeed.setLatestAnswer(int256(1e18));
            reserveEthPriceFeed.setTimestamp(block.timestamp);
            reserveEthPriceFeed.setRoundId(1);
            reserveEthPriceFeed.setAnsweredInRound(1);

            onemaUsdPriceFeed = new MockPriceFeed();
            onemaUsdPriceFeed.setDecimals(8);
            onemaUsdPriceFeed.setLatestAnswer(int256(5e8));
            onemaUsdPriceFeed.setTimestamp(block.timestamp);
            onemaUsdPriceFeed.setRoundId(1);
            onemaUsdPriceFeed.setAnsweredInRound(1);

            twomaUsdPriceFeed = new MockPriceFeed();
            twomaUsdPriceFeed.setDecimals(8);
            twomaUsdPriceFeed.setLatestAnswer(int256(20e8));
            twomaUsdPriceFeed.setTimestamp(block.timestamp);
            twomaUsdPriceFeed.setRoundId(1);
            twomaUsdPriceFeed.setAnsweredInRound(1);

            twomaEthPriceFeed = new MockPriceFeed();
            twomaEthPriceFeed.setDecimals(18);
            twomaEthPriceFeed.setLatestAnswer(int256(0.01e18));
            twomaEthPriceFeed.setTimestamp(block.timestamp);
            twomaEthPriceFeed.setRoundId(1);
            twomaEthPriceFeed.setAnsweredInRound(1);

            // UniswapV3
            ohmEthUniV3Pool = new MockUniV3Pair();
            bool ohmFirst = address(ohm) < address(weth);
            ohmEthUniV3Pool.setToken0(ohmFirst ? address(ohm) : address(weth));
            ohmEthUniV3Pool.setToken1(ohmFirst ? address(weth) : address(ohm));
            // Create ticks for a 60 second observation period
            // Set to a price of 1 OHM = 0.005 ETH
            // Weighted tick needs to be -52986 (if OHM is token0) or 52986 (if OHM is token1)
            // Therefore, we need a tick difference of -3179149 (if OHM is token0) or 3179149 (if OHM is token1)
            int56[] memory tickCumulatives = new int56[](2);
            tickCumulatives[0] = ohmFirst
                ? int56(100000000) - int56(3179149)
                : int56(100000000) + int56(3179149);
            tickCumulatives[1] = int56(100000000);
            ohmEthUniV3Pool.setTickCumulatives(tickCumulatives);
        }

        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy price module
            price = new OlympusPricev2(kernel, 18, uint32(8 hours));

            // Deploy mock module writer
            writer = price.generateGodmodeFixture(type(OlympusPricev2).name);

            // Deploy price submodules
            chainlinkPrice = new ChainlinkPriceFeeds(price);
            bptPrice = new BalancerPoolTokenPrice(price, IVault(address(balVault)));
            strategy = new SimplePriceFeedStrategy(price);
            univ3Price = new UniswapV3Price(price);
        }

        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));

            // Install submodules on price module
            vm.startPrank(writer);
            price.installSubmodule(chainlinkPrice);
            price.installSubmodule(bptPrice);
            price.installSubmodule(univ3Price);
            price.installSubmodule(strategy);
            vm.stopPrank();
        }
    }

    // =========  HELPER FUNCTIONS ========= //
    // function initializePrice(uint8 nonce) internal {
    //     /// Assume that the reserveEth price feed is fixed at 0.001 ETH = 1 Reserve
    //     reserveEthPriceFeed.setLatestAnswer(int256(1e15));
    //     uint256 reserveEthPrice = uint256(reserveEthPriceFeed.latestAnswer());

    //     /// Set ohmEth price to 0.01 ETH = 1 OHM initially
    //     /// This makes the price 10 reserves per OHM, which is the same as our minimum value.
    //     /// Random moves up and down will be above or below this.
    //     int256 ohmEthPrice = int256(1e16);

    //     /// Set scaling value for calculations
    //     uint256 scale = 10 **
    //         (price.priceDecimals() + reserveEthPriceFeed.decimals() - ohmEthPriceFeed.decimals());

    //     /// Calculate the number of observations and initialize the observation array
    //     uint48 observationFrequency = price.observationFrequency();
    //     uint48 movingAverageDuration = price.movingAverageDuration();
    //     uint256 numObservations = movingAverageDuration / observationFrequency;
    //     uint256[] memory observations = new uint256[](numObservations);

    //     /// Perform a random walk to initialize the observations
    //     int256 change; // percentage with two decimals
    //     for (uint256 i; i < numObservations; ++i) {
    //         /// Calculate a random percentage change from -10% to + 10% using the nonce and observation number
    //         change = int256(uint256(keccak256(abi.encodePacked(nonce, i)))) % int256(1000);

    //         /// Calculate the new ohmEth price
    //         ohmEthPrice = (ohmEthPrice * (CHANGE_DECIMALS + change)) / CHANGE_DECIMALS;

    //         /// Update price feed
    //         ohmEthPriceFeed.setLatestAnswer(ohmEthPrice);

    //         /// Get the current price from the price module and store in the observations array
    //         observations[i] = uint256(ohmEthPrice).mulDiv(scale, reserveEthPrice);
    //     }

    //     /// Initialize the price module with the observations
    //     vm.prank(writer);
    //     price.initialize(observations, uint48(block.timestamp));
    // }

    // function makeRandomObservations(
    //     uint8 nonce,
    //     uint256 observations
    // ) internal returns (uint48 timeIncrease) {
    //     /// Perform a random walk and update the moving average with the supplied number of observations
    //     int256 change; // percentage with two decimals
    //     int256 ohmEthPrice = ohmEthPriceFeed.latestAnswer();
    //     uint48 observationFrequency = price.observationFrequency();
    //     for (uint256 i; i < observations; ++i) {
    //         /// Calculate a random percentage change from -10% to + 10% using the nonce and observation number
    //         change = int256(uint256(keccak256(abi.encodePacked(nonce, i)))) % int256(1000);

    //         /// Calculate the new ohmEth price
    //         ohmEthPrice = (ohmEthPrice * (CHANGE_DECIMALS + change)) / CHANGE_DECIMALS;

    //         /// Update price feed
    //         ohmEthPriceFeed.setLatestAnswer(ohmEthPrice);
    //         ohmEthPriceFeed.setTimestamp(block.timestamp);
    //         reserveEthPriceFeed.setTimestamp(block.timestamp);

    //         /// Call update moving average on the price module
    //         vm.prank(writer);
    //         price.updateMovingAverage();

    //         /// Shift time forward by the observation frequency
    //         timeIncrease += observationFrequency;
    //         vm.warp(block.timestamp + observationFrequency);
    //     }
    // }

    function _addBaseAssets() internal {
        // Configure price feed data and add asset to price module
        vm.startPrank(writer);

        // WETH - One feed with no strategy
        {
            ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
                ethUsdPriceFeed,
                uint48(24 hours)
            );

            PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
            feeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
                ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
                abi.encode(ethParams) // bytes memory params_
            );

            price.addAsset(
                address(weth), // address asset_
                false, // bool storeMovingAverage_ // don't track WETH MA
                false, // bool useMovingAverage_
                uint32(0), // uint32 movingAverageDuration_
                uint48(0), // uint48 lastObservationTime_
                new uint256[](0), // uint256[] memory observations_
                PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
                feeds //
            );
        }

        // OHM - Three feeds using the getMedianIfDeviation strategy
        {
            ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
                .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

            ChainlinkPriceFeeds.TwoFeedParams memory ohmFeedTwoParams = ChainlinkPriceFeeds
                .TwoFeedParams(
                    ohmEthPriceFeed,
                    uint48(24 hours),
                    ethUsdPriceFeed,
                    uint48(24 hours)
                );

            UniswapV3Price.UniswapV3Params memory ohmFeedThreeParams = UniswapV3Price
                .UniswapV3Params(ohmEthUniV3Pool, uint32(60 seconds));

            PRICEv2.Component[] memory feeds = new PRICEv2.Component[](3);
            feeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
                ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
                abi.encode(ohmFeedOneParams) // bytes memory params
            );
            feeds[1] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
                ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 selector
                abi.encode(ohmFeedTwoParams) // bytes memory params
            );
            feeds[2] = PRICEv2.Component(
                toSubKeycode("PRICE.UNIV3"), // SubKeycode target
                UniswapV3Price.getTokenTWAP.selector, // bytes4 selector
                abi.encode(ohmFeedThreeParams) // bytes memory params
            );

            price.addAsset(
                address(ohm), // address asset_
                true, // bool storeMovingAverage_ // track OHM MA
                false, // bool useMovingAverage_ // do not use MA in strategy
                uint32(30 days), // uint32 movingAverageDuration_
                uint48(block.timestamp), // uint48 lastObservationTime_
                new uint256[](90), // uint256[] memory observations_ // TODO
                PRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getMedianIfDeviation.selector,
                    abi.encode(uint256(300)) // 3% deviation
                ), // Component memory strategy_
                feeds // Component[] feeds_
            );
        }

        // RSV - Two feeds using the getAverageIfDeviation strategy
        {
            ChainlinkPriceFeeds.OneFeedParams memory reserveFeedOneParams = ChainlinkPriceFeeds
                .OneFeedParams(reserveUsdPriceFeed, uint48(24 hours));

            ChainlinkPriceFeeds.TwoFeedParams memory reserveFeedTwoParams = ChainlinkPriceFeeds
                .TwoFeedParams(
                    reserveEthPriceFeed,
                    uint48(24 hours),
                    ethUsdPriceFeed,
                    uint48(24 hours)
                );

            PRICEv2.Component[] memory feeds = new PRICEv2.Component[](2);
            feeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(reserveFeedOneParams)
            );
            feeds[1] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
                ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 functionSelector_
                abi.encode(reserveFeedTwoParams) // bytes memory params_
            );

            price.addAsset(
                address(reserve), // address asset_
                true, // bool storeMovingAverage_ // track reserve MA
                false, // bool useMovingAverage_ // do not use MA in strategy
                uint32(30 days), // uint32 movingAverageDuration_
                uint48(block.timestamp), // uint48 lastObservationTime_
                new uint256[](90), // uint256[] memory observations_ // TODO
                PRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getAverageIfDeviation.selector,
                    abi.encode(uint256(300)) // 3% deviation
                ), // Component memory strategy_
                feeds // Component[] feeds_
            );
        }

        // BPT - One feed (has recursive calls) with no strategy
        {
            BalancerPoolTokenPrice.BalancerWeightedPoolParams
                memory bptParams = BalancerPoolTokenPrice.BalancerWeightedPoolParams(
                    IWeightedPool(address(bpt))
                );

            PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
            feeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.BPT"), // SubKeycode subKeycode_
                BalancerPoolTokenPrice.getWeightedPoolTokenPrice.selector, // bytes4 functionSelector_
                abi.encode(bptParams) // bytes memory params_
            );

            price.addAsset(
                address(bpt), // address asset_
                false, // bool storeMovingAverage_ // no moving average for BPT
                false, // bool useMovingAverage_
                uint32(0), // uint32 movingAverageDuration_
                uint48(0), // uint48 lastObservationTime_
                new uint256[](0), // uint256[] memory observations_
                PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
                feeds // Component[] feeds_
            );
        }

        // ONEMA - One feed + MA using the getPriceWithFallback strategy
        {
            ChainlinkPriceFeeds.OneFeedParams memory onemaFeedParams = ChainlinkPriceFeeds
                .OneFeedParams(onemaUsdPriceFeed, uint48(24 hours));

            PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
            feeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
                ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
                abi.encode(onemaFeedParams) // bytes memory params_
            );

            price.addAsset(
                address(onema), // address asset_
                true, // bool storeMovingAverage_ // track ONEMA MA
                true, // bool useMovingAverage_ // use MA in strategy
                uint32(5 days), // uint32 movingAverageDuration_
                uint48(block.timestamp), // uint48 lastObservationTime_
                new uint256[](15), // uint256[] memory observations_ // TODO
                PRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getPriceWithFallback.selector,
                    abi.encode("") // no params required
                ), // Component memory strategy_
                feeds // Component[] feeds_
            );
        }

        // TWOMA - Two feed + MA using the getAveragePrice strategy
        {
            ChainlinkPriceFeeds.OneFeedParams memory twomaFeedOneParams = ChainlinkPriceFeeds
                .OneFeedParams(twomaUsdPriceFeed, uint48(24 hours));

            ChainlinkPriceFeeds.TwoFeedParams memory twomaFeedTwoParams = ChainlinkPriceFeeds
                .TwoFeedParams(
                    twomaEthPriceFeed,
                    uint48(24 hours),
                    ethUsdPriceFeed,
                    uint48(24 hours)
                );

            PRICEv2.Component[] memory feeds = new PRICEv2.Component[](2);
            feeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(twomaFeedOneParams)
            );
            feeds[1] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
                ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 functionSelector_
                abi.encode(twomaFeedTwoParams) // bytes memory params_
            );

            price.addAsset(
                address(twoma), // address asset_
                true, // bool storeMovingAverage_ // track TWOMA MA
                true, // bool useMovingAverage_ // use MA in strategy
                uint32(5 days), // uint32 movingAverageDuration_
                uint48(block.timestamp), // uint48 lastObservationTime_
                new uint256[](15), // uint256[] memory observations_ // TODO
                PRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getAveragePrice.selector,
                    abi.encode("") // no params required
                ), // Component memory strategy_
                feeds // Component[] feeds_
            );
        }

        vm.stopPrank();
    }

    // =========  TESTS ========= //

    // =========  getAssets  ========= //

    function test_getAssets_zero() public {
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

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        vm.prank(writer);
        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_ // don't track WETH MA
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );

        // Get assets from price module and check that they match
        address[] memory assets = price.getAssets();
        assertEq(assets[0], address(weth));
        assertEq(assets.length, 1);
    }

    function test_getAssets_many() public {
        // Add base assets to price module
        _addBaseAssets();

        // Get assets from price module and check that they match
        address[] memory assets = price.getAssets();
        assertEq(assets[0], address(weth));
        assertEq(assets[1], address(ohm));
        assertEq(assets[2], address(reserve));
        assertEq(assets[3], address(bpt));
        assertEq(assets[4], address(onema));
        assertEq(assets[5], address(twoma));
        assertEq(assets.length, 6);
    }

    // =========  getAssetData  ========= //

    function test_getAssetData() public {
        // Add base assets to price module
        _addBaseAssets();

        // Get asset data from price module and check that it matches
        PRICEv2.Asset memory assetData = price.getAssetData(address(ohm));
        assertEq(assetData.approved, true);
        assertEq(assetData.storeMovingAverage, true);
        assertEq(assetData.useMovingAverage, false);
        assertEq(assetData.movingAverageDuration, uint32(30 days));
        assertEq(assetData.lastObservationTime, uint48(block.timestamp));
        assertEq(assetData.obs.length, 90);
        PRICEv2.Component memory strategy = abi.decode(assetData.strategy, (PRICEv2.Component));
        assertEq(fromSubKeycode(strategy.target), bytes20("PRICE.SIMPLESTRATEGY"));
        assertEq(strategy.selector, SimplePriceFeedStrategy.getMedianIfDeviation.selector);
        assertEq(strategy.params, abi.encode(uint256(300)));
        PRICEv2.Component[] memory feeds = abi.decode(assetData.feeds, (PRICEv2.Component[]));
        assertEq(feeds.length, 3);
        assertEq(fromSubKeycode(feeds[0].target), bytes20("PRICE.CHAINLINK"));
        assertEq(feeds[0].selector, ChainlinkPriceFeeds.getOneFeedPrice.selector);
        assertEq(
            feeds[0].params,
            abi.encode(ChainlinkPriceFeeds.OneFeedParams(ohmUsdPriceFeed, uint48(24 hours)))
        );
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
        assertEq(fromSubKeycode(feeds[2].target), bytes20("PRICE.UNIV3"));
        assertEq(feeds[2].selector, UniswapV3Price.getTokenTWAP.selector);
        assertEq(
            feeds[2].params,
            abi.encode(UniswapV3Price.UniswapV3Params(ohmEthUniV3Pool, uint32(60 seconds)))
        );
    }

    // =========  getPrice  ========= //
}
