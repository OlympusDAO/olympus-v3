// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FullMath} from "libraries/FullMath.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockBalancerWeightedPool} from "test/mocks/MockBalancerPool.sol";
import {MockBalancerVault} from "test/mocks/MockBalancerVault.sol";
import {MockUniV3Pair} from "test/mocks/MockUniV3Pair.sol";

import "modules/PRICE/OlympusPrice.v2.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {UniswapV3Price} from "modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {BalancerPoolTokenPrice, IVault, IWeightedPool} from "modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

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
// [X] getPrice(address, uint48) - convenience function for price up to a certain age
//      [X] returns cached value if updated within the provided age
//      [X] calculates and returns current price if not updated within the provided age
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
// [X] getPriceIn(asset, base, uint48) - returns cached value if updated within the provided age, otherwise calculates dynamically
//      [X] returns cached value if both assets updated within the provided age
//      [X] calculates and returns current price if either asset not updated within the provided age
// [X] storePrice - caches the price of an asset (stores a new observation if the asset uses a moving average)
//      [X] reverts if asset not configured on PRICE module (not approved)
//      [X] reverts if price is zero
//      [X] reverts if caller is not permissioned
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
// [X] updateAssetPriceFeeds
//      [X] reverts if asset not configured (not approved)
//      [X] reverts if caller is not permissioned
//      [X] reverts if no feeds are provided
//      [X] reverts if any feed is not installed as a submodule
//      [X] reverts if a non-functioning configuration is provided
//      [X] stores new feeds in asset data as abi-encoded bytes of the feed address array
// [X] updateAssetPriceStrategy
//      [X] reverts if asset not configured (not approved)
//      [X] reverts if caller is not permissioned
//      [X] reverts if strategy is not installed as a submodule
//      [X] reverts if uses moving average but moving average is not stored for asset
//      [X] reverts if no strategy is provided, but feeds > 1
//      [X] reverts if no strategy is provided, but MA + feeds > 1
//      [X] reverts if a non-functioning configuration is provided
//      [X] stores empty strategy when feeds = 1
//      [X] stores new strategy in asset data as abi-encoded bytes of the strategy component
// [X] updateAssetMovingAverage
//      [X] reverts if asset not configured (not approved)
//      [X] reverts if caller is not permissioned
//      [X] reverts if last observation time is in the future
//      [X] reverts if a non-functioning configuration is provided
//      [X] previous configuration and observations cleared
//      [X] if storing moving average
//           [X] reverts if moving average duration and observation frequency are invalid
//           [X] reverts if implied observations does not equal the amount of observations provided
//           [X] reverts if a zero value is provided
//           [X] if storeMovingAverage was previously enabled, stores moving average data, including observations, in asset data
//           [X] if storeMovingAverage was previously disabled, stores moving average data, including observations, in asset data
//      [X] if not storing moving average
//           [X] reverts if more than one observation is provided
//           [X] reverts if movingAverageDuration is provided
//           [X] one observation provided
//              [X] stores observation and last observation time in asset data
//              [X] reverts if a zero value is provided
//           [X] no observations provided
//              [X] stores last observation time in asset data
//              [X] calculates current price and stores as cached value

// In order to create the necessary configuration to test above scenarios, the following assets/feed combinations are created on the price module:
// - OHM: Three feed using the getMedianPriceIfDeviation strategy
// - RSV: Two feed using the getAveragePriceIfDeviation strategy
// - WETH: One feed with no strategy
// - ALPHA: One feed with no strategy
// - BPT: One feed (has recursive calls) with no strategy
// - ONEMA: One feed + MA using the getFirstNonZeroPrice strategy
// - TWOMA: Two feed + MA using the getAveragePrice strategy

