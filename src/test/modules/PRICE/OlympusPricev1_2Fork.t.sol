// SPDX-License-Identifier: UNLICENSED
// solhint-disable contract-name-camelcase
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
pragma solidity ^0.8.20;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

// Interfaces
import {IPRICEv1} from "src/modules/PRICE/IPRICE.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";

// Bophades
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {toSubKeycode} from "src/Submodules.sol";
import {PRICEv1} from "src/modules/PRICE/PRICE.v1.sol";
import {OlympusPricev1_2} from "src/modules/PRICE/OlympusPrice.v1_2.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {PythPriceFeeds} from "src/modules/PRICE/submodules/feeds/PythPriceFeeds.sol";
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";

import {EmissionManager} from "src/policies/EmissionManager.sol";
import {YieldRepurchaseFacility} from "src/policies/YieldRepurchaseFacility.sol";
import {OlympusHeart} from "src/policies/Heart.sol";
import {ConvertibleDepositAuctioneer} from "src/policies/deposits/ConvertibleDepositAuctioneer.sol";

import {UniswapV3Price} from "src/modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {ERC4626Price} from "src/modules/PRICE/submodules/feeds/ERC4626Price.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract OlympusPricev1_2ForkTest is Test {
    using FullMath for uint256;

    // Constants
    /// @dev Fork block after CD deployment, specified so that YRF and EM are at particular epochs
    /// @dev YRF epoch 4, EM epoch 1
    uint256 internal constant FORK_BLOCK = 24582000 + 1;
    address public constant OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public constant KERNEL = 0x2286d7f9639e8158FaD1169e76d1FbC38247f54b;
    address public constant HEART = 0x5824850D8A6E46a473445a5AF214C7EbD46c5ECB;
    address public constant ROLES_ADMIN = 0xb216d714d91eeC4F7120a732c11428857C659eC8;
    address public constant EMISSION_MANAGER = 0xA61b846D5D8b757e3d541E0e4F80390E28f0B6Ff;
    address public constant YIELD_REPO = 0x271e35a8555a62F6bA76508E85dfD76D580B0692;
    address public constant CONVERTIBLE_DEPOSIT_AUCTIONEER =
        0xF35193DA8C10e44aF10853Ba5a3a1a6F7529E39a;
    address public constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant PYTH = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    address public constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant CHAINLINK_BTC_USD = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address public constant CHAINLINK_ETH_BTC = 0xAc559F25B1619171CbC396a50854A3240b6A4e99;
    address public constant CHAINLINK_OHM_ETH = 0x9a72298ae3886221820B1c878d12D872087D3a23;
    address public constant REDSTONE_ETH_USD = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
    address public constant CHAINLINK_USDS_USD = 0xfF30586cD0F29eD462364C7e81375FC0C71219b1;
    address public constant CHAINLINK_DAI_USD = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public constant UNISWAP_OHM_WETH = 0x88051B0eea095007D3bEf21aB287Be961f3d8598;
    address public constant UNISWAP_OHM_SUSDS = 0x0858e2B0F9D75f7300B38D64482aC2C8DF06a755;
    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    uint256 internal constant OHM_USD_PRICE = 20e18;
    bytes32 internal constant ETH_USD_FEED_ID =
        0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 internal constant PYTH_USDS_USD_FEED_ID =
        0x77f0971af11cc8bac224917275c1bf55f2319ed5c654a1ca955c82fa2d297ea1;

    // Price validation bounds (18 decimals) - from production config
    uint256 internal constant USDS_MIN_PRICE = 0.99e18;
    uint256 internal constant USDS_MAX_PRICE = 1.01e18;
    uint256 internal constant SUSDS_MIN_PRICE = 1.06e18;
    uint256 internal constant SUSDS_MAX_PRICE = 1.10e18;
    uint256 internal constant ETH_MIN_PRICE = 1500e18;
    uint256 internal constant ETH_MAX_PRICE = 2100e18;
    uint256 internal constant OHM_MIN_PRICE = 17e18;
    uint256 internal constant OHM_MAX_PRICE = 22e18;
    uint256 internal constant BPS_MAX = 10_000;
    uint256 internal constant WETH_DEVIATION_BPS = 500; // 5% deviation
    uint256 internal constant USDS_DEVIATION_BPS = 100; // 1% deviation
    uint256 internal constant OHM_DEVIATION_BPS = 200; // 2% deviation
    uint256 internal constant PYTH_ETH_USD_MAX_CONFIDENCE = 10e18;
    uint256 internal constant PYTH_USDS_USD_MAX_CONFIDENCE = 0.1e18;
    uint48 internal constant WETH_UPDATE_THRESHOLD = 2 * 86400; // 48 hours (differs from production to allow for warping)
    uint48 internal constant WETH_ETH_BTC_UPDATE_THRESHOLD = 2 * 86400; // 48 hours (differs from production to allow for warping)
    uint48 internal constant WETH_BTC_USD_UPDATE_THRESHOLD = 2 * 86400; // 48 hours (differs from production to allow for warping)
    uint48 internal constant USDS_UPDATE_THRESHOLD = 2 * 86400; // 48 hours (differs from production to allow for warping)
    uint48 internal constant OHM_UPDATE_THRESHOLD = 2 * 86400; // 48 hours (differs from production to allow for warping)
    // 25-minute TWAP fits within 128-cardinality pools at 12s/block (requires 125 observations).
    uint32 internal constant OHM_WETH_OBSERVATION_WINDOW = 1500;
    uint32 internal constant OHM_SUSDS_OBSERVATION_WINDOW = 1500;
    uint32 internal constant _UNISWAP_V3_AVERAGE_BLOCK_TIME_SECONDS = 12;

    // System contracts
    Kernel public kernel;
    PRICEv1 public oldPrice;
    OlympusPricev1_2 public price;
    OlympusHeart public heart;
    EmissionManager public emissionManager;
    YieldRepurchaseFacility public yrf;
    ConvertibleDepositAuctioneer public cdAuctioneer;
    RolesAdmin public rolesAdmin;
    PriceConfigv2 public priceConfig;

    // Submodules
    ChainlinkPriceFeeds public chainlinkPrice;
    PythPriceFeeds public pythPrice;
    SimplePriceFeedStrategy public strategy;

    // Permissioned addresses
    address public kernelExecutor;

    event MarketCreated(
        uint256 indexed id,
        address indexed payoutToken,
        address indexed quoteToken,
        uint48 vesting,
        uint256 initialPrice
    );

    function _makeFeedExpectations(
        uint256 length_,
        uint256 minPrice_,
        uint256 maxPrice_
    ) internal pure returns (IPriceConfigv2.PriceFeedExpectation[] memory expectations_) {
        uint256 expectedPrice = (minPrice_ + maxPrice_) / 2;
        uint16 toleranceBps = SafeCast.encodeUInt16(
            maxPrice_.mulDivUp(BPS_MAX, expectedPrice) - BPS_MAX
        );

        expectations_ = new IPriceConfigv2.PriceFeedExpectation[](length_);
        for (uint256 i; i < length_; i++) {
            expectations_[i] = IPriceConfigv2.PriceFeedExpectation({
                expectedPrice: expectedPrice,
                toleranceBps: toleranceBps
            });
        }
    }

    function setUp() public {
        vm.createSelectFork("mainnet", FORK_BLOCK);

        // Get system contracts
        kernel = Kernel(KERNEL);
        kernelExecutor = kernel.executor();
        oldPrice = PRICEv1(address(kernel.getModuleForKeycode(toKeycode("PRICE"))));
        rolesAdmin = RolesAdmin(ROLES_ADMIN);

        // Get Heart, EmissionManager, YRF
        heart = OlympusHeart(HEART);
        emissionManager = EmissionManager(EMISSION_MANAGER);
        cdAuctioneer = ConvertibleDepositAuctioneer(CONVERTIBLE_DEPOSIT_AUCTIONEER);
        yrf = YieldRepurchaseFacility(YIELD_REPO);

        // Ensure that the EmissionManager's bond market capacity scalar is set to 1e18 (100%)
        // This is disabled (0) at the time of the fork
        vm.prank(TIMELOCK);
        emissionManager.setBondMarketCapacityScalar(1e18);

        // Get observation frequency from old PRICE module
        uint32 observationFrequency = uint32(oldPrice.observationFrequency());
        // Get minimum target price from old PRICE module (if available)
        uint256 minimumTargetPrice = oldPrice.minimumTargetPrice();
        uint256 targetPriceBeforeUpgrade = oldPrice.getTargetPrice();

        // Deploy new PRICE v1.2 module
        price = new OlympusPricev1_2(kernel, OHM, observationFrequency, minimumTargetPrice);

        // Deploy PriceConfigv2 policy
        priceConfig = new PriceConfigv2(kernel);

        // Deploy submodules
        chainlinkPrice = new ChainlinkPriceFeeds(price);
        pythPrice = new PythPriceFeeds(price);
        UniswapV3Price uniswapV3Price = new UniswapV3Price(
            price,
            _UNISWAP_V3_AVERAGE_BLOCK_TIME_SECONDS,
            UNISWAP_V3_FACTORY
        );
        ERC4626Price erc4626Price = new ERC4626Price(price);
        strategy = new SimplePriceFeedStrategy(price);

        // ========== SAME-BATCH PRICE v1.2 UPGRADE ==========
        // All operations happen in the same transaction (via kernelExecutor),
        // ensuring no Heart heartbeat occurs between upgrade and configuration.
        // This is the production pattern for zero-downtime upgrades.
        vm.startPrank(kernelExecutor);
        {
            // Step 1: Upgrade PRICE module to v1.2
            kernel.executeAction(Actions.UpgradeModule, address(price));

            // Step 2: Activate PriceConfigv2 policy
            kernel.executeAction(Actions.ActivatePolicy, address(priceConfig));
        }
        vm.stopPrank();

        // Install submodules (requires admin or price_admin role)
        // We assume that the DAO MS has the price_admin role
        vm.startPrank(DAO_MS);
        priceConfig.installSubmodule(address(chainlinkPrice));
        priceConfig.installSubmodule(address(pythPrice));
        priceConfig.installSubmodule(address(uniswapV3Price));
        priceConfig.installSubmodule(address(erc4626Price));
        priceConfig.installSubmodule(address(strategy));
        vm.stopPrank();

        // ========== CONFIGURE ASSETS (Same Batch Pattern) ==========
        // In production, this would be done by DAO MS in the same batch.
        _configureUsdsAsset();
        _configureWethAsset();
        _configureSusdsAsset();
        _configureOhmAsset();

        assertEq(
            price.getTargetPrice(),
            targetPriceBeforeUpgrade,
            "OHM target price should be preserved after PRICE v1.2 upgrade"
        );
    }

    // ========== HELPER FUNCTIONS ========== //

    function _configureOhmAsset() internal {
        vm.startPrank(DAO_MS); // DAO_MS has price_admin permissions

        // Create strategy component: getAveragePriceExcludingDeviations
        IPRICEv2.Component memory ohmStrategy = IPRICEv2.Component({
            target: toSubKeycode("PRICE.SIMPLESTRATEGY"),
            selector: SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            params: abi.encode(
                ISimplePriceFeedStrategy.DeviationParams({
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    deviationBps: uint16(OHM_DEVIATION_BPS),
                    revertOnInsufficientCount: true // strict mode
                })
            )
        });

        // Create feed components for the two Uniswap pools using getTokenTWAP, and the Chainlink OHM/ETH feed
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](3);

        // Feed 0: Uniswap OHM/WETH
        UniswapV3Price.UniswapV3Params memory ohmWethParams = UniswapV3Price.UniswapV3Params({
            pool: IUniswapV3Pool(UNISWAP_OHM_WETH),
            observationWindowSeconds: OHM_WETH_OBSERVATION_WINDOW
        });
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.UNIV3"),
            UniswapV3Price.getTokenTWAP.selector,
            abi.encode(ohmWethParams)
        );

        // Feed 1: Uniswap OHM/sUSDS
        UniswapV3Price.UniswapV3Params memory ohmSusdsParams = UniswapV3Price.UniswapV3Params({
            pool: IUniswapV3Pool(UNISWAP_OHM_SUSDS),
            observationWindowSeconds: OHM_SUSDS_OBSERVATION_WINDOW
        });
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.UNIV3"),
            UniswapV3Price.getTokenTWAP.selector,
            abi.encode(ohmSusdsParams)
        );

        // Feed 2: Chainlink OHM/ETH x ETH/USD
        feeds[2] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams({
                    firstFeed: AggregatorV2V3Interface(CHAINLINK_OHM_ETH),
                    firstUpdateThreshold: OHM_UPDATE_THRESHOLD,
                    secondFeed: AggregatorV2V3Interface(CHAINLINK_ETH_USD),
                    secondUpdateThreshold: WETH_UPDATE_THRESHOLD
                })
            )
        );

        _addOhmAssetWithMigratedObservations(ohmStrategy, feeds);

        vm.stopPrank();
    }

    function _addOhmAssetWithMigratedObservations(
        IPRICEv2.Component memory ohmStrategy_,
        IPRICEv2.Component[] memory feeds_
    ) internal {
        (
            uint32 movingAverageDuration,
            uint48 lastObservationTime,
            uint256[] memory observations
        ) = _getMigratedOhmObservations();

        // Add OHM asset via PriceConfig with moving average configuration
        priceConfig.addAsset(
            address(OHM),
            true, // storeMovingAverage
            false, // useMovingAverage
            movingAverageDuration,
            lastObservationTime,
            observations,
            ohmStrategy_,
            feeds_,
            _makeFeedExpectations(feeds_.length, OHM_MIN_PRICE, OHM_MAX_PRICE)
        );
    }

    function _getMigratedOhmObservations()
        internal
        view
        returns (
            uint32 movingAverageDuration_,
            uint48 lastObservationTime_,
            uint256[] memory observations_
        )
    {
        uint48 oldObservationFrequency = oldPrice.observationFrequency();
        assertEq(
            price.observationFrequency(),
            oldObservationFrequency,
            "Observation frequency should match PRICE v1"
        );

        uint32 oldNumObservations = oldPrice.numObservations();
        movingAverageDuration_ = uint32(oldPrice.movingAverageDuration());
        assertEq(movingAverageDuration_, uint32(30 days), "OHM moving average should be 30 days");

        // Use the live PRICE v1 observation count rather than a hard-coded seed. With an 8-hour
        // observation frequency and a 30-day moving average, this migrates 90 raw observations.
        uint256 expectedNumObservations = uint256(movingAverageDuration_) /
            uint256(oldObservationFrequency);
        assertEq(
            uint256(oldNumObservations),
            expectedNumObservations,
            "Observation count should match moving average duration"
        );

        // PRICE v1 stores observations in a ring buffer. PRICE v1.2 initializes nextObsIndex to
        // zero, so rotate the migrated data such that the oldest observation remains at index 0.
        observations_ = new uint256[](oldNumObservations);
        uint256 oldestObservationIndex = oldPrice.nextObsIndex();
        for (uint256 i = 0; i < oldNumObservations; i++) {
            uint256 sourceIndex = (oldestObservationIndex + i) % oldNumObservations;
            observations_[i] = oldPrice.observations(sourceIndex);
        }

        lastObservationTime_ = oldPrice.lastObservationTime();
    }

    function _configureWethAsset() internal {
        // Configure WETH with production configuration: 4 feeds with deviation strategy
        // Feeds: Chainlink ETH/USD, RedStone ETH/USD (via Chainlink interface), Pyth ETH/USD, Derived ETH/BTC×BTC/USD

        vm.startPrank(DAO_MS); // DAO_MS has price_admin permissions

        // Create strategy component: getAveragePriceExcludingDeviations (from production config)
        IPRICEv2.Component memory wethStrategy = IPRICEv2.Component({
            target: toSubKeycode("PRICE.SIMPLESTRATEGY"),
            selector: SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            params: abi.encode(
                ISimplePriceFeedStrategy.DeviationParams({
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    deviationBps: uint16(WETH_DEVIATION_BPS),
                    revertOnInsufficientCount: true // wethStrictMode from production
                })
            )
        });

        // Create feed components - 4 feeds matching production configuration
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](4);

        // Feed 0: Chainlink ETH/USD
        ChainlinkPriceFeeds.OneFeedParams memory chainlinkEthUsdParams = ChainlinkPriceFeeds
            .OneFeedParams(AggregatorV2V3Interface(CHAINLINK_ETH_USD), WETH_UPDATE_THRESHOLD);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(chainlinkEthUsdParams)
        );

        // Feed 1: RedStone ETH/USD (uses Chainlink interface)
        // Note: RedStone is accessed via Chainlink interface in production
        ChainlinkPriceFeeds.OneFeedParams memory redstoneEthUsdParams = ChainlinkPriceFeeds
            .OneFeedParams(AggregatorV2V3Interface(REDSTONE_ETH_USD), WETH_UPDATE_THRESHOLD);
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(redstoneEthUsdParams)
        );

        // Feed 2: Pyth ETH/USD
        PythPriceFeeds.OneFeedParams memory pythEthUsdParams = PythPriceFeeds.OneFeedParams(
            PYTH,
            ETH_USD_FEED_ID,
            WETH_UPDATE_THRESHOLD,
            PYTH_ETH_USD_MAX_CONFIDENCE
        );
        feeds[2] = IPRICEv2.Component(
            toSubKeycode("PRICE.PYTH"),
            PythPriceFeeds.getOneFeedPrice.selector,
            abi.encode(pythEthUsdParams)
        );

        // Feed 3: Derived ETH-USD from ETH-BTC × BTC-USD
        ChainlinkPriceFeeds.TwoFeedParams memory derivedEthUsdParams = ChainlinkPriceFeeds
            .TwoFeedParams({
                firstFeed: AggregatorV2V3Interface(CHAINLINK_ETH_BTC),
                firstUpdateThreshold: WETH_ETH_BTC_UPDATE_THRESHOLD,
                secondFeed: AggregatorV2V3Interface(CHAINLINK_BTC_USD),
                secondUpdateThreshold: WETH_BTC_USD_UPDATE_THRESHOLD
            });
        feeds[3] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(derivedEthUsdParams)
        );

        // Add WETH asset via PriceConfig
        // Note: Not storing moving average for WETH in production config
        priceConfig.addAsset(
            address(WETH),
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0), // movingAverageDuration
            uint48(0), // lastObservationTime
            new uint256[](0), // observations
            wethStrategy,
            feeds,
            _makeFeedExpectations(feeds.length, ETH_MIN_PRICE, ETH_MAX_PRICE)
        );

        vm.stopPrank();
    }

    function _configureUsdsAsset() internal {
        // Configure USDS with production configuration: 3 feeds with deviation strategy
        // Feeds: Chainlink USDS/USD, Chainlink DAI/USD, Pyth USDS/USD

        vm.startPrank(DAO_MS); // DAO_MS has price_admin permissions

        // Create strategy component: getAveragePriceExcludingDeviations
        IPRICEv2.Component memory usdsStrategy = IPRICEv2.Component({
            target: toSubKeycode("PRICE.SIMPLESTRATEGY"),
            selector: SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            params: abi.encode(
                ISimplePriceFeedStrategy.DeviationParams({
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    deviationBps: uint16(USDS_DEVIATION_BPS),
                    revertOnInsufficientCount: true // strict mode
                })
            )
        });

        // Create feed components - 3 feeds
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](3);

        // Feed 0: Chainlink USDS/USD
        ChainlinkPriceFeeds.OneFeedParams memory chainlinkUsdsUsdParams = ChainlinkPriceFeeds
            .OneFeedParams(AggregatorV2V3Interface(CHAINLINK_USDS_USD), USDS_UPDATE_THRESHOLD);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(chainlinkUsdsUsdParams)
        );

        // Feed 1: Chainlink DAI/USD
        ChainlinkPriceFeeds.OneFeedParams memory chainlinkDaiUsdParams = ChainlinkPriceFeeds
            .OneFeedParams(AggregatorV2V3Interface(CHAINLINK_DAI_USD), USDS_UPDATE_THRESHOLD);
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(chainlinkDaiUsdParams)
        );

        // Feed 2: Pyth USDS/USD
        PythPriceFeeds.OneFeedParams memory pythUsdsUsdParams = PythPriceFeeds.OneFeedParams(
            PYTH,
            PYTH_USDS_USD_FEED_ID,
            USDS_UPDATE_THRESHOLD,
            PYTH_USDS_USD_MAX_CONFIDENCE
        );
        feeds[2] = IPRICEv2.Component(
            toSubKeycode("PRICE.PYTH"),
            PythPriceFeeds.getOneFeedPrice.selector,
            abi.encode(pythUsdsUsdParams)
        );

        // Add USDS asset via PriceConfig
        priceConfig.addAsset(
            address(USDS),
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0), // movingAverageDuration
            uint48(0), // lastObservationTime
            new uint256[](0), // observations
            usdsStrategy,
            feeds,
            _makeFeedExpectations(feeds.length, USDS_MIN_PRICE, USDS_MAX_PRICE)
        );

        vm.stopPrank();
    }

    function _configureSusdsAsset() internal {
        // Configure sUSDS using ERC4626 submodule (derives price from USDS)

        vm.startPrank(DAO_MS); // DAO_MS has price_admin permissions

        // Empty strategy (single feed, no aggregation needed)
        IPRICEv2.Component memory susdsStrategy = IPRICEv2.Component({
            target: toSubKeycode(""),
            selector: bytes4(0),
            params: abi.encode("")
        });

        // Single ERC4626 feed - derives price from the underlying asset (USDS)
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component({
            target: toSubKeycode("PRICE.ERC4626"),
            selector: ERC4626Price.getPriceFromUnderlying.selector,
            params: "" // Empty params - underlying is derived from the asset being configured
        });

        // Add sUSDS asset via PriceConfig
        priceConfig.addAsset(
            address(SUSDS),
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0), // movingAverageDuration
            uint48(0), // lastObservationTime
            new uint256[](0), // observations
            susdsStrategy,
            feeds,
            _makeFeedExpectations(feeds.length, SUSDS_MIN_PRICE, SUSDS_MAX_PRICE)
        );

        vm.stopPrank();
    }

    /// @notice Validates that a price is within a reasonable range
    function _assertPriceInRange(
        uint256 price_,
        uint256 minPrice_,
        uint256 maxPrice_,
        string memory assetName_
    ) internal pure {
        assertGe(price_, minPrice_, string.concat(assetName_, " price below minimum"));
        assertLe(price_, maxPrice_, string.concat(assetName_, " price above maximum"));
    }

    /// @notice Validates that configured prices are within reasonable bounds
    function test_priceValidation_assetPricesAreSane() public view {
        // Validate USDS price (uses real feeds)
        uint256 usdsPrice = price.getPrice(USDS);
        _assertPriceInRange(usdsPrice, USDS_MIN_PRICE, USDS_MAX_PRICE, "USDS");

        // Validate sUSDS price (uses ERC4626 submodule)
        uint256 susdsPrice = price.getPrice(SUSDS);
        _assertPriceInRange(susdsPrice, SUSDS_MIN_PRICE, SUSDS_MAX_PRICE, "sUSDS");

        // Validate WETH price (uses real feeds)
        uint256 wethPrice = price.getPrice(WETH);
        _assertPriceInRange(wethPrice, ETH_MIN_PRICE, ETH_MAX_PRICE, "WETH");

        // Validate OHM price (uses Uniswap V3 TWAP feeds)
        uint256 ohmPrice = price.getPrice(OHM);
        _assertPriceInRange(ohmPrice, OHM_MIN_PRICE, OHM_MAX_PRICE, "OHM");
    }

    function test_priceValidation_ohmUsesDeviationFilteredAverage() public view {
        IPRICEv2.Asset memory ohmAsset = price.getAssetData(OHM);
        IPRICEv2.Component memory ohmStrategy = abi.decode(ohmAsset.strategy, (IPRICEv2.Component));
        ISimplePriceFeedStrategy.DeviationParams memory params = abi.decode(
            ohmStrategy.params,
            (ISimplePriceFeedStrategy.DeviationParams)
        );

        assertEq(
            ohmStrategy.selector,
            SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            "OHM should use deviation-filtered average"
        );
        assertEq(
            params.deviationBps,
            OHM_DEVIATION_BPS,
            "OHM deviation threshold should match config"
        );
        assertTrue(params.revertOnInsufficientCount, "OHM strategy should use strict mode");
    }

    function test_priceValidation_ohmDeviationStrategyExcludesOutlier() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 202e17;
        prices[1] = 205e17;
        prices[2] = 30e18;

        uint256 resolvedPrice = strategy.getAveragePriceExcludingDeviations(
            prices,
            abi.encode(
                ISimplePriceFeedStrategy.DeviationParams({
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    deviationBps: uint16(OHM_DEVIATION_BPS),
                    revertOnInsufficientCount: true
                })
            )
        );

        // prices[0] = 20.2e18 (18 decimals)
        // prices[1] = 20.5e18 (18 decimals)
        // prices[2] = 30e18 (18 decimals)
        // Median benchmark is 20.5e18. With a 2% threshold, 30e18 deviates and is excluded.
        // Expected: (20.2e18 + 20.5e18) / 2 = 20.35e18.
        assertEq(resolvedPrice, 2035e16, "OHM strategy should exclude the outlier");
    }

    function _warpToNextHeartbeat() internal {
        // Warp to the next heartbeat timestamp
        vm.warp(heart.lastBeat() + heart.frequency());
    }

    modifier warpToNextHeartbeat() {
        _warpToNextHeartbeat();
        _;
    }

    modifier beat() {
        heart.beat();

        console2.log("EM epoch", emissionManager.beatCounter());
        console2.log("YRF epoch", yrf.epoch());
        console2.log("CDA auctionResultsNextIndex", cdAuctioneer.getAuctionResultsNextIndex());
        _;
    }

    modifier givenOhmPrice(uint256 price_) {
        // Mock the getPrice function to return a specific OHM price
        // This allows us to test specific premium scenarios without manipulating pool state
        // The selector for getPrice(address,Variant) is 0x5d5d8e3b
        bytes4 getPriceWithVariantSelector = bytes4(keccak256("getPrice(address,(uint8,bytes1))"));
        bytes4 getPriceSelector = bytes4(keccak256("getPrice(address)"));

        vm.mockCall(
            address(price),
            abi.encodeWithSelector(getPriceSelector, OHM),
            abi.encode(price_)
        );
        vm.mockCall(
            address(price),
            abi.encodeWithSelector(IPRICEv1.getCurrentPrice.selector),
            abi.encode(price_)
        );
        vm.mockCall(
            address(price),
            abi.encodeWithSelector(IPRICEv1.getLastPrice.selector),
            abi.encode(price_)
        );
        vm.mockCall(
            address(price),
            abi.encodeWithSelector(getPriceWithVariantSelector, OHM, IPRICEv2.Variant.CURRENT),
            abi.encode(price_, SafeCast.encodeUInt48(block.timestamp))
        );
        // Also mock LAST variant to return the same price
        vm.mockCall(
            address(price),
            abi.encodeWithSelector(getPriceWithVariantSelector, OHM, IPRICEv2.Variant.LAST),
            abi.encode(price_, SafeCast.encodeUInt48(block.timestamp))
        );
        _;
    }

    modifier givenAuctionTrackingPeriod(uint8 period_) {
        vm.prank(TIMELOCK);
        cdAuctioneer.setAuctionTrackingPeriod(period_);
        _;
    }

    modifier givenBondMarketCapacityScalar(uint256 scalar_) {
        vm.prank(TIMELOCK);
        emissionManager.setBondMarketCapacityScalar(scalar_);
        _;
    }

    // ========== TESTS ========== //

    // ========== GAS SNAPSHOTS ========== //

    // Raw getPrice() call gas snapshot
    //  [X] measures gas for OHM price lookup using Variant.LAST

    function test_gasSnapshot_getPrice_OHM() public {
        // Snapshot gas for raw getPrice() call
        // This measures the cost of looking up a cached price (Variant.LAST default)
        vm.startSnapshotGas("getPrice_OHM");
        uint256 ohmPrice = price.getPrice(OHM);
        uint256 gasUsed = vm.stopSnapshotGas();

        console2.log("getPrice(OHM) gas used:", gasUsed);
        console2.log("OHM price (18 decimals):", ohmPrice);

        // Verify price is in expected range
        _assertPriceInRange(ohmPrice, OHM_MIN_PRICE, OHM_MAX_PRICE, "OHM");
    }

    //  [X] resolves the OHM price when one OHM feed path fails
    function test_getPrice_OHM_singleFeedFailure() public {
        uint32[] memory observationWindow = new uint32[](2);
        observationWindow[0] = OHM_WETH_OBSERVATION_WINDOW;
        observationWindow[1] = 0;

        vm.mockCallRevert(
            UNISWAP_OHM_WETH,
            abi.encodeWithSelector(bytes4(keccak256("observe(uint32[])")), observationWindow),
            "OHM/WETH unavailable"
        );

        uint256 ohmPrice = price.getPrice(OHM);

        vm.clearMockedCalls();

        _assertPriceInRange(ohmPrice, OHM_MIN_PRICE, OHM_MAX_PRICE, "OHM");
    }

    // ========== HEARTBEAT INTEGRATION ========== //

    // when the heartbeat is called
    //  [X] the OHM moving average is updated
    //  [X] the EmissionManager premium is uses the price feed
    function test_beat() public {
        // Get initial state
        uint48 lastObsTimeBefore = price.lastObservationTime();
        uint256 ohmMABefore = price.getMovingAverage();
        uint256 ohmPrice = price.getPrice(OHM);

        console2.log("OHM price (18 decimals):", ohmPrice);

        // Warp forward by observation frequency
        _warpToNextHeartbeat();

        // Snapshot gas for heartbeat call
        // This measures the full cost of a heartbeat including:
        // - PRICE module storing observations
        // - EmissionManager premium calculation
        // - YieldRepurchaseFacility epoch tracking
        // - ConvertibleDepositAuctioneer auction management
        vm.startSnapshotGas("heartbeat");
        heart.beat();
        uint256 gasUsed = vm.stopSnapshotGas();

        console2.log("Heartbeat gas used:", gasUsed);
        console2.log("EM epoch", emissionManager.beatCounter());
        console2.log("YRF epoch", yrf.epoch());
        console2.log("CDA auctionResultsNextIndex", cdAuctioneer.getAuctionResultsNextIndex());

        // Verify PRICE moving average was updated
        uint48 lastObsTimeAfter = price.lastObservationTime();
        assertEq(
            lastObsTimeAfter,
            SafeCast.encodeUInt48(block.timestamp),
            "Last observation time should be updated"
        );
        assertGt(lastObsTimeAfter, lastObsTimeBefore, "Last observation time should be updated");

        // Verify moving average was updated
        // The price at this block is around $17, so it will drive the moving average down
        uint256 ohmMAAfter = price.getMovingAverage();
        assertLt(ohmMAAfter, ohmMABefore, "Moving average should be updated");
    }

    // when the EM reaches the 0 epoch
    //  when the price in the current block is below 50% premium
    //   [X] the CD auction is disabled

    function test_emissionManager_givenEpochZero_belowPremium()
        public
        givenOhmPrice(24e18) // Above 50% premium
        warpToNextHeartbeat
        beat // Epoch 2
        givenOhmPrice(17e18) // Below 50% premium
        warpToNextHeartbeat
        beat // Epoch 0
    {
        // Verify that the CD auction target is 0 (disabled)
        assertEq(cdAuctioneer.getAuctionParameters().target, 0, "CD auction target should be 0");
    }

    //  when the price in the current block is above 50% premium
    //   [X] the CD auction min price uses the current price

    function test_emissionManager_givenEpochZero_abovePremium()
        public
        givenOhmPrice(24e18) // Above 50% premium
        warpToNextHeartbeat
        beat // Epoch 1
        warpToNextHeartbeat
        beat // Epoch 2
        givenOhmPrice(24e18) // Above 50% premium
        warpToNextHeartbeat
        beat // Epoch 0
    {
        // Calculate the expected min price
        uint256 expectedMinPrice = emissionManager.getMinPriceFor(24e18);

        assertEq(
            cdAuctioneer.getAuctionParameters().minPrice,
            expectedMinPrice,
            "CD auction min price should be the expected min price"
        );
        // No need to test the target, as the premium has already been tested
    }

    //  when the end of the auction tracking period is reached
    //   [X] the EM market is created with the current price

    function test_emissionManager_endOfAuctionTrackingPeriod()
        public
        givenAuctionTrackingPeriod(2)
        givenBondMarketCapacityScalar(1e18)
        givenOhmPrice(24e18)
        warpToNextHeartbeat
        beat // Epoch 2
        givenOhmPrice(24e18)
        warpToNextHeartbeat
        beat // Epoch 0, auction results next index is 1
        warpToNextHeartbeat
        beat // Epoch 1
        warpToNextHeartbeat
        beat // Epoch 2
        givenOhmPrice(24e18)
        warpToNextHeartbeat
    {
        uint256 expectedInitialPrice = 24e36; // Bond market scaling
        uint256 expectedMarketId = 730 + 1;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit MarketCreated(
            expectedMarketId,
            address(OHM),
            address(emissionManager.reserve()),
            uint48(0),
            expectedInitialPrice
        );

        // Beat
        // Epoch 0, auction results next index is 0
        vm.startSnapshotGas("heartbeat_emissionManager");
        heart.beat();
        vm.stopSnapshotGas();

        // Verify
        assertEq(
            emissionManager.activeMarketId(),
            expectedMarketId,
            "Active market ID should be the expected market ID"
        );
    }

    // when the heartbeat launches a YRF market
    //  [X] the YRF market is created with the price from the price feed

    function test_yieldRepurchaseFacility()
        public
        givenOhmPrice(24e18) // Above 50% premium
        warpToNextHeartbeat
        beat // YRF epoch 5
        warpToNextHeartbeat
    {
        // Calculate the expected initial price
        // From YRF._createMarket()
        // 10 ** (18 * 2) / ((24e18 * 97) / 100)
        // = 42955326460481099
        // Adjusted by 1e17 for bond market scaling
        uint256 expectedInitialPrice = 42955326460481099 * 1e17;
        uint256 expectedMarketId = 728 + 1;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit MarketCreated(
            expectedMarketId,
            address(emissionManager.reserve()),
            address(OHM),
            uint48(0),
            expectedInitialPrice
        );

        // Beat
        // Epoch 6
        vm.startSnapshotGas("heartbeat_yrf");
        heart.beat();
        vm.stopSnapshotGas();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
