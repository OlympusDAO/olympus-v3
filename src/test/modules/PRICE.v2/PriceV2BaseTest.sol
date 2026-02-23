// SPDX-License-Identifier: Unlicense
// solhint-disable max-states-count
// solhint-disable custom-errors
/// forge-lint: disable-start(mixed-case-variable,mixed-case-function)
pragma solidity >=0.8.0;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

// Mocks
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockBalancerWeightedPool} from "test/mocks/MockBalancerPool.sol";
import {MockBalancerVault} from "test/mocks/MockBalancerVault.sol";
import {MockUniV3Pair} from "test/mocks/MockUniV3Pair.sol";

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";

// Libraries
import {FullMath} from "libraries/FullMath.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

// Bophades
import {Actions, Kernel} from "src/Kernel.sol";
import {ModuleWithSubmodules} from "src/Submodules.sol";
import {fromSubKeycode, toSubKeycode} from "src/Submodules.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {UniswapV3Price} from "modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {BalancerPoolTokenPrice, IVault, IWeightedPool} from "modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";

abstract contract PriceV2BaseTest is Test {
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

    address internal moduleWriter;
    address internal priceWriter;

    int256 internal constant CHANGE_DECIMALS = 1e4;
    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;
    uint32 internal constant TWAP_PERIOD = 24 hours;

    // Re-declare events from PRICE.v2.sol
    event PriceStored(address indexed asset_, uint256 price_, uint48 timestamp_);
    event AssetAdded(address indexed asset_);
    event AssetRemoved(address indexed asset_);
    event AssetPriceFeedsUpdated(address indexed asset_);
    event AssetPriceStrategyUpdated(address indexed asset_);
    event AssetMovingAverageUpdated(address indexed asset_);

    function setUp() public virtual {
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
            // Create ticks for a 24 hour second observation period
            // Set to a price of 1 OHM = 0.005 ETH
            // Weighted tick needs to be 154257 (if OHM is token0) or -154257 (if OHM is token1) (as if 5,000,000 ETH per OHM because of the decimal difference)
            // 154257 * 24 * 60 * 60 = 13_327_804_800
            // Therefore, we need a tick difference of 13_327_804_800 (if OHM is token0) or -13_327_804_800 (if OHM is token1)
            uint56 cumulativeValue = 1_000_000_000 + 13_327_804_800;
            int56[] memory tickCumulatives = new int56[](2);
            /// forge-lint: disable-start(unsafe-typecast)
            tickCumulatives[0] = ohmFirst ? int56(1000000000) : -int56(1000000000);
            tickCumulatives[1] = ohmFirst ? int56(cumulativeValue) : -int56(cumulativeValue);
            /// forge-lint: disable-end(unsafe-typecast)
            ohmEthUniV3Pool.setTickCumulatives(tickCumulatives);
        }

        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy price module
            price = new OlympusPricev2(kernel, 18, OBSERVATION_FREQUENCY);

            // Deploy mock module writer
            moduleWriter = price.generateGodmodeFixture(type(ModuleWithSubmodules).name);
            priceWriter = price.generateGodmodeFixture(type(OlympusPricev2).name);

            // Deploy price submodules
            chainlinkPrice = new ChainlinkPriceFeeds(price);
            bptPrice = new BalancerPoolTokenPrice(price, IVault(address(balVault)));
            strategy = new SimplePriceFeedStrategy(price);
            univ3Price = new UniswapV3Price(price);
        }

        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.ActivatePolicy, address(moduleWriter));
            kernel.executeAction(Actions.ActivatePolicy, address(priceWriter));

            // Install submodules on price module
            vm.startPrank(moduleWriter);
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
        IPRICEv2.Component memory feed,
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
            /// forge-lint: disable-next-line(unsafe-typecast)
            obs[i - 1] = uint256(fetchedPrice);

            /// Calculate a random percentage change from -10% to +10% using the nonce and observation number
            /// change ∈ [-1000, +1000] where CHANGE_DECIMALS = 1e4, giving ±10%
            int256 range = 1000;
            change =
                (int256(uint256(keccak256(abi.encodePacked(nonce, i)))) % (2 * range + 1)) -
                range;

            /// Calculate the new ohmEth price
            fetchedPrice = (fetchedPrice * (CHANGE_DECIMALS + change)) / CHANGE_DECIMALS;
        }

        return obs;
    }

    function _addOneMAAsset(uint256 nonce_, uint256 numObs_) internal {
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
            /// forge-lint: disable-next-line(unsafe-typecast)
            uint32(numObs_) * OBSERVATION_FREQUENCY, // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            _makeRandomObservations(onema, feeds[0], nonce_, uint256(numObs_)), // uint256[] memory observations_
            IPRICEv2.Component(
                toSubKeycode("PRICE.SIMPLESTRATEGY"),
                SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                abi.encode(0) // no params required
            ), // Component memory strategy_
            feeds // Component[] feeds_
        );
        vm.stopPrank();
    }

    function _addOneMAAssetWithObservations(uint256[] memory observations_) internal {
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
            uint32(observations_.length) * OBSERVATION_FREQUENCY, // uint32 movingAverageDuration_
            uint48(block.timestamp), // uint48 lastObservationTime_
            observations_, // uint256[] memory observations_
            IPRICEv2.Component(
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
        vm.startPrank(priceWriter);

        // WETH - One feed with no strategy
        {
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

        // ALPHA - One feed with no strategy (simplifies testing certain cases)
        {
            ChainlinkPriceFeeds.OneFeedParams memory alphaParams = ChainlinkPriceFeeds
                .OneFeedParams(alphaUsdPriceFeed, uint48(24 hours));

            IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
            feeds[0] = IPRICEv2.Component(
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
                IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
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
                .UniswapV3Params(ohmEthUniV3Pool, TWAP_PERIOD);

            IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](3);
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
            feeds[2] = IPRICEv2.Component(
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
                IPRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getMedianPriceIfDeviation.selector,
                    abi.encode(
                        ISimplePriceFeedStrategy.DeviationParams({
                            deviationBps: 300,
                            revertOnInsufficientCount: false
                        })
                    )
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

            IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
            feeds[0] = IPRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(reserveFeedOneParams)
            );
            feeds[1] = IPRICEv2.Component(
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
                IPRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getAveragePriceIfDeviation.selector,
                    abi.encode(
                        ISimplePriceFeedStrategy.DeviationParams({
                            deviationBps: 300,
                            revertOnInsufficientCount: false
                        })
                    )
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

            IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
            feeds[0] = IPRICEv2.Component(
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
                IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // Component memory strategy_
                feeds // Component[] feeds_
            );
        }

        // ONEMA - One feed + MA using the getFirstNonZeroPrice strategy
        {
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
                uint32(5 days), // uint32 movingAverageDuration_
                uint48(block.timestamp), // uint48 lastObservationTime_
                _makeRandomObservations(onema, feeds[0], nonce_, uint256(15)), // uint256[] memory observations_
                IPRICEv2.Component(
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

            IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
            feeds[0] = IPRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(twomaFeedOneParams)
            );
            feeds[1] = IPRICEv2.Component(
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
                IPRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getAveragePrice.selector,
                    abi.encode(0) // no params required
                ), // Component memory strategy_
                feeds // Component[] feeds_
            );
        }

        vm.stopPrank();
    }
}