contract PriceV2Test is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusPricev2;

    MockPriceFeed internal ohmUsdPriceFeed;
    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal reserveUsdPriceFeed;
    MockPriceFeed internal reserveEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;
    MockPriceFeed internal alphaUsdPriceFeed;
    MockPriceFeed internal onemaUsdPriceFeed;
    MockPriceFeed internal twomaUsdPriceFeed;
    MockPriceFeed internal twomaEthPriceFeed;
    MockUniV3Pair internal ohmEthUniV3Pool;
    MockBalancerWeightedPool internal bpt;
    MockBalancerVault internal balVault;

    MockERC20 internal ohm;
    MockERC20 internal reserve;
    MockERC20 internal weth;
    MockERC20 internal alpha;
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
    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;

    // Re-declare events from PRICE.v2.sol
    event PriceStored(address indexed asset_, uint256 price_, uint48 timestamp_);
    event AssetAdded(address indexed asset_);
    event AssetRemoved(address indexed asset_);
    event AssetPriceFeedsUpdated(address indexed asset_);
    event AssetPriceStrategyUpdated(address indexed asset_);
    event AssetMovingAverageUpdated(address indexed asset_);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        {
            // Deploy mocks for testing PRICEv2

            // Tokens
            ohm = new MockERC20("Olympus", "OHM", 9);
            reserve = new MockERC20("Reserve", "RSV", 18);
            weth = new MockERC20("Wrapped ETH", "WETH", 18);
            alpha = new MockERC20("Alpha", "ALPHA", 18);
            onema = new MockERC20("One + MA", "ONEMA", 18);
            twoma = new MockERC20("Two + MA", "TWOMA", 18);

            // Balancer
            bpt = new MockBalancerWeightedPool();
            bpt.setDecimals(18);
            bpt.setTotalSupply(1e24);
            uint256[] memory weights = new uint256[](2);
            weights[0] = 5e17;
            weights[1] = 5e17;
            bpt.setNormalizedWeights(weights);
            // Target price: 10 reserves per OHM, balances are 1e7 Reserve and 1e6 OHM
            // At 1 million LP token supply, LP price should be 20e18
            bpt.setInvariant(uint256(3.16227766016838e24));
            balVault = new MockBalancerVault();
            address[] memory tokens = new address[](2);
            tokens[0] = address(ohm);
            tokens[1] = address(reserve);
            balVault.setTokens(tokens);
            uint256[] memory balances = new uint256[](2);
            balances[0] = 1e6 * 1e9;
            balances[1] = 1e7 * 1e18;
            balVault.setBalances(balances);

            // Chainlink
            ethUsdPriceFeed = new MockPriceFeed();
            ethUsdPriceFeed.setDecimals(8);
            ethUsdPriceFeed.setLatestAnswer(int256(2000e8));
            ethUsdPriceFeed.setTimestamp(block.timestamp);
            ethUsdPriceFeed.setRoundId(1);
            ethUsdPriceFeed.setAnsweredInRound(1);

            alphaUsdPriceFeed = new MockPriceFeed();
            alphaUsdPriceFeed.setDecimals(8);
            alphaUsdPriceFeed.setLatestAnswer(int256(50e8));
            alphaUsdPriceFeed.setTimestamp(block.timestamp);
            alphaUsdPriceFeed.setRoundId(1);
            alphaUsdPriceFeed.setAnsweredInRound(1);

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
            reserveEthPriceFeed.setLatestAnswer(int256(0.0005e18));
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
            // Weighted tick needs to be 154257 (if OHM is token0) or -154257 (if OHM is token1) (as if 5,000,000 ETH per OHM because of the decimal difference)
            // Therefore, we need a tick difference of 9255432 (if OHM is token0) or -9255432 (if OHM is token1)
            int56[] memory tickCumulatives = new int56[](2);
            tickCumulatives[0] = ohmFirst ? int56(100000000) : -int56(100000000);
            tickCumulatives[1] = ohmFirst ? int56(109255432) : -int56(109255432);
            ohmEthUniV3Pool.setTickCumulatives(tickCumulatives);
        }

        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy price module
            price = new OlympusPricev2(kernel, 18, OBSERVATION_FREQUENCY);

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
    function _makeRandomObservations(
        MockERC20 asset,
        PRICEv2.Component memory feed,
        uint256 nonce,
        uint256 numObs
    ) internal view returns (uint256[] memory) {
        // Get current price from feed
        (bool success, bytes memory data) = address(price.getSubmoduleForKeycode(feed.target))
            .staticcall(
                abi.encodeWithSelector(feed.selector, address(asset), price.decimals(), feed.params)
            );

        require(success, "Price feed call failed");
        int256 fetchedPrice = int256(abi.decode(data, (uint256)));

        /// Perform a random walk and create observations array
        uint256[] memory obs = new uint256[](numObs);
        int256 change; // percentage with two decimals
        for (uint256 i = numObs; i > 0; --i) {
            // Add current price to obs array
            obs[i - 1] = uint256(fetchedPrice);

            /// Calculate a random percentage change from -10% to + 10% using the nonce and observation number
            change = int256(uint256(keccak256(abi.encodePacked(nonce, i)))) % int256(1000);

            /// Calculate the new ohmEth price
            fetchedPrice = (fetchedPrice * (CHANGE_DECIMALS + change)) / CHANGE_DECIMALS;
        }

        return obs;
    }

    function _addOneMAAsset(uint256 nonce_, uint256 numObs_) internal {
        vm.startPrank(writer);

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
            uint32(numObs_) * OBSERVATION_FREQUENCY, // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            _makeRandomObservations(onema, feeds[0], nonce_, uint256(numObs_)), // uint256[] memory observations_
            PRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds // Component[] feeds_
        );
        vm.stopPrank();
    }

    function _addOneMAAssetWithObservations(uint256[] memory observations_) internal {
        vm.startPrank(writer);
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
            uint32(observations_.length) * OBSERVATION_FREQUENCY, // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            observations_, // uint256[] memory observations_
            PRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds // Component[] feeds_
        );

        vm.stopPrank();
    }

    function _addBaseAssets(uint256 nonce_) internal {
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

        // ALPHA - One feed with no strategy (simplifies testing certain cases)
        {
            ChainlinkPriceFeeds.OneFeedParams memory alphaParams = ChainlinkPriceFeeds
                .OneFeedParams(alphaUsdPriceFeed, uint48(24 hours));

            PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
            feeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
                ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
                abi.encode(alphaParams) // bytes memory params_
            );

            price.addAsset(
                address(alpha), // address asset_
                false, // bool storeMovingAverage_ // don't track WETH MA
                false, // bool useMovingAverage_
                uint32(0), // uint32 movingAverageDuration_
                uint48(0), // uint48 lastObservationTime_
                new uint256[](0), // uint256[] memory observations_
                PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
                feeds //
            );
        }

        // OHM - Three feeds using the getMedianPriceIfDeviation strategy
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
                .UniswapV3Params(ohmEthUniV3Pool, uint32(60 seconds), 0);

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
                _makeRandomObservations(ohm, feeds[0], nonce_, uint256(90)), // uint256[] memory observations_
                PRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getMedianPriceIfDeviation.selector,
                    abi.encode(uint256(300)) // 3% deviation
                ), // Component memory strategy_
                feeds // Component[] feeds_
            );
        }

        // RSV - Two feeds using the getAveragePriceIfDeviation strategy
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
                _makeRandomObservations(reserve, feeds[0], nonce_, uint256(90)), // uint256[] memory observations_
                PRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getAveragePriceIfDeviation.selector,
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

        // ONEMA - One feed + MA using the getFirstNonZeroPrice strategy
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
                _makeRandomObservations(onema, feeds[0], nonce_, uint256(15)), // uint256[] memory observations_
                PRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                    abi.encode(0) // no params required
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
                _makeRandomObservations(twoma, feeds[0], nonce_, uint256(15)), // uint256[] memory observations_
                PRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getAveragePrice.selector,
                    abi.encode(0) // no params required
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
        PRICEv2.Asset memory assetData = price.getAssetData(address(ohm));
        assertEq(assetData.approved, true);
        assertEq(assetData.storeMovingAverage, true);
        assertEq(assetData.useMovingAverage, false);
        assertEq(assetData.movingAverageDuration, uint32(30 days));
        assertEq(assetData.lastObservationTime, uint48(block.timestamp));
        assertEq(assetData.obs.length, 90);
        PRICEv2.Component memory assetStrategy = abi.decode(
            assetData.strategy,
            (PRICEv2.Component)
        );
        assertEq(fromSubKeycode(assetStrategy.target), bytes20("PRICE.SIMPLESTRATEGY"));
        assertEq(
            assetStrategy.selector,
            SimplePriceFeedStrategy.getMedianPriceIfDeviation.selector
        );
        assertEq(assetStrategy.params, abi.encode(uint256(300)));
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
            abi.encode(UniswapV3Price.UniswapV3Params(ohmEthUniV3Pool, uint32(60 seconds), 0))
        );
    }

    // =========  getPrice (with current variant) ========= //

    function test_getPrice_current_noStrat_oneFeed(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Get current price from price module and check that it matches
        (uint256 price_, uint48 timestamp) = price.getPrice(address(weth), PRICEv2.Variant.CURRENT);
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
        price.getPrice(address(weth), PRICEv2.Variant.CURRENT);
    }

    function test_getPrice_current_noStrat_oneFeedRecursive(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Get current price from price module and check that it matches
        (uint256 price_, uint48 timestamp) = price.getPrice(address(bpt), PRICEv2.Variant.CURRENT);
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
        price.getPrice(address(bpt), PRICEv2.Variant.CURRENT);
    }

    function test_getPrice_current_strat_twoFeed(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Price feeds are initialized with same value so there should be no deviation

        // Get current price from price module and check that it matches
        (uint256 price_, uint48 timestamp) = price.getPrice(
            address(reserve),
            PRICEv2.Variant.CURRENT
        );
        assertEq(price_, uint256(1e18));
        assertEq(timestamp, uint48(block.timestamp));

        // Set price feeds at a small deviation to each other
        reserveUsdPriceFeed.setLatestAnswer(int256(1.1e8));
        // Other price feed is still 1e18

        // Get current price again, expect average of two feeds because deviation is more than 3%
        (price_, timestamp) = price.getPrice(address(reserve), PRICEv2.Variant.CURRENT);
        assertEq(price_, uint256(1.05e18));
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testRevert_getPrice_current_strat_twoFeed_stratFailed(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Set price feeds to zero
        reserveUsdPriceFeed.setLatestAnswer(int256(0));
        reserveEthPriceFeed.setLatestAnswer(int256(0));
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(reserve));
        vm.expectRevert(err);
        price.getPrice(address(reserve), PRICEv2.Variant.CURRENT);
    }

    function test_getPrice_current_strat_oneFeedPlusMA(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // First feed is up so it should be returned on the first call
        (uint256 price_, uint48 timestamp) = price.getPrice(
            address(onema),
            PRICEv2.Variant.CURRENT
        );
        assertEq(price_, uint256(5e18));
        assertEq(timestamp, uint48(block.timestamp));

        // Get moving average
        (uint256 movingAverage, ) = price.getPrice(address(onema), PRICEv2.Variant.MOVINGAVERAGE);

        // Set price feed to zero
        onemaUsdPriceFeed.setLatestAnswer(int256(0));

        // Get current price again, expect moving average because feed is down
        (price_, timestamp) = price.getPrice(address(onema), PRICEv2.Variant.CURRENT);
        assertEq(price_, movingAverage);
    }

    // MA cannot be zero so we cannot test PriceZero error on assets that use MA in a fallback strategy

    function test_getPrice_current_strat_threeFeed(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Price feeds are initialized with same value so there should be no deviation

        // Get current price from price module and check that it matches
        (uint256 price_, uint48 timestamp) = price.getPrice(address(ohm), PRICEv2.Variant.CURRENT);
        assertEq(price_, uint256(10e18));

        // Set price feeds at a deviation to each other
        ohmUsdPriceFeed.setLatestAnswer(int256(11e8)); // $11
        ohmEthPriceFeed.setLatestAnswer(int256(0.0045e18)); // effectively $9

        // Get current price again, expect median of the three feeds because deviation is more than 3%
        // In this case, it should be the price of the UniV3 pool
        (price_, timestamp) = price.getPrice(address(ohm), PRICEv2.Variant.CURRENT);
        uint256 expectedPrice = univ3Price.getTokenTWAP(
            address(ohm),
            price.decimals(),
            abi.encode(UniswapV3Price.UniswapV3Params(ohmEthUniV3Pool, uint32(60), 0))
        );
        assertEq(price_, expectedPrice);
    }

    function testRevert_getPrice_current_strat_threeFeed_stratFailed(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Set price feeds to zero
        ohmUsdPriceFeed.setLatestAnswer(int256(0));
        ohmEthPriceFeed.setLatestAnswer(int256(0));
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(ohm));
        vm.expectRevert(err);
        price.getPrice(address(ohm), PRICEv2.Variant.CURRENT);
    }

    function test_getPrice_current_strat_twoFeedPlusMA(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // All feeds are up, so the first call should return the average of all feeds & moving average
        (uint256 price_, uint48 timestamp) = price.getPrice(
            address(twoma),
            PRICEv2.Variant.CURRENT
        );

        (uint256 movingAverage, ) = price.getPrice(address(twoma), PRICEv2.Variant.MOVINGAVERAGE);
        uint256 expectedPrice = (uint256(20e18) + uint256(20e18) + movingAverage) / 3;
        assertEq(price_, expectedPrice);
        assertEq(timestamp, uint48(block.timestamp));
    }

    function test_getPrice_current_strat_twoFeedPlusMA_priceZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Set price feeds to zero
        twomaUsdPriceFeed.setLatestAnswer(int256(0));
        twomaEthPriceFeed.setLatestAnswer(int256(0));
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price
        (uint256 returnedPrice, ) = price.getPrice(address(twoma), PRICEv2.Variant.CURRENT);

        // Grab the historical moving average
        (uint256 movingAverage, ) = price.getPrice(address(twoma), PRICEv2.Variant.MOVINGAVERAGE);

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
        price.getPrice(address(twoma), PRICEv2.Variant.CURRENT);
    }

    function testRevert_getPrice_current_addressZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Try to call getPrice with the last variant and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(0));
        vm.expectRevert(err);
        price.getPrice(address(0), PRICEv2.Variant.CURRENT);
    }

    // =========  getPrice (with last variant) ========= //

    function test_getPrice_last_singleObservation(uint256 nonce_) public {
        // Add base asset with only 1 observation stored
        _addOneMAAsset(nonce_, 1);

        // Get the stored observation
        PRICEv2.Asset memory asset = price.getAssetData(address(onema));
        uint256 storedObservation = asset.obs[0];
        uint48 start = uint48(block.timestamp);

        // Get last price, expect the only observation to be returned
        (uint256 price_, uint48 timestamp) = price.getPrice(address(onema), PRICEv2.Variant.LAST);

        assertEq(price_, storedObservation);
        assertEq(timestamp, start);

        // Warp forward in time and expect the same answer, even in the feed changes
        vm.warp(start + 1);
        onemaUsdPriceFeed.setLatestAnswer(int256(0));
        (price_, timestamp) = price.getPrice(address(onema), PRICEv2.Variant.LAST);
        assertEq(price_, storedObservation);
        assertEq(timestamp, start);
    }

    function test_getPrice_last_multipleObservations(uint256 nonce_) public {
        // Add base asset with multiple observations stored
        _addOneMAAsset(nonce_, 10);

        // Get the stored observation
        PRICEv2.Asset memory asset = price.getAssetData(address(onema));
        uint256 storedObservation = asset.obs[9];
        uint48 start = uint48(block.timestamp);

        // Get last price, expect the last observation to be returned
        (uint256 price_, uint48 timestamp) = price.getPrice(address(onema), PRICEv2.Variant.LAST);

        assertEq(price_, storedObservation);
        assertEq(timestamp, start);

        // Warp forward in time and expect the same answer, even in the feed changes
        vm.warp(start + 1);
        onemaUsdPriceFeed.setLatestAnswer(int256(0));
        (price_, timestamp) = price.getPrice(address(onema), PRICEv2.Variant.LAST);
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
        (uint256 price_, ) = price.getPrice(address(onema), PRICEv2.Variant.CURRENT);
        assertEq(price_, 5e18);

        // Get the last price, which should be 2e18 from the stored observations
        (price_, ) = price.getPrice(address(onema), PRICEv2.Variant.LAST);
        assertEq(price_, 2e18);

        // Store the price, to increment nextObsIndex to 1
        vm.prank(writer);
        price.storePrice(address(onema));

        // Get last price, expect the most recent observation to be returned
        (price_, ) = price.getPrice(address(onema), PRICEv2.Variant.LAST);

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
        price.getPrice(address(twoma), PRICEv2.Variant.LAST);
    }

    function testRevert_getPrice_last_addressZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Try to call getPrice with the last variant and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(0));
        vm.expectRevert(err);
        price.getPrice(address(0), PRICEv2.Variant.LAST);
    }

    // =========  getPrice (with moving average variant) ========= //

    function test_getPrice_movingAverage_singleObservation(uint256 nonce_) public {
        // Add base asset with only 1 observation stored
        _addOneMAAsset(nonce_, 1);

        // Get the stored observation
        PRICEv2.Asset memory asset = price.getAssetData(address(onema));
        uint256 storedObservation = asset.obs[0];

        // Get moving average price, expect the only observation to be returned
        (uint256 price_, ) = price.getPrice(address(onema), PRICEv2.Variant.MOVINGAVERAGE);

        assertEq(price_, storedObservation);
    }

    function test_getPrice_movingAverage_multipleObservations(uint256 nonce_) public {
        // Add base asset with multiple observations stored
        _addOneMAAsset(nonce_, 10);

        // Get the stored observation
        PRICEv2.Asset memory asset = price.getAssetData(address(onema));
        uint256 cumulativeObservations;
        for (uint256 i; i < asset.numObservations; i++) {
            cumulativeObservations += asset.obs[i];
        }
        uint256 movingAverage = cumulativeObservations / asset.numObservations;

        // Get moving average price, expect the only observation to be returned
        (uint256 price_, ) = price.getPrice(address(onema), PRICEv2.Variant.MOVINGAVERAGE);

        assertEq(price_, movingAverage);
    }

    function testRevert_getPrice_movingAverage_movingAverageNotStored(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Try to call getPrice with the moving average variant and expect revert
        bytes memory err = abi.encodeWithSignature(
            "PRICE_MovingAverageNotStored(address)",
            address(weth)
        );
        vm.expectRevert(err);
        price.getPrice(address(weth), PRICEv2.Variant.MOVINGAVERAGE);
    }

    function testRevert_getPrice_movingAverage_unconfiguredAsset() public {
        // No base assets

        // Try to call getPrice with the moving average variant and expect revert
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(twoma)
        );
        vm.expectRevert(err);
        price.getPrice(address(twoma), PRICEv2.Variant.MOVINGAVERAGE);
    }

    function testRevert_getPrice_movingAverage_addressZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Try to call getPrice with the last variant and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(0));
        vm.expectRevert(err);
        price.getPrice(address(0), PRICEv2.Variant.MOVINGAVERAGE);
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

    // =========  getPrice (with max age) ========= //

    function test_getPrice_maxAge(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Cache the current price of weth
        vm.prank(writer);
        price.storePrice(address(weth));
        uint48 start = uint48(block.timestamp);

        // Get current price from price module and check that it matches
        // Use a 60 second max age
        uint256 price_ = price.getPrice(address(weth), uint48(60));
        assertEq(price_, uint256(2000e18));

        // Warp time forward slightly (not passed max age) and expect same price
        vm.warp(uint256(start) + 60);
        ethUsdPriceFeed.setLatestAnswer(int256(2001e8));

        price_ = price.getPrice(address(weth), uint48(60));
        assertEq(price_, uint256(2000e18));

        // Warp time forward slightly (passed max age) and expect new price
        vm.warp(uint256(start) + 61);
        price_ = price.getPrice(address(weth), uint48(60));
        assertEq(price_, uint256(2001e18));
    }

    function testRevert_getPrice_maxAge_unconfiguredAsset() public {
        // No base assets

        // Try to call getPrice with a max age and expect revert
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(twoma)
        );
        vm.expectRevert(err);
        price.getPrice(address(twoma), 1000);
    }

    // =========  getPrice (convenience) ========= //

    function test_getPrice_conv(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Cache the current price of weth
        vm.prank(writer);
        price.storePrice(address(weth));
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
            PRICEv2.Variant.CURRENT
        );

        assertEq(price_, uint256(200e18));
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testRevert_getPriceIn_current_priceZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Set weth price feed to zero
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(weth));
        vm.expectRevert(err);
        price.getPriceIn(address(weth), address(ohm), PRICEv2.Variant.CURRENT);

        // Set weth price back to normal
        ethUsdPriceFeed.setLatestAnswer(int256(2000e8));

        // Set alpha price to zero
        alphaUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(alpha));
        vm.expectRevert(err);
        price.getPriceIn(address(weth), address(alpha), PRICEv2.Variant.CURRENT);
    }

    function testRevert_getPriceIn_current_unconfiguredAsset() public {
        // No base assets

        // Try to call getPriceIn with the current variant and expect revert on the first asset
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(onema)
        );
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), PRICEv2.Variant.CURRENT);

        // Add onema so it is approved
        _addOneMAAsset(1, 10);

        // Try to call getPriceIn with the current variant and expect revert on the second asset
        err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(twoma));
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), PRICEv2.Variant.CURRENT);
    }

    function test_getPriceIn_last(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Cache the current price of weth
        vm.prank(writer);
        price.storePrice(address(weth));
        // OHM is already cached via storing the moving average on initialization
        uint48 start = uint48(block.timestamp);

        // Get last price of weth in ohm
        (uint256 price_, uint48 timestamp) = price.getPriceIn(
            address(weth),
            address(ohm),
            PRICEv2.Variant.LAST
        );

        assertEq(price_, uint256(200e18));
        assertEq(timestamp, uint48(start));

        // Warp forward in time and expect to get the same value
        vm.warp(uint256(start) + 1);
        ethUsdPriceFeed.setLatestAnswer(int256(2001e8));
        ohmEthPriceFeed.setLatestAnswer(int256(0.004e18));
        ohmUsdPriceFeed.setLatestAnswer(int256(8e8));

        (price_, timestamp) = price.getPriceIn(address(weth), address(ohm), PRICEv2.Variant.LAST);

        assertEq(price_, uint256(200e18));
        assertEq(timestamp, uint48(start));
    }

    function testRevert_getPriceIn_last_unconfiguredAsset() public {
        // No base assets

        // Try to call getPriceIn with the current variant and expect revert on the first asset
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(onema)
        );
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), PRICEv2.Variant.LAST);

        // Add onema so it is approved
        _addOneMAAsset(1, 10);

        // Try to call getPriceIn with the current variant and expect revert on the second asset
        err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(twoma));
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), PRICEv2.Variant.LAST);
    }

    function test_getPriceIn_movingAverage(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Manually calculate moving average of ohm in reserve (both are configured for Moving Averages)
        PRICEv2.Asset memory ohmData = price.getAssetData(address(ohm));
        PRICEv2.Asset memory reserveData = price.getAssetData(address(reserve));
        uint48 start = uint48(block.timestamp);

        uint256 ohmMovingAverage = ohmData.cumulativeObs / ohmData.numObservations;
        uint256 reserveMovingAverage = reserveData.cumulativeObs / reserveData.numObservations;
        uint256 expectedMovingAverage = (ohmMovingAverage * 10 ** price.decimals()) /
            reserveMovingAverage;

        // Get moving average price of ohm in reserve
        (uint256 movingAverage, uint48 timestamp) = price.getPriceIn(
            address(ohm),
            address(reserve),
            PRICEv2.Variant.MOVINGAVERAGE
        );

        assertEq(movingAverage, expectedMovingAverage);
        assertEq(timestamp, start);

        // Warp forward in time and expect to get the same value since no new prices are stored
        vm.warp(uint256(start) + 1 hours);
        (movingAverage, timestamp) = price.getPriceIn(
            address(ohm),
            address(reserve),
            PRICEv2.Variant.MOVINGAVERAGE
        );

        assertEq(movingAverage, expectedMovingAverage);
        assertEq(timestamp, start);
    }

    function testRevert_getPriceIn_movingAverage_notStored(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Try to call getPriceIn with the moving average variant and expect revert on the first asset
        bytes memory err = abi.encodeWithSignature(
            "PRICE_MovingAverageNotStored(address)",
            address(weth)
        );
        vm.expectRevert(err);
        price.getPriceIn(address(weth), address(ohm), PRICEv2.Variant.MOVINGAVERAGE);

        // Try with positions reversed
        vm.expectRevert(err);
        price.getPriceIn(address(ohm), address(weth), PRICEv2.Variant.MOVINGAVERAGE);
    }

    function testRevert_getPriceIn_movingAverage_unconfiguredAsset() public {
        // No base assets

        // Try to call getPriceIn with the current variant and expect revert on the first asset
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(onema)
        );
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), PRICEv2.Variant.MOVINGAVERAGE);

        // Add onema so it is approved
        _addOneMAAsset(1, 10);

        // Try to call getPriceIn with the current variant and expect revert on the second asset
        err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(twoma));
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), PRICEv2.Variant.MOVINGAVERAGE);
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

    // Cases to check for getPriceIn (asset, base):
    // 1. Both assets have a cached price at current timestamp
    // 2. Both assets don't have a cached price at current timestamp
    // 3. Asset has a cached price, base doesn't
    // 4. Base has a cached price, asset doesn't

    function test_getPriceIn_conv_case1(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // WETH and ALPHA have values cached on creation

        // Get price of weth in alpha (current price and last are the same)
        uint256 price_ = price.getPriceIn(address(weth), address(alpha));

        assertEq(price_, uint256(40e18));

        // Change price of both assets
        ethUsdPriceFeed.setLatestAnswer(int256(1600e8));
        alphaUsdPriceFeed.setLatestAnswer(int256(20e8));

        // Get price of weth in alpha, expect stored value since it has the current timestamp
        price_ = price.getPriceIn(address(weth), address(alpha));
        assertEq(price_, uint256(40e18));
    }

    function test_getPriceIn_conv_case2(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // WETH and ALPHA have values cached on creation

        // Warp forward in time so that the stored prices are stale (but non-zero)
        vm.warp(block.timestamp + 1);

        // Change price of both assets
        ethUsdPriceFeed.setLatestAnswer(int256(1600e8));
        alphaUsdPriceFeed.setLatestAnswer(int256(20e8));

        // Get price of weth in ohm, expect new value since stored values are stale
        uint256 price_ = price.getPriceIn(address(weth), address(alpha));
        assertEq(price_, uint256(80e18));
    }

    function test_getPriceIn_conv_case3(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Warp forward in time to ignore initialized cache prices
        vm.warp(uint256(block.timestamp) + 1);

        // Store the price of one asset
        vm.startPrank(writer);
        price.storePrice(address(weth));
        vm.stopPrank();

        // Set a different value for both assets
        ethUsdPriceFeed.setLatestAnswer(int256(1600e8));
        alphaUsdPriceFeed.setLatestAnswer(int256(20e8));

        // Get current price of
        uint256 price_ = price.getPriceIn(address(weth), address(alpha));

        // Will be the stored weth value divided by the new alpha value
        assertEq(price_, uint256(100e18));
    }

    function test_getPriceIn_conv_case4(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Warp forward in time to ignore initialized cache prices
        vm.warp(uint256(block.timestamp) + 1);

        // Store the price of one asset
        vm.startPrank(writer);
        price.storePrice(address(alpha));
        vm.stopPrank();

        // Set a different value for both assets
        ethUsdPriceFeed.setLatestAnswer(int256(1600e8));
        alphaUsdPriceFeed.setLatestAnswer(int256(20e8));

        // Get current price of
        uint256 price_ = price.getPriceIn(address(weth), address(alpha));

        // Will be the new weth value divided by the stored alpha value
        assertEq(price_, uint256(32e18));
    }

    // ==========  getPriceIn (asset, base, maxAge) ========== //

    function testRevert_getPriceIn_maxAge_unconfiguredAssets() public {
        // No base assets

        // Try to call getPriceIn and expect revert on the first asset
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(onema)
        );
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), uint48(60));

        // Add onema so it is approved
        _addOneMAAsset(1, 10);

        // Try to call getPriceIn and expect revert on the second asset
        err = abi.encodeWithSignature("PRICE_AssetNotApproved(address)", address(twoma));
        vm.expectRevert(err);
        price.getPriceIn(address(onema), address(twoma), uint48(60));

        // Reverse positions
        vm.expectRevert(err);
        price.getPriceIn(address(twoma), address(onema), uint48(60));
    }

    function testRevert_getPriceIn_maxAge_priceZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Warp forward in time to ignore initialized cache prices
        vm.warp(uint256(block.timestamp) + 61);

        // Change WETH price to zero
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // WETH is not stored at the beginning, so it should revert
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(weth));
        vm.expectRevert(err);
        price.getPriceIn(address(weth), address(alpha), uint48(60));

        // Try with positions reversed
        vm.expectRevert(err);
        price.getPriceIn(address(alpha), address(weth), uint48(60));
    }

    // Cases to check for getPriceIn (asset, base, maxAge):
    // 1. Both assets have a cached price within maxAge
    // 2. Both assets don't have a cached price within maxAge
    // 3. Asset has a cached price, base doesn't
    // 4. Base has a cached price, asset doesn't

    function test_getPriceIn_maxAge_case1(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // WETH and ALPHA both have a cached value on creation
        uint48 start = uint48(block.timestamp);

        // Get current price of weth in alpha, expect stored value / current value since they are the same
        uint256 price_ = price.getPriceIn(address(weth), address(alpha), uint48(60));
        assertEq(price_, uint256(40e18));

        // Move forward in time so that the stored value is still valid for both assets
        vm.warp(uint256(start + 60));

        // Change price of both assets
        ethUsdPriceFeed.setLatestAnswer(int256(1600e8));
        alphaUsdPriceFeed.setLatestAnswer(int256(20e8));

        // Get price of weth in alpha, expect stored value since is within the maxAge
        price_ = price.getPriceIn(address(weth), address(alpha), uint48(60));
        assertEq(price_, uint256(40e18));
    }

    function test_getPriceIn_maxAge_case2(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // WETH and ALPHA both have a cached value on creation

        // Change price of both assets
        ethUsdPriceFeed.setLatestAnswer(int256(1600e8));
        alphaUsdPriceFeed.setLatestAnswer(int256(20e8));

        // Get current price of weth in alpha, expect stored value / current value since they are the same
        uint256 price_ = price.getPriceIn(address(weth), address(alpha), uint48(60));
        assertEq(price_, uint256(40e18));

        // Move forward in time so that the stored values are stale
        vm.warp(uint256(block.timestamp + 61));

        // Get price of weth in alpha, expect current value since stored values are stale
        price_ = price.getPriceIn(address(weth), address(alpha), uint48(60));
        assertEq(price_, uint256(80e18));
    }

    function test_getPriceIn_maxAge_case3(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Warp forward in time to ignore initialized cache prices
        uint48 start = uint48(block.timestamp);
        vm.warp(uint256(start) + 120);

        // Store the price of one asset
        vm.startPrank(writer);
        price.storePrice(address(weth));
        vm.stopPrank();

        // Set a different value for both assets
        ethUsdPriceFeed.setLatestAnswer(int256(1600e8));
        alphaUsdPriceFeed.setLatestAnswer(int256(20e8));

        // Get price of weth in alpha
        uint256 price_ = price.getPriceIn(address(weth), address(alpha), uint48(60));

        // Will be the stored weth value divided by the new alpha value
        assertEq(price_, uint256(100e18));

        // Warp forward in time so that the stored value for weth is still within maxAge
        vm.warp(uint256(start) + 180);

        // Get price of weth in alpha, expect same value since it is within maxAge
        price_ = price.getPriceIn(address(weth), address(alpha), uint48(60));
        assertEq(price_, uint256(100e18));

        // Warp forward in time so that the stored value for weth is stale
        vm.warp(uint256(start) + 181);

        // Get price of weth in alpha, expect new value since it is outside of maxAge
        price_ = price.getPriceIn(address(weth), address(alpha), uint48(60));
        assertEq(price_, uint256(80e18));
    }

    function test_getPriceIn_maxAge_case4(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Warp forward in time to ignore initialized cache prices
        uint48 start = uint48(block.timestamp);
        vm.warp(uint256(start) + 120);

        // Store the price of base asset
        vm.startPrank(writer);
        price.storePrice(address(alpha));
        vm.stopPrank();

        // Set a different value for both assets
        ethUsdPriceFeed.setLatestAnswer(int256(1600e8));
        alphaUsdPriceFeed.setLatestAnswer(int256(20e8));

        // Get price of weth in alpha
        uint256 price_ = price.getPriceIn(address(weth), address(alpha), uint48(60));

        // Will be the new weth value divided by the stored alpha value
        assertEq(price_, uint256(32e18));

        // Warp forward in time so that the stored value for alpha is still within maxAge
        vm.warp(uint256(start) + 180);

        // Get price of weth in alpha, expect same value since it is within maxAge
        price_ = price.getPriceIn(address(weth), address(alpha), uint48(60));
        assertEq(price_, uint256(32e18));

        // Warp forward in time so that the stored value for alpha is stale
        vm.warp(uint256(start) + 181);

        // Get price of weth in alpha, expect new value since it is outside of maxAge
        price_ = price.getPriceIn(address(weth), address(alpha), uint48(60));
        assertEq(price_, uint256(80e18));
    }

    // ==========  storePrice  ========== //

    function testRevert_storePrice_unconfiguredAsset() public {
        // No base assets

        // Try to call storePrice for an asset not added and expect revert
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(twoma)
        );
        vm.expectRevert(err);
        vm.prank(writer);
        price.storePrice(address(twoma));
    }

    function testRevert_storePrice_priceZero(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Set weth price feed to zero
        ethUsdPriceFeed.setLatestAnswer(int256(0));

        // Try to call storePrice with weth and expect revert (single feed)
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(weth));
        vm.expectRevert(err);
        vm.prank(writer);
        price.storePrice(address(weth));

        // Set ohm price to zero
        ohmUsdPriceFeed.setLatestAnswer(int256(0));
        ohmEthPriceFeed.setLatestAnswer(int256(0));

        // Try to get current price and expect revert
        err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(ohm));
        vm.expectRevert(err);
        vm.prank(writer);
        price.storePrice(address(ohm));
    }

    function testRevert_storePrice_onlyPermissioned(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Try to call storePrice with non-permissioned address (this contract) and expect revert
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);
        price.storePrice(address(weth));

        // Try to call storePrice with permissioned address (writer) and expect to succeed
        vm.prank(writer);
        price.storePrice(address(weth));
    }

    function test_storePrice_noMovingAverage(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Get current cached data for weth from initialization
        uint48 start = uint48(block.timestamp);
        PRICEv2.Asset memory asset = price.getAssetData(address(weth));
        assertEq(asset.obs[0], uint256(2000e18));
        assertEq(asset.obs.length, 1);
        assertEq(asset.numObservations, 1);
        assertEq(asset.cumulativeObs, uint256(0)); // zero since no moving average
        assertEq(asset.lastObservationTime, start);
        assertEq(asset.nextObsIndex, 0); // always 0 when no moving average

        // Warp forward in time and store a new price
        vm.warp(uint256(start) + 1);
        ethUsdPriceFeed.setLatestAnswer(int256(2001e8));

        vm.prank(writer);
        price.storePrice(address(weth));

        // Get updated cached data for weth
        asset = price.getAssetData(address(weth));
        assertEq(asset.obs[0], uint256(2001e18));
        assertEq(asset.obs.length, 1);
        assertEq(asset.numObservations, 1);
        assertEq(asset.cumulativeObs, uint256(0)); // zero since no moving average
        assertEq(asset.lastObservationTime, uint48(start + 1));
        assertEq(asset.nextObsIndex, 0); // always 0 when no moving average

        // Store price again and check that event is emitted
        vm.prank(writer);
        vm.expectEmit(true, false, false, true);
        emit PriceStored(address(weth), uint256(2001e18), uint48(start + 1));
        price.storePrice(address(weth));
    }

    function test_storePrice_movingAverage(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

        // Get current cached data for onema from initialization
        uint48 start = uint48(block.timestamp);
        PRICEv2.Asset memory asset = price.getAssetData(address(onema));
        assertEq(asset.obs[14], uint256(5e18));
        assertEq(asset.obs.length, 15);
        assertEq(asset.numObservations, 15);
        // cumulative obs is random based on the nonce, store for comparison after new value added (which will be larger)
        uint256 cumulativeObs = asset.cumulativeObs;
        assertEq(asset.lastObservationTime, start);
        assertEq(asset.nextObsIndex, 0); // starts at zero after initialization since that is the oldest data point

        // Warp forward in time and store a new price
        vm.warp(uint256(start) + 1);
        onemaUsdPriceFeed.setLatestAnswer(int256(50e8));

        vm.prank(writer);
        price.storePrice(address(onema));

        // Get updated cached data for onema
        asset = price.getAssetData(address(onema));
        assertEq(asset.obs[0], uint256(50e18));
        assertEq(asset.obs[14], uint256(5e18));
        assertEq(asset.obs.length, 15);
        assertEq(asset.numObservations, 15);
        assertGt(asset.cumulativeObs, cumulativeObs); // new cumulative obs is larger than the previous one due to adding a high ob
        assertEq(asset.lastObservationTime, uint48(start + 1));
        assertEq(asset.nextObsIndex, 1); // next index is 1 since we added a new value

        // Add several new values to test ring buffer
        for (uint256 i; i < 14; i++) {
            vm.warp(uint256(start) + 2 + i);
            vm.prank(writer);
            price.storePrice(address(onema));
        }

        // Get updated cached data for onema
        asset = price.getAssetData(address(onema));
        assertEq(asset.obs[14], uint256(50e18));
        assertEq(asset.obs.length, 15);
        assertEq(asset.numObservations, 15);
        assertEq(asset.cumulativeObs, uint256(50e18) * 15); // all data points should be 50e18 now
        assertEq(asset.lastObservationTime, uint48(start + 15));
        assertEq(asset.nextObsIndex, 0); // next index should be zero since the ring buffer should wrap back around

        // Warp forward in time and store a new price
        vm.warp(uint256(start) + 16);
        vm.prank(writer);
        price.storePrice(address(onema));

        // Get updated cached data for onema
        asset = price.getAssetData(address(onema));
        assertEq(asset.nextObsIndex, 1); // next index should be 1 since we added a new value

        // Store price again and check that event is emitted
        vm.prank(writer);
        vm.expectEmit(true, false, false, true);
        emit PriceStored(address(onema), uint256(50e18), uint48(start + 16));
        price.storePrice(address(onema));
    }

    // ========== addAsset ========== //

    function testRevert_addAsset_exists(uint256 nonce_) public {
        // Add base assets to price module
        _addBaseAssets(nonce_);

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

        // Try and add the an asset again
        vm.startPrank(writer);

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
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_notContract() public {
        address eoa = 0x3040351e0D8EAf89A0F1b958Fa62915d804B2405;

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

        // Try and add the asset
        vm.startPrank(writer);

        bytes memory err = abi.encodeWithSignature("PRICE_AssetNotContract(address)", address(eoa));
        vm.expectRevert(err);

        price.addAsset(
            address(eoa), // address asset_
            false, // bool storeMovingAverage_ // don't track WETH MA
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            new uint256[](0), // uint256[] memory observations_
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_notPermissioned() public {
        MockERC20 asset = new MockERC20("Asset", "ASSET", 18);

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

        // Try and add the asset
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
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
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_noStrategy_noMovingAverage_multiplePriceFeeds() public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        ChainlinkPriceFeeds.TwoFeedParams memory ohmFeedTwoParams = ChainlinkPriceFeeds
            .TwoFeedParams(ohmEthPriceFeed, uint48(24 hours), ethUsdPriceFeed, uint48(24 hours));

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](2);
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

        // Try and add the asset
        vm.startPrank(writer);

        // Reverts as there is no strategy, but no MA + 2 price feeds > 1 requires a strategy
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsStrategyInsufficient(address,bytes,uint256,bool)",
            address(weth),
            abi.encode(PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0))),
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
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_useMovingAverage_noStoreMovingAverage() public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        // Try and add the asset
        vm.startPrank(writer);

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
            PRICEv2.Component( // Add a strategy so that addAsset has no other reason to revert
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                SimplePriceFeedStrategy.getAveragePrice.selector,
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_noStrategy_movingAverage_singlePriceFeed() public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        // Try and add the asset
        vm.startPrank(writer);

        // Reverts as there is no strategy, but MA + single price feed > 1 requires a strategy
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsStrategyInsufficient(address,bytes,uint256,bool)",
            address(weth),
            abi.encode(PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0))),
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
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function test_addAsset_noStrategy_noMovingAverage_singlePriceFeed_cachesCurrentPrice() public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        PRICEv2.Component memory strategyEmpty = PRICEv2.Component(
            toSubKeycode(bytes20(0)),
            bytes4(0),
            abi.encode(0)
        );

        // Try and add the asset
        vm.startPrank(writer);

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

        // Should have a cached result
        (uint256 price_, uint48 priceTimestamp_) = price.getPrice(
            address(weth),
            PRICEv2.Variant.LAST
        );
        assertEq(price_, 10e18);

        uint256[] memory expectedObs = new uint256[](1);
        expectedObs[0] = price_;

        // Configuration should be stored correctly
        PRICEv2.Asset memory asset = price.getAssetData(address(weth));
        assertEq(asset.approved, true);
        assertEq(asset.storeMovingAverage, false);
        assertEq(asset.useMovingAverage, false);
        assertEq(asset.movingAverageDuration, uint32(0));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(1));
        assertEq(asset.lastObservationTime, priceTimestamp_);
        assertEq(asset.cumulativeObs, uint256(0)); // Not updated when the moving average is not used/stored
        assertEq(asset.obs, expectedObs);
        assertEq(asset.strategy, abi.encode(strategyEmpty));
        assertEq(asset.feeds, abi.encode(feeds));
    }

    function test_addAsset_noStrategy_noMovingAverage_singlePriceFeed_singleObservation() public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        uint256[] memory observations = new uint256[](1);
        observations[0] = 9e18; // Junk number that should be different to anything from price feeds

        // Try and add the asset
        vm.startPrank(writer);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetAdded(address(weth));

        price.addAsset(
            address(weth), // address asset_
            false, // bool storeMovingAverage_
            false, // bool useMovingAverage_
            uint32(0), // uint32 movingAverageDuration_
            uint48(0), // uint48 lastObservationTime_
            observations, // uint256[] memory observations_
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );

        // Should have a cached result, populated from the given observations
        (uint256 price_, ) = price.getPrice(address(weth), PRICEv2.Variant.LAST);
        assertEq(price_, 9e18);
    }

    function testRevert_addAsset_noStrategy_noMovingAverage_singlePriceFeed_multipleObservations()
        public
    {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        uint256[] memory observations = new uint256[](2);
        observations[0] = 9e18;
        observations[0] = 8e18;

        vm.startPrank(writer);

        // Reverts as there should only be 1 observation (cached result) when no moving average is being stored
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsInvalidObservationCount(address,uint256,uint256,uint256)",
            address(weth),
            observations.length,
            0,
            1
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
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function testRevert_addAsset_noStrategy_noMovingAverage_singlePriceFeed_singleObservationZero()
        public
    {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        uint256[] memory observations = new uint256[](1);
        observations[0] = 0;

        vm.startPrank(writer);

        // Reverts as the observations input should not contain 0
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsObservationZero(address,uint256)",
            address(weth),
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
            PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
            feeds //
        );
    }

    function test_addAsset_strategy_movingAverage_multiplePriceFeeds(uint256 nonce_) public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        ChainlinkPriceFeeds.TwoFeedParams memory ohmFeedTwoParams = ChainlinkPriceFeeds
            .TwoFeedParams(ohmEthPriceFeed, uint48(24 hours), ethUsdPriceFeed, uint48(24 hours));

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](2);
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

        // Try and add the asset
        vm.startPrank(writer);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetAdded(address(weth));

        price.addAsset(
            address(weth), // address asset_
            true, // bool storeMovingAverage_
            true, // bool useMovingAverage_
            uint32(8 hours), // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            _makeRandomObservations(weth, feeds[0], nonce_, uint256(1)), // uint256[] memory observations_
            PRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                SimplePriceFeedStrategy.getAveragePrice.selector,
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds //
        );

        // Should have a cached result
        (uint256 price_, ) = price.getPrice(address(weth), PRICEv2.Variant.LAST);
        assertEq(price_, 10e18);
    }

    function test_addAsset_strategy_movingAverage_singlePriceFeed(uint256 nonce_) public {
        ChainlinkPriceFeeds.OneFeedParams memory ohmFeedOneParams = ChainlinkPriceFeeds
            .OneFeedParams(ohmUsdPriceFeed, uint48(24 hours));

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode target
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 selector
            abi.encode(ohmFeedOneParams) // bytes memory params
        );

        PRICEv2.Component memory averageStrategy = PRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getAveragePrice.selector,
            abi.encode(0) // no params required
        );

        uint256[] memory observations = _makeRandomObservations(weth, feeds[0], nonce_, uint256(1));
        uint256 expectedCumulativeObservations = observations[0];

        // Try and add the asset
        vm.startPrank(writer);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetAdded(address(weth));

        price.addAsset(
            address(weth), // address asset_
            true, // bool storeMovingAverage_
            true, // bool useMovingAverage_
            uint32(8 hours), // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            observations, // uint256[] memory observations_
            averageStrategy, // Component memory strategy_
            feeds //
        );

        // Should have a cached result
        (uint256 price_, uint48 priceTimestamp_) = price.getPrice(
            address(weth),
            PRICEv2.Variant.LAST
        );
        assertEq(price_, 10e18); // Average of 10, 10, 10

        // Configuration should be stored correctly
        PRICEv2.Asset memory asset = price.getAssetData(address(weth));
        assertEq(asset.approved, true);
        assertEq(asset.storeMovingAverage, true);
        assertEq(asset.useMovingAverage, true);
        assertEq(asset.movingAverageDuration, uint32(8 hours));
        assertEq(asset.nextObsIndex, uint16(0));
        assertEq(asset.numObservations, uint16(1)); // movingAverageDuration / observation frequency
        assertEq(asset.lastObservationTime, priceTimestamp_);
        assertEq(asset.cumulativeObs, expectedCumulativeObservations);
        assertEq(asset.obs, observations);
        assertEq(asset.strategy, abi.encode(averageStrategy));
        assertEq(asset.feeds, abi.encode(feeds));
    }

    function testRevert_addAsset_invalidPriceFeed() public {
        // Set up a new feed that will revert when run
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed,
            uint48(24 hours)
        );

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_ // Will revert as these parameters are not sufficient
        );

        PRICEv2.Component memory strategyEmpty = PRICEv2.Component(
            toSubKeycode(bytes20(0)),
            bytes4(0),
            abi.encode(0)
        );

        // Specify observations so that a lookup does not happen
        uint256[] memory observations = new uint256[](1);
        observations[0] = 2e18;

        // Try and add the asset
        vm.startPrank(writer);
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
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        price.removeAsset(address(weth));
    }

    function testRevert_removeAsset_notApproved() public {
        // No assets registered

        // Try and remove the asset
        vm.startPrank(writer);
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
        vm.startPrank(writer);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetRemoved(address(weth));

        price.removeAsset(address(weth));

        // Asset data is removed
        PRICEv2.Asset memory asset = price.getAssetData(address(weth));
        assertEq(asset.approved, false);

        address[] memory assetAddresses = price.getAssets();
        for (uint256 i; i < assetAddresses.length; i++) {
            assertFalse(assetAddresses[i] == address(weth));
        }
    }

    // ========== updateAssetPriceFeeds ========== //

    function test_updateAssetPriceFeeds(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up a new feed
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed,
            uint48(24 hours)
        );

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        // Update the asset's price feeds
        vm.startPrank(writer);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetPriceFeedsUpdated(address(weth));

        price.updateAssetPriceFeeds(address(weth), feeds);

        vm.stopPrank();

        // Check that the feeds were updated
        PRICEv2.Asset memory receivedAsset = price.getAssetData(address(weth));
        PRICEv2.Component[] memory receivedFeeds = abi.decode(
            receivedAsset.feeds,
            (PRICEv2.Component[])
        );
        PRICEv2.Component memory receivedFeedOne = receivedFeeds[0];

        assertEq(fromSubKeycode(receivedFeedOne.target), fromSubKeycode(feeds[0].target));
        assertEq(receivedFeedOne.selector, feeds[0].selector);
        assertEq(receivedFeedOne.params, feeds[0].params);
        assertEq(receivedFeeds.length, 1);
    }

    function testRevert_updateAssetPriceFeeds_notPermissioned(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up a new feed
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed,
            uint48(24 hours)
        );

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        // Try and update the asset
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        price.updateAssetPriceFeeds(address(weth), feeds);
    }

    function testRevert_updateAssetPriceFeeds_notApproved() public {
        // No existing assets

        // Set up a new feed
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed,
            uint48(24 hours)
        );

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        // Try and update the asset
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(weth)
        );
        vm.expectRevert(err);

        price.updateAssetPriceFeeds(address(weth), feeds);
    }

    function testRevert_updateAssetPriceFeeds_feedsEmpty(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up an empty feeds array
        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](0);

        // Try and update the asset
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsPriceFeedInsufficient(address,uint256,uint256)",
            address(weth),
            0,
            1
        );
        vm.expectRevert(err);

        price.updateAssetPriceFeeds(address(weth), feeds);
    }

    function testRevert_updateAssetPriceFeeds_submoduleNotInstalled(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up a new feed
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed,
            uint48(24 hours)
        );

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINKNEW"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        // Try and update the asset
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_SubmoduleNotInstalled(address,bytes)",
            address(weth),
            abi.encode(feeds[0].target)
        );
        vm.expectRevert(err);

        price.updateAssetPriceFeeds(address(weth), feeds);
    }

    function testRevert_updateAssetPriceFeeds_invalidPriceFeed(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up a new feed that will revert when run
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed,
            uint48(24 hours)
        );

        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](1);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_ // Will revert as these parameters are not sufficient
        );

        // Try and update the asset
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature("PRICE_PriceZero(address)", address(weth));
        vm.expectRevert(err);

        price.updateAssetPriceFeeds(address(weth), feeds);
    }

    function testRevert_updateAssetPriceFeeds_duplicatePriceFeeds(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up a new feed
        ChainlinkPriceFeeds.OneFeedParams memory ethParams = ChainlinkPriceFeeds.OneFeedParams(
            alphaUsdPriceFeed,
            uint48(24 hours)
        );

        // Create a feed array with two of the same feed
        PRICEv2.Component[] memory feeds = new PRICEv2.Component[](2);
        feeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );
        feeds[1] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // SubKeycode subKeycode_
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(ethParams) // bytes memory params_
        );

        // Try and update the asset
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_DuplicatePriceFeed(address,uint256)",
            address(weth),
            uint256(1)
        );
        vm.expectRevert(err);

        price.updateAssetPriceFeeds(address(weth), feeds);
    }

    // ========== updateAssetPriceStrategy ========== //

    function test_updateAssetPriceStrategy(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up a new strategy
        PRICEv2.Component memory averageStrategy = PRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0) // no params required
        );

        // Update the asset's strategy
        vm.startPrank(writer);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetPriceStrategyUpdated(address(weth));

        price.updateAssetPriceStrategy(address(weth), averageStrategy, false);

        vm.stopPrank();

        // Check that the feeds were updated
        PRICEv2.Asset memory receivedAsset = price.getAssetData(address(weth));
        PRICEv2.Component memory receivedStrategy = abi.decode(
            receivedAsset.strategy,
            (PRICEv2.Component)
        );

        assertEq(fromSubKeycode(receivedStrategy.target), fromSubKeycode(averageStrategy.target));
        assertEq(receivedStrategy.selector, averageStrategy.selector);
        assertEq(receivedStrategy.params, averageStrategy.params);
    }

    function testRevert_updateAssetPriceStrategy_notPermissioned(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up a new strategy
        PRICEv2.Component memory averageStrategy = PRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0) // no params required
        );

        // Try and update the asset
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        price.updateAssetPriceStrategy(address(weth), averageStrategy, false);
    }

    function testRevert_updateAssetPriceStrategy_notApproved() public {
        // No existing assets

        // Set up a new strategy
        PRICEv2.Component memory averageStrategy = PRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0) // no params required
        );

        // Try and update the asset
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(weth)
        );
        vm.expectRevert(err);

        price.updateAssetPriceStrategy(address(weth), averageStrategy, false);
    }

    function testRevert_updateAssetPriceStrategy_submoduleNotInstalled(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up a new strategy
        PRICEv2.Component memory averageStrategy = PRICEv2.Component(
            toSubKeycode("PRICE.SIMPLENEW"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0) // no params required
        );

        // Try and update the asset
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_SubmoduleNotInstalled(address,bytes)",
            address(weth),
            abi.encode(averageStrategy.target)
        );
        vm.expectRevert(err);

        price.updateAssetPriceStrategy(address(weth), averageStrategy, false);
    }

    function test_updateAssetPriceStrategy_noStrategy_singleFeed(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up a new strategy
        PRICEv2.Component memory strategyEmpty = PRICEv2.Component(
            toSubKeycode(bytes20(0)),
            bytes4(0),
            abi.encode(0)
        );

        // Update the asset's strategy
        vm.startPrank(writer);

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetPriceStrategyUpdated(address(weth));

        price.updateAssetPriceStrategy(address(weth), strategyEmpty, false);

        vm.stopPrank();

        // Check that the feeds were updated
        PRICEv2.Asset memory receivedAsset = price.getAssetData(address(weth));
        PRICEv2.Component memory receivedStrategy = abi.decode(
            receivedAsset.strategy,
            (PRICEv2.Component)
        );

        assertEq(fromSubKeycode(receivedStrategy.target), fromSubKeycode(strategyEmpty.target));
        assertEq(receivedStrategy.selector, strategyEmpty.selector);
        assertEq(receivedStrategy.params, strategyEmpty.params);
    }

    function testRevert_updateAssetPriceStrategy_noStrategy_multipleFeeds(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up a new strategy
        PRICEv2.Component memory strategyEmpty = PRICEv2.Component(
            toSubKeycode(bytes20(0)),
            bytes4(0),
            abi.encode(0)
        );

        // Update the asset's strategy
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsStrategyInsufficient(address,bytes,uint256,bool)",
            address(reserve),
            abi.encode(strategyEmpty),
            2,
            false
        );
        vm.expectRevert(err);

        price.updateAssetPriceStrategy(address(reserve), strategyEmpty, false);
    }

    function testRevert_updateAssetPriceStrategy_noStrategy_useMovingAverage_singleFeed(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        // Set up a new strategy
        PRICEv2.Component memory strategyEmpty = PRICEv2.Component(
            toSubKeycode(bytes20(0)),
            bytes4(0),
            abi.encode(0)
        );

        // Update the asset's strategy
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsStrategyInsufficient(address,bytes,uint256,bool)",
            address(onema),
            abi.encode(strategyEmpty),
            1,
            true
        );
        vm.expectRevert(err);

        price.updateAssetPriceStrategy(address(onema), strategyEmpty, true);
    }

    function testRevert_updateAssetPriceStrategy_invalidStrategy(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Set up a new strategy
        PRICEv2.Component memory averageStrategy = PRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getAveragePriceIfDeviation.selector,
            abi.encode(0) // will revert due to missing parameters
        );

        // Update the asset's strategy
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_StrategyFailed(address,bytes)",
            address(reserve),
            abi.encodeWithSignature("SimpleStrategy_ParamsInvalid(bytes)", abi.encode(0))
        );
        vm.expectRevert(err);

        price.updateAssetPriceStrategy(
            address(reserve), // The strategy will only be used if the number of feeds is > 1
            averageStrategy,
            false
        );
    }

    function testRevert_updateAssetPriceStrategy_movingAverage_storeMovingAverageDisabled(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        // Set up a new strategy
        PRICEv2.Component memory firstPriceStrategy = PRICEv2.Component(
            toSubKeycode("PRICE.SIMPLESTRATEGY"),
            SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
            abi.encode(0)
        );

        // Update the asset's strategy
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsStoreMovingAverageRequired(address)",
            address(weth)
        );
        vm.expectRevert(err);

        price.updateAssetPriceStrategy(
            address(weth),
            firstPriceStrategy,
            true // Will revert as weth does not store the moving average
        );
    }

    // ========== updateAssetMovingAverage =========== //

    function test_updateAssetMovingAverage_storeMovingAverage_existingObservations(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256[] memory observations = new uint256[](2);
        observations[0] = 2e18;
        observations[1] = 3e18;

        vm.startPrank(writer);

        // Expect an event when the configuration is updated
        vm.expectEmit(true, false, false, true);
        emit PriceStored(address(reserve), 3e18, uint48(block.timestamp));

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetMovingAverageUpdated(address(reserve));

        // Update the asset's moving average
        price.updateAssetMovingAverage(
            address(reserve),
            true, // Enable storeMovingAverage (previously enabled)
            uint32(observations.length * 8 hours), // movingAverageDuration_
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_
        );
        vm.stopPrank();

        // Check that the feeds were updated
        PRICEv2.Asset memory receivedAsset = price.getAssetData(address(reserve));

        assertEq(receivedAsset.storeMovingAverage, true);
        assertEq(receivedAsset.movingAverageDuration, uint32(observations.length * 8 hours));
        assertEq(receivedAsset.nextObsIndex, 0);
        assertEq(receivedAsset.numObservations, observations.length);
        assertEq(receivedAsset.lastObservationTime, uint48(block.timestamp));
        assertEq(receivedAsset.cumulativeObs, 2e18 + 3e18); // Overwrites existing value
        assertEq(receivedAsset.obs, observations); // Overwrites existing observations
        assertEq(receivedAsset.obs.length, observations.length); // Overwrites existing observations
    }

    function test_updateAssetMovingAverage_storeMovingAverage(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256[] memory observations = new uint256[](2);
        observations[0] = 2e18;
        observations[1] = 3e18;

        vm.startPrank(writer);

        // Expect an event when the configuration is updated
        vm.expectEmit(true, false, false, true);
        emit PriceStored(address(weth), 3e18, uint48(block.timestamp));

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetMovingAverageUpdated(address(weth));

        // Update the asset's moving average
        price.updateAssetMovingAverage(
            address(weth),
            true, // Enable storeMovingAverage (previously disabled)
            uint32(observations.length * 8 hours), // movingAverageDuration_
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_
        );
        vm.stopPrank();

        // Check that the feeds were updated
        PRICEv2.Asset memory receivedAsset = price.getAssetData(address(weth));

        assertEq(receivedAsset.storeMovingAverage, true);
        assertEq(receivedAsset.movingAverageDuration, uint32(observations.length * 8 hours));
        assertEq(receivedAsset.nextObsIndex, 0);
        assertEq(receivedAsset.numObservations, observations.length);
        assertEq(receivedAsset.lastObservationTime, uint48(block.timestamp));
        assertEq(receivedAsset.cumulativeObs, 2e18 + 3e18);
        assertEq(receivedAsset.obs, observations);
        assertEq(receivedAsset.obs.length, observations.length);
    }

    function testRevert_updateAssetMovingAverage_storeMovingAverage_invalidConfiguration(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256[] memory observations = new uint256[](1);
        observations[0] = 6e18; // new cached value for onema

        // We're removing the moving average from onema, but it's used by the strategy, so the update should fail
        bool storeMovingAverage = false;

        // Try to update onema's moving average to disable it
        // Will trigger a revert as the moving average is used by the strategy
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsStoreMovingAverageRequired(address)",
            address(onema)
        );
        vm.expectRevert(err);
        vm.prank(writer);
        price.updateAssetMovingAverage(
            address(onema),
            storeMovingAverage, // disable storeMovingAverage (previously enabled)
            uint32(0), // movingAverageDuration_
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_
        );
    }

    function testRevert_updateAssetMovingAverage_notPermissioned(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256[] memory observations = new uint256[](1);
        observations[0] = 2e18;

        // Try and update the asset
        bytes memory err = abi.encodeWithSignature(
            "Module_PolicyNotPermitted(address)",
            address(this)
        );
        vm.expectRevert(err);

        price.updateAssetMovingAverage(
            address(reserve),
            true, // Enable storeMovingAverage
            uint32(8 hours), // movingAverageDuration_
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_
        );
    }

    function testRevert_updateAssetMovingAverage_notApproved() public {
        // No existing assets

        // Observations
        uint256[] memory observations = new uint256[](1);
        observations[0] = 2e18;

        // Try and update the asset
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_AssetNotApproved(address)",
            address(reserve)
        );
        vm.expectRevert(err);

        price.updateAssetMovingAverage(
            address(reserve),
            true, // Enable storeMovingAverage
            uint32(8 hours), // movingAverageDuration_
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_
        );
    }

    function testRevert_updateAssetMovingAverage_storeMovingAverage_lastObservationTimeInFuture(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256[] memory observations = new uint256[](1);
        observations[0] = 2e18;

        // Update the asset's moving average
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsLastObservationTimeInvalid(address,uint48,uint48,uint48)",
            address(reserve),
            uint48(block.timestamp + 1),
            uint48(0),
            uint48(block.timestamp)
        );
        vm.expectRevert(err);

        price.updateAssetMovingAverage(
            address(reserve),
            true, // Enable storeMovingAverage
            uint32(8 hours), // movingAverageDuration_
            uint48(block.timestamp + 1), // lastObservationTime_ // timestamp in the future
            observations // observations_
        );
    }

    function testRevert_updateAssetMovingAverage_storeMovingAverage_inconsistentDuration(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256[] memory observations = new uint256[](1);
        observations[0] = 2e18;

        // Update the asset's moving average
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsMovingAverageDurationInvalid(address,uint32,uint32)",
            address(reserve),
            uint32(9 hours),
            uint32(8 hours)
        );
        vm.expectRevert(err);

        price.updateAssetMovingAverage(
            address(reserve),
            true, // Enable storeMovingAverage
            uint32(9 hours), // movingAverageDuration_ // 9 hours / 8 hours doesn't work
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_
        );
    }

    function testRevert_updateAssetMovingAverage_storeMovingAverage_observationZeroPrice(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256 zeroIndex = bound(nonce_, 0, 9);
        uint256[] memory observations = new uint256[](10);
        for (uint256 i; i < observations.length; i++) {
            if (i == zeroIndex) {
                observations[i] = 0;
            } else {
                observations[i] = 2e18;
            }
        }

        // Update the asset's moving average
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsObservationZero(address,uint256)",
            address(reserve),
            zeroIndex
        );
        vm.expectRevert(err);

        price.updateAssetMovingAverage(
            address(reserve),
            true, // Enable storeMovingAverage
            uint32(10 * 8 hours), // movingAverageDuration_ // 9 hours / 8 hours doesn't work
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_ // Will revert as there is a zero value
        );
    }

    function testRevert_updateAssetMovingAverage_storeMovingAverage_inconsistentObservationsLength(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256[] memory observations = new uint256[](2);
        observations[0] = 2e18;
        observations[1] = 3e18;

        // Update the asset's moving average
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsInvalidObservationCount(address,uint256,uint256,uint256)",
            address(reserve),
            observations.length,
            1,
            1
        );
        vm.expectRevert(err);

        price.updateAssetMovingAverage(
            address(reserve),
            true, // Enable storeMovingAverage
            uint32(8 hours), // movingAverageDuration_
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_ // should be length 1, but has 2
        );
    }

    function testRevert_updateAssetMovingAverage_storeMovingAverageFalse_inconsistentObservationsLength(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256[] memory observations = new uint256[](2);
        observations[0] = 2e18;
        observations[1] = 3e18;

        // Update the asset's moving average
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsInvalidObservationCount(address,uint256,uint256,uint256)",
            address(reserve),
            observations.length,
            0,
            1
        );
        vm.expectRevert(err);

        price.updateAssetMovingAverage(
            address(reserve),
            false, // Disable storeMovingAverage
            uint32(8 hours), // movingAverageDuration_
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_ // should be length 1, but has 2
        );
    }

    function testRevert_updateAssetMovingAverage_storeMovingAverageFalse_observationsEmpty(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256[] memory observations = new uint256[](1);

        // Update the asset's moving average
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsObservationZero(address,uint256)",
            address(reserve),
            0
        );
        vm.expectRevert(err);

        price.updateAssetMovingAverage(
            address(reserve),
            false, // Disable storeMovingAverage
            uint32(8 hours), // movingAverageDuration_
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_ // 0 value
        );
    }

    function testRevert_updateAssetMovingAverage_storeMovingAverageFalse_movingDurationNotZero(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);
        uint32 movingAverageDuration = uint32(bound(nonce_, 1, 10) * 8 hours);

        // Observations
        uint256[] memory observations = new uint256[](1);

        // Update the asset's moving average
        vm.startPrank(writer);
        bytes memory err = abi.encodeWithSignature(
            "PRICE_ParamsObservationZero(address,uint256)",
            address(reserve),
            0
        );
        vm.expectRevert(err);

        price.updateAssetMovingAverage(
            address(reserve),
            false, // Disable storeMovingAverage
            movingAverageDuration, // movingAverageDuration_ // multiple of 8 hours (which would be valid), but it should be 0
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_ // 0 value
        );
    }

    function test_updateAssetMovingAverage_storeMovingAverageFalse(uint256 nonce_) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256[] memory observations = new uint256[](1);
        observations[0] = 2e18;

        vm.startPrank(writer);

        // Expect an event when the configuration is updated
        vm.expectEmit(true, false, false, true);
        emit PriceStored(address(reserve), 2e18, uint48(block.timestamp));

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetMovingAverageUpdated(address(reserve));

        // Update the asset's moving average
        price.updateAssetMovingAverage(
            address(reserve),
            false, // Disable storeMovingAverage
            uint32(0), // movingAverageDuration_
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_
        );
        vm.stopPrank();

        // Check that the asset was updated
        PRICEv2.Asset memory receivedAsset = price.getAssetData(address(reserve));

        assertEq(receivedAsset.storeMovingAverage, false);
        assertEq(receivedAsset.movingAverageDuration, uint32(0));
        assertEq(receivedAsset.nextObsIndex, 0);
        assertEq(receivedAsset.numObservations, observations.length);
        assertEq(receivedAsset.lastObservationTime, uint48(block.timestamp));
        assertEq(receivedAsset.cumulativeObs, 0); // Not tracked
        assertEq(receivedAsset.obs, observations); // Overwrites existing observations
        assertEq(receivedAsset.obs.length, observations.length); // Overwrites existing observations
    }

    function test_updateAssetMovingAverage_storeMovingAverageFalse_observationsEmpty(
        uint256 nonce_
    ) public {
        _addBaseAssets(nonce_);

        // Observations
        uint256[] memory observations = new uint256[](0);

        // Get the current price for the asset
        (uint256 price_, uint48 timestamp_) = price.getPrice(
            address(reserve),
            PRICEv2.Variant.CURRENT
        );
        uint256[] memory expectedObservations = new uint256[](1);
        expectedObservations[0] = price_;

        vm.startPrank(writer);

        // Expect an event when the configuration is updated
        vm.expectEmit(true, false, false, true);
        emit PriceStored(address(reserve), price_, uint48(block.timestamp));

        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AssetMovingAverageUpdated(address(reserve));

        // Update the asset's moving average
        price.updateAssetMovingAverage(
            address(reserve),
            false, // Disable storeMovingAverage
            uint32(0), // movingAverageDuration_
            uint48(block.timestamp), // lastObservationTime_
            observations // observations_
        );
        vm.stopPrank();

        // Check that the asset was updated
        PRICEv2.Asset memory receivedAsset = price.getAssetData(address(reserve));

        assertEq(receivedAsset.storeMovingAverage, false);
        assertEq(receivedAsset.movingAverageDuration, uint32(0));
        assertEq(receivedAsset.nextObsIndex, 0);
        assertEq(receivedAsset.numObservations, 1);
        assertEq(receivedAsset.lastObservationTime, timestamp_);
        assertEq(receivedAsset.cumulativeObs, 0); // Not tracked
        assertEq(receivedAsset.obs, expectedObservations);
        assertEq(receivedAsset.obs.length, 1);
    }
}
