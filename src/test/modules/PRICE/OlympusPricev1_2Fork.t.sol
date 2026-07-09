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
import {Strings} from "@openzeppelin-4.8.0/utils/Strings.sol";

// Bophades
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {toSubKeycode} from "src/Submodules.sol";
import {PRICEv1} from "src/modules/PRICE/PRICE.v1.sol";
import {OlympusPricev1_2} from "src/modules/PRICE/OlympusPrice.v1_2.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
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
import {IUniswapV3Pool} from "@uniswap-v3-core-1.0.1/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap-v3-core-1.0.1/libraries/TickMath.sol";
import {OracleLibrary} from "@uniswap-v3-periphery-1.4.2/libraries/OracleLibrary.sol";

contract OlympusPricev1_2ForkTest is Test {
    using FullMath for uint256;

    // Constants
    /// @dev Fork block after the OHM/WETH 100 bps liquidity deployment with live 25-minute observations.
    uint256 internal constant FORK_BLOCK = 25488388;

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
    address public constant API3_ETH_USD = 0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473;
    address public constant API3_USDS_USD = 0x6C3C2A615Ea3c592487b3e06ecAF01D9a3181f47;
    address public constant UNISWAP_OHM_WETH_THIRTY_BPS =
        0x88051B0eea095007D3bEf21aB287Be961f3d8598;
    address public constant UNISWAP_OHM_WETH_ONE_HUNDRED_BPS =
        0x584eC2562b937C4AC0452184D8d83346382B5D3a;
    address public constant UNISWAP_OHM_SUSDS = 0x0858e2B0F9D75f7300B38D64482aC2C8DF06a755;
    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    uint256 internal constant OHM_USD_PRICE = 16.89e18;
    uint256 internal constant CDA_MINIMUM_BID = 100e18;
    uint256 internal constant CDA_INITIAL_TICK_SIZE_BASE = 2e18;
    uint24 internal constant CDA_INITIAL_TICK_STEP_MULTIPLIER = 10075;
    uint256 internal constant EM_TICK_SIZE = 150e9;

    // Price validation bounds (18 decimals) - from production config
    uint256 internal constant USDS_MIN_PRICE = 0.99e18;
    uint256 internal constant USDS_MAX_PRICE = 1.01e18;
    uint256 internal constant SUSDS_MIN_PRICE = 1.09e18;
    uint256 internal constant SUSDS_MAX_PRICE = 1.11e18;
    uint256 internal constant ETH_MIN_PRICE = 1700e18;
    uint256 internal constant ETH_MAX_PRICE = 1800e18;
    uint256 internal constant OHM_MIN_PRICE = 16.00e18;
    uint256 internal constant OHM_MAX_PRICE = 17.50e18;
    uint256 internal constant BPS_MAX = 10_000;
    uint256 internal constant WETH_DEVIATION_BPS = 500; // 5% deviation
    uint256 internal constant USDS_DEVIATION_BPS = 100; // 1% deviation
    uint256 internal constant OHM_DEVIATION_BPS = 200; // 2% deviation
    uint48 internal constant WETH_UPDATE_THRESHOLD = 2 * 86400; // 48 hours (differs from production to allow for warping)
    uint48 internal constant WETH_ETH_BTC_UPDATE_THRESHOLD = 2 * 86400; // 48 hours (differs from production to allow for warping)
    uint48 internal constant WETH_BTC_USD_UPDATE_THRESHOLD = 2 * 86400; // 48 hours (differs from production to allow for warping)
    uint48 internal constant USDS_UPDATE_THRESHOLD = 2 * 86400; // 48 hours (differs from production to allow for warping)
    uint48 internal constant OHM_UPDATE_THRESHOLD = 2 * 86400; // 48 hours (differs from production to allow for warping)
    // 25-minute TWAP fits within 128-cardinality pools at 12s/block (requires 125 observations).
    uint32 internal constant OHM_WETH_THIRTY_BPS_OBSERVATION_WINDOW = 1500;
    uint32 internal constant OHM_WETH_ONE_HUNDRED_BPS_OBSERVATION_WINDOW = 1500;
    uint32 internal constant OHM_SUSDS_OBSERVATION_WINDOW = 1500;
    uint32 internal constant _UNISWAP_V3_AVERAGE_BLOCK_TIME_SECONDS = 12;
    int24 internal constant OHM_WETH_ONE_HUNDRED_BPS_UPPER_RANGE_TICK = 161000;
    int24 internal constant OHM_SUSDS_LOWER_RANGE_TICK = 234360;
    uint128 internal constant OHM_BASE_AMOUNT = 1e9;
    uint256 internal constant OHM_SUSDS_TICK_WORD_SEARCH_LIMIT = 64;
    uint8 internal constant PRICE_LOG_DECIMALS = 6;
    uint8 internal constant WETH_DECIMALS = 18;
    uint8 internal constant SUSDS_DECIMALS = 18;

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
    SimplePriceFeedStrategy public strategy;
    AggregatorV2V3Interface internal _api3UsdsUsdFeed;

    // Permissioned addresses
    address public kernelExecutor;

    event MarketCreated(
        uint256 indexed id,
        address indexed payoutToken,
        address indexed quoteToken,
        uint48 vesting,
        uint256 initialPrice
    );

    error UnsupportedOhmQuoteToken(address quoteToken_);
    error InitializedTickRangeNotFound(address pool_, int24 tick_);

    struct OhmDownsideLogData {
        string scenario;
        uint256 targetOhmUsdPrice;
        uint256 wethUsdPrice;
        uint256 susdsUsdPrice;
        uint256 chainlinkEthUsdPrice;
        uint256 ohmWethThirtyBpsUsdPrice;
        uint256 ohmWethOneHundredBpsUsdPrice;
        uint256 ohmSusdsUsdPrice;
        uint256 chainlinkOhmUsdPrice;
        uint256 expectedPrice;
        uint256 resolvedPrice;
        int24 ohmWethOneHundredBpsLockedTick;
        int24 ohmSusdsLockedTick;
        int24 ohmSusdsLiquidityLowerTick;
        int24 ohmSusdsLiquidityUpperTick;
    }

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
        _labelMainnetAddresses();

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

        // Restore CD/EM sizing from ConvertibleDepositActivator. The live fork has since been
        // updated with higher values that prevent this test from reaching its target scenario.
        vm.startPrank(TIMELOCK);
        cdAuctioneer.setMinimumBid(CDA_MINIMUM_BID);
        cdAuctioneer.setTickSizeBase(CDA_INITIAL_TICK_SIZE_BASE);
        cdAuctioneer.setTickStep(CDA_INITIAL_TICK_STEP_MULTIPLIER);
        emissionManager.setTickSize(EM_TICK_SIZE);
        emissionManager.setBondMarketCapacityScalar(1e18);
        vm.stopPrank();

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
        UniswapV3Price uniswapV3Price = new UniswapV3Price(
            price,
            _UNISWAP_V3_AVERAGE_BLOCK_TIME_SECONDS,
            UNISWAP_V3_FACTORY
        );
        ERC4626Price erc4626Price = new ERC4626Price(price);
        strategy = new SimplePriceFeedStrategy(price);

        vm.label(address(price), "PRICE v1.2");
        vm.label(address(priceConfig), "PriceConfig v2");
        vm.label(address(chainlinkPrice), "ChainlinkPriceFeeds");
        vm.label(address(uniswapV3Price), "UniswapV3Price");
        vm.label(address(erc4626Price), "ERC4626Price");
        vm.label(address(strategy), "SimplePriceFeedStrategy");

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

    function _labelMainnetAddresses() internal {
        vm.label(OHM, "OHM");
        vm.label(WETH, "WETH");
        vm.label(USDS, "USDS");
        vm.label(SUSDS, "sUSDS");

        vm.label(KERNEL, "Kernel");
        vm.label(HEART, "Heart");
        vm.label(ROLES_ADMIN, "RolesAdmin");
        vm.label(EMISSION_MANAGER, "EmissionManager");
        vm.label(YIELD_REPO, "YieldRepurchaseFacility");
        vm.label(CONVERTIBLE_DEPOSIT_AUCTIONEER, "ConvertibleDepositAuctioneer");
        vm.label(TIMELOCK, "Timelock");
        vm.label(DAO_MS, "DAO MS");

        vm.label(CHAINLINK_ETH_USD, "Chainlink ETH/USD");
        vm.label(CHAINLINK_BTC_USD, "Chainlink BTC/USD");
        vm.label(CHAINLINK_ETH_BTC, "Chainlink ETH/BTC");
        vm.label(CHAINLINK_OHM_ETH, "Chainlink OHM/ETH");
        vm.label(CHAINLINK_USDS_USD, "Chainlink USDS/USD");
        vm.label(CHAINLINK_DAI_USD, "Chainlink DAI/USD");
        vm.label(REDSTONE_ETH_USD, "Redstone ETH/USD");
        vm.label(API3_ETH_USD, "API3 ETH/USD");
        vm.label(API3_USDS_USD, "API3 USDS/USD");

        vm.label(UNISWAP_OHM_WETH_THIRTY_BPS, "Uniswap V3 OHM/WETH 30 bps");
        vm.label(UNISWAP_OHM_WETH_ONE_HUNDRED_BPS, "Uniswap V3 OHM/WETH 100 bps");
        vm.label(UNISWAP_OHM_SUSDS, "Uniswap V3 OHM/sUSDS");
        vm.label(UNISWAP_V3_FACTORY, "Uniswap V3 Factory");
    }

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

        // Create feed components for the three Uniswap pools using getTokenTWAP, and the Chainlink OHM/ETH feed
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](4);

        // Feed 0: Uniswap OHM/WETH 30 bps
        UniswapV3Price.UniswapV3Params memory ohmWethThirtyBpsParams = UniswapV3Price
            .UniswapV3Params({
                pool: IUniswapV3Pool(UNISWAP_OHM_WETH_THIRTY_BPS),
                observationWindowSeconds: OHM_WETH_THIRTY_BPS_OBSERVATION_WINDOW
            });
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.UNIV3"),
            UniswapV3Price.getTokenTWAP.selector,
            abi.encode(ohmWethThirtyBpsParams)
        );

        // Feed 1: Uniswap OHM/WETH 100 bps
        UniswapV3Price.UniswapV3Params memory ohmWethOneHundredBpsParams = UniswapV3Price
            .UniswapV3Params({
                pool: IUniswapV3Pool(UNISWAP_OHM_WETH_ONE_HUNDRED_BPS),
                observationWindowSeconds: OHM_WETH_ONE_HUNDRED_BPS_OBSERVATION_WINDOW
            });
        feeds[1] = IPRICEv2.Component(
            toSubKeycode("PRICE.UNIV3"),
            UniswapV3Price.getTokenTWAP.selector,
            abi.encode(ohmWethOneHundredBpsParams)
        );

        // Feed 2: Uniswap OHM/sUSDS
        UniswapV3Price.UniswapV3Params memory ohmSusdsParams = UniswapV3Price.UniswapV3Params({
            pool: IUniswapV3Pool(UNISWAP_OHM_SUSDS),
            observationWindowSeconds: OHM_SUSDS_OBSERVATION_WINDOW
        });
        feeds[2] = IPRICEv2.Component(
            toSubKeycode("PRICE.UNIV3"),
            UniswapV3Price.getTokenTWAP.selector,
            abi.encode(ohmSusdsParams)
        );

        // Feed 3: Chainlink OHM/ETH x ETH/USD
        feeds[3] = IPRICEv2.Component(
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
        // Feeds: Chainlink ETH/USD, RedStone ETH/USD, API3 ETH/USD, Derived ETH/BTC×BTC/USD

        vm.startPrank(DAO_MS); // DAO_MS has price_admin permissions

        // Create strategy component: getAveragePriceExcludingDeviations (from production config)
        IPRICEv2.Component memory wethStrategy = IPRICEv2.Component({
            target: toSubKeycode("PRICE.SIMPLESTRATEGY"),
            selector: SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            params: abi.encode(
                ISimplePriceFeedStrategy.DeviationParams({
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    deviationBps: uint16(WETH_DEVIATION_BPS),
                    revertOnInsufficientCount: true // wethRevertOnInsufficientPriceFeeds from production
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

        // Feed 2: API3 ETH/USD (uses Chainlink interface)
        ChainlinkPriceFeeds.OneFeedParams memory api3EthUsdParams = ChainlinkPriceFeeds
            .OneFeedParams(AggregatorV2V3Interface(API3_ETH_USD), WETH_UPDATE_THRESHOLD);
        feeds[2] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(api3EthUsdParams)
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
        // Feeds: Chainlink USDS/USD, Chainlink DAI/USD, API3 USDS/USD

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

        // Feed 2: API3 USDS/USD (uses Chainlink interface).
        ChainlinkPriceFeeds.OneFeedParams memory api3UsdsUsdParams = ChainlinkPriceFeeds
            .OneFeedParams(AggregatorV2V3Interface(API3_USDS_USD), USDS_UPDATE_THRESHOLD);
        feeds[2] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(api3UsdsUsdParams)
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
        _logPrice("USDS/USD", usdsPrice);
        _assertPriceInRange(usdsPrice, USDS_MIN_PRICE, USDS_MAX_PRICE, "USDS");

        // Validate sUSDS price (uses ERC4626 submodule)
        uint256 susdsPrice = price.getPrice(SUSDS);
        _logPrice("sUSDS/USD", susdsPrice);
        _assertPriceInRange(susdsPrice, SUSDS_MIN_PRICE, SUSDS_MAX_PRICE, "sUSDS");

        // Validate WETH price (uses real feeds)
        uint256 wethPrice = price.getPrice(WETH);
        _logPrice("WETH/USD", wethPrice);
        _assertPriceInRange(wethPrice, ETH_MIN_PRICE, ETH_MAX_PRICE, "WETH");

        // Validate OHM price (uses Uniswap V3 TWAP feeds)
        uint256 ohmPrice = price.getPrice(OHM);
        _logPrice("OHM/USD", ohmPrice);
        _logCurrentOhmFeedPrices();
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

        IPRICEv2.Component[] memory feeds = abi.decode(ohmAsset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 4, "OHM should use four price feeds");
    }

    function test_priceValidation_ohmDeviationStrategyExcludesOutlier() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 202e17;
        prices[1] = 205e17;
        prices[2] = 204e17;
        prices[3] = 30e18;

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
        // prices[2] = 20.4e18 (18 decimals)
        // prices[3] = 30e18 (18 decimals)
        // Median benchmark is the midpoint of 20.4e18 and 20.5e18 for an even-length array.
        // With a 2% threshold, 30e18 deviates and is excluded.
        // Expected: (20.2e18 + 20.5e18 + 20.4e18) / 3 = 20.366666666666666666e18.
        _logPrice("Strategy input price 0", prices[0]);
        _logPrice("Strategy input price 1", prices[1]);
        _logPrice("Strategy input price 2", prices[2]);
        _logPrice("Strategy outlier price", prices[3]);
        _logPrice("Strategy resolved price", resolvedPrice);
        assertEq(resolvedPrice, 20366666666666666666, "OHM strategy should exclude the outlier");
    }

    function test_priceValidation_ohmSusdsLowerRangeStillContributesAt1630() public {
        OhmDownsideLogData memory logData;
        logData.scenario = "OHM at 16.30";
        logData.targetOhmUsdPrice = 16.30e18;
        logData.wethUsdPrice = price.getPrice(WETH);
        logData.susdsUsdPrice = price.getPrice(SUSDS);
        logData.chainlinkEthUsdPrice = _getChainlinkEthUsdPrice();
        logData.ohmSusdsLockedTick = OHM_SUSDS_LOWER_RANGE_TICK;

        IUniswapV3Pool ohmWethThirtyBpsPool = IUniswapV3Pool(UNISWAP_OHM_WETH_THIRTY_BPS);
        IUniswapV3Pool ohmWethOneHundredBpsPool = IUniswapV3Pool(UNISWAP_OHM_WETH_ONE_HUNDRED_BPS);
        IUniswapV3Pool ohmSusdsPool = IUniswapV3Pool(UNISWAP_OHM_SUSDS);
        (
            logData.ohmSusdsLiquidityLowerTick,
            logData.ohmSusdsLiquidityUpperTick
        ) = _getInitializedTickRange(ohmSusdsPool, logData.ohmSusdsLockedTick);
        int24 ohmWethThirtyBpsTick = _getTwapTickForOhmUsdPrice(
            ohmWethThirtyBpsPool,
            logData.targetOhmUsdPrice,
            logData.wethUsdPrice
        );
        int24 ohmWethOneHundredBpsTick = _getTwapTickForOhmUsdPrice(
            ohmWethOneHundredBpsPool,
            logData.targetOhmUsdPrice,
            logData.wethUsdPrice
        );

        _mockUniswapTwap(
            ohmWethThirtyBpsPool,
            OHM_WETH_THIRTY_BPS_OBSERVATION_WINDOW,
            ohmWethThirtyBpsTick
        );
        _mockUniswapTwap(
            ohmWethOneHundredBpsPool,
            OHM_WETH_ONE_HUNDRED_BPS_OBSERVATION_WINDOW,
            ohmWethOneHundredBpsTick
        );
        _mockUniswapTwap(ohmSusdsPool, OHM_SUSDS_OBSERVATION_WINDOW, logData.ohmSusdsLockedTick);
        _assertPoolTick(ohmSusdsPool, logData.ohmSusdsLockedTick);
        logData.chainlinkOhmUsdPrice = _mockChainlinkOhmEthPrice(logData.targetOhmUsdPrice);

        logData.ohmWethThirtyBpsUsdPrice = _getOhmUsdPriceAtTick(
            ohmWethThirtyBpsPool,
            ohmWethThirtyBpsTick,
            logData.wethUsdPrice
        );
        logData.ohmWethOneHundredBpsUsdPrice = _getOhmUsdPriceAtTick(
            ohmWethOneHundredBpsPool,
            ohmWethOneHundredBpsTick,
            logData.wethUsdPrice
        );
        logData.ohmSusdsUsdPrice = _getOhmUsdPriceAtTick(
            ohmSusdsPool,
            logData.ohmSusdsLockedTick,
            logData.susdsUsdPrice
        );

        // At $16.30, the OHM/sUSDS lower range price is still within the 2% deviation threshold,
        // so all four OHM feeds remain in the resolved average.
        logData.expectedPrice =
            (logData.ohmWethThirtyBpsUsdPrice +
                logData.ohmWethOneHundredBpsUsdPrice +
                logData.ohmSusdsUsdPrice +
                logData.chainlinkOhmUsdPrice) /
            4;
        logData.resolvedPrice = price.getPrice(OHM);
        _logOhmDownsideFeedPrices(logData);
        assertEq(
            logData.resolvedPrice,
            logData.expectedPrice,
            "OHM/sUSDS lower range should contribute"
        );

        vm.clearMockedCalls();
    }

    function test_priceValidation_ohmSusdsLowerRangeExcludedAfterFurtherDrop() public {
        OhmDownsideLogData memory logData;
        logData.scenario = "OHM below lower range";
        logData.targetOhmUsdPrice = 16e18;
        logData.wethUsdPrice = price.getPrice(WETH);
        logData.susdsUsdPrice = price.getPrice(SUSDS);
        logData.chainlinkEthUsdPrice = _getChainlinkEthUsdPrice();
        logData.ohmSusdsLockedTick = OHM_SUSDS_LOWER_RANGE_TICK;

        IUniswapV3Pool ohmWethThirtyBpsPool = IUniswapV3Pool(UNISWAP_OHM_WETH_THIRTY_BPS);
        IUniswapV3Pool ohmWethOneHundredBpsPool = IUniswapV3Pool(UNISWAP_OHM_WETH_ONE_HUNDRED_BPS);
        IUniswapV3Pool ohmSusdsPool = IUniswapV3Pool(UNISWAP_OHM_SUSDS);
        (
            logData.ohmSusdsLiquidityLowerTick,
            logData.ohmSusdsLiquidityUpperTick
        ) = _getInitializedTickRange(ohmSusdsPool, logData.ohmSusdsLockedTick);
        int24 ohmWethThirtyBpsTick = _getTwapTickForOhmUsdPrice(
            ohmWethThirtyBpsPool,
            logData.targetOhmUsdPrice,
            logData.wethUsdPrice
        );
        int24 ohmWethOneHundredBpsTick = _getTwapTickForOhmUsdPrice(
            ohmWethOneHundredBpsPool,
            logData.targetOhmUsdPrice,
            logData.wethUsdPrice
        );

        _mockUniswapTwap(
            ohmWethThirtyBpsPool,
            OHM_WETH_THIRTY_BPS_OBSERVATION_WINDOW,
            ohmWethThirtyBpsTick
        );
        _mockUniswapTwap(
            ohmWethOneHundredBpsPool,
            OHM_WETH_ONE_HUNDRED_BPS_OBSERVATION_WINDOW,
            ohmWethOneHundredBpsTick
        );
        _mockUniswapTwap(ohmSusdsPool, OHM_SUSDS_OBSERVATION_WINDOW, logData.ohmSusdsLockedTick);
        _assertPoolTick(ohmSusdsPool, logData.ohmSusdsLockedTick);
        logData.chainlinkOhmUsdPrice = _mockChainlinkOhmEthPrice(logData.targetOhmUsdPrice);

        logData.ohmWethThirtyBpsUsdPrice = _getOhmUsdPriceAtTick(
            ohmWethThirtyBpsPool,
            ohmWethThirtyBpsTick,
            logData.wethUsdPrice
        );
        logData.ohmWethOneHundredBpsUsdPrice = _getOhmUsdPriceAtTick(
            ohmWethOneHundredBpsPool,
            ohmWethOneHundredBpsTick,
            logData.wethUsdPrice
        );
        logData.ohmSusdsUsdPrice = _getOhmUsdPriceAtTick(
            ohmSusdsPool,
            logData.ohmSusdsLockedTick,
            logData.susdsUsdPrice
        );

        // The OHM/sUSDS lower range price is now more than 2% above the other feeds, so it is
        // excluded and PRICE resolves OHM from both OHM/WETH pools plus Chainlink OHM/ETH x ETH/USD.
        uint256 maxAllowedDeviation = logData.targetOhmUsdPrice.mulDiv(OHM_DEVIATION_BPS, BPS_MAX);
        assertGt(
            logData.ohmSusdsUsdPrice - logData.targetOhmUsdPrice,
            maxAllowedDeviation,
            "OHM/sUSDS lower range price should deviate"
        );

        logData.expectedPrice =
            (logData.ohmWethThirtyBpsUsdPrice +
                logData.ohmWethOneHundredBpsUsdPrice +
                logData.chainlinkOhmUsdPrice) /
            3;
        logData.resolvedPrice = price.getPrice(OHM);
        _logOhmDownsideFeedPrices(logData);
        assertEq(
            logData.resolvedPrice,
            logData.expectedPrice,
            "OHM/sUSDS lower range should be excluded"
        );

        vm.clearMockedCalls();
    }

    function test_priceValidation_ohmWethOneHundredBpsUpperRangeExcludedAfterRally() public {
        OhmDownsideLogData memory logData;
        logData.scenario = "OHM above OHM/WETH 100 bps upper range";
        logData.targetOhmUsdPrice = 17.50e18;
        logData.wethUsdPrice = price.getPrice(WETH);
        logData.susdsUsdPrice = price.getPrice(SUSDS);
        logData.chainlinkEthUsdPrice = _getChainlinkEthUsdPrice();
        logData.ohmWethOneHundredBpsLockedTick = OHM_WETH_ONE_HUNDRED_BPS_UPPER_RANGE_TICK;

        IUniswapV3Pool ohmWethThirtyBpsPool = IUniswapV3Pool(UNISWAP_OHM_WETH_THIRTY_BPS);
        IUniswapV3Pool ohmWethOneHundredBpsPool = IUniswapV3Pool(UNISWAP_OHM_WETH_ONE_HUNDRED_BPS);
        IUniswapV3Pool ohmSusdsPool = IUniswapV3Pool(UNISWAP_OHM_SUSDS);
        int24 ohmWethThirtyBpsTick = _getTwapTickForOhmUsdPrice(
            ohmWethThirtyBpsPool,
            logData.targetOhmUsdPrice,
            logData.wethUsdPrice
        );
        int24 ohmSusdsTick = _getTwapTickForOhmUsdPrice(
            ohmSusdsPool,
            logData.targetOhmUsdPrice,
            logData.susdsUsdPrice
        );

        _mockUniswapTwap(
            ohmWethThirtyBpsPool,
            OHM_WETH_THIRTY_BPS_OBSERVATION_WINDOW,
            ohmWethThirtyBpsTick
        );
        _mockUniswapTwap(
            ohmWethOneHundredBpsPool,
            OHM_WETH_ONE_HUNDRED_BPS_OBSERVATION_WINDOW,
            logData.ohmWethOneHundredBpsLockedTick
        );
        _mockUniswapTwap(ohmSusdsPool, OHM_SUSDS_OBSERVATION_WINDOW, ohmSusdsTick);
        _assertPoolTick(ohmWethOneHundredBpsPool, logData.ohmWethOneHundredBpsLockedTick);
        logData.chainlinkOhmUsdPrice = _mockChainlinkOhmEthPrice(logData.targetOhmUsdPrice);

        logData.ohmWethThirtyBpsUsdPrice = _getOhmUsdPriceAtTick(
            ohmWethThirtyBpsPool,
            ohmWethThirtyBpsTick,
            logData.wethUsdPrice
        );
        logData.ohmWethOneHundredBpsUsdPrice = _getOhmUsdPriceAtTick(
            ohmWethOneHundredBpsPool,
            logData.ohmWethOneHundredBpsLockedTick,
            logData.wethUsdPrice
        );
        logData.ohmSusdsUsdPrice = _getOhmUsdPriceAtTick(
            ohmSusdsPool,
            ohmSusdsTick,
            logData.susdsUsdPrice
        );

        uint256 maxAllowedDeviation = logData.targetOhmUsdPrice.mulDiv(OHM_DEVIATION_BPS, BPS_MAX);
        assertGt(
            logData.targetOhmUsdPrice - logData.ohmWethOneHundredBpsUsdPrice,
            maxAllowedDeviation,
            "OHM/WETH 100 bps upper range price should deviate"
        );

        logData.expectedPrice =
            (logData.ohmWethThirtyBpsUsdPrice +
                logData.ohmSusdsUsdPrice +
                logData.chainlinkOhmUsdPrice) /
            3;
        logData.resolvedPrice = price.getPrice(OHM);
        _logOhmDownsideFeedPrices(logData);
        assertEq(
            logData.resolvedPrice,
            logData.expectedPrice,
            "OHM/WETH 100 bps upper range should be excluded"
        );

        vm.clearMockedCalls();
    }

    function _logOhmDownsideFeedPrices(OhmDownsideLogData memory logData_) internal pure {
        console2.log(logData_.scenario);
        _logTick("OHM/WETH 100 bps locked tick", logData_.ohmWethOneHundredBpsLockedTick);
        _logTick("OHM/sUSDS locked tick", logData_.ohmSusdsLockedTick);
        _logTick("OHM/sUSDS liquidity lower tick", logData_.ohmSusdsLiquidityLowerTick);
        _logTick("OHM/sUSDS liquidity upper tick", logData_.ohmSusdsLiquidityUpperTick);
        _logPrice("target OHM/USD", logData_.targetOhmUsdPrice);
        _logPrice("PRICE WETH/USD", logData_.wethUsdPrice);
        _logPrice("PRICE sUSDS/USD", logData_.susdsUsdPrice);
        _logPrice("Chainlink ETH/USD", logData_.chainlinkEthUsdPrice);
        _logPrice("OHM/WETH 30 bps OHM/USD", logData_.ohmWethThirtyBpsUsdPrice);
        _logPrice("OHM/WETH 100 bps OHM/USD", logData_.ohmWethOneHundredBpsUsdPrice);
        _logPrice("OHM/sUSDS OHM/USD", logData_.ohmSusdsUsdPrice);
        _logPrice("Chainlink OHM/ETH x ETH/USD", logData_.chainlinkOhmUsdPrice);
        _logPrice("expected PRICE OHM/USD", logData_.expectedPrice);
        _logPrice("resolved PRICE OHM/USD", logData_.resolvedPrice);
    }

    function _logCurrentOhmFeedPrices() internal view {
        uint256 wethUsdPrice = price.getPrice(WETH);
        uint256 susdsUsdPrice = price.getPrice(SUSDS);
        int24 ohmWethThirtyBpsTick = _consultTwapTick(
            IUniswapV3Pool(UNISWAP_OHM_WETH_THIRTY_BPS),
            OHM_WETH_THIRTY_BPS_OBSERVATION_WINDOW
        );
        int24 ohmWethOneHundredBpsTick = _consultTwapTick(
            IUniswapV3Pool(UNISWAP_OHM_WETH_ONE_HUNDRED_BPS),
            OHM_WETH_ONE_HUNDRED_BPS_OBSERVATION_WINDOW
        );
        int24 ohmSusdsTick = _consultTwapTick(
            IUniswapV3Pool(UNISWAP_OHM_SUSDS),
            OHM_SUSDS_OBSERVATION_WINDOW
        );

        _logTick("OHM/WETH 30 bps TWAP tick", ohmWethThirtyBpsTick);
        _logPrice(
            "OHM/WETH 30 bps OHM/USD",
            _getOhmUsdPriceAtTick(
                IUniswapV3Pool(UNISWAP_OHM_WETH_THIRTY_BPS),
                ohmWethThirtyBpsTick,
                wethUsdPrice
            )
        );
        _logTick("OHM/WETH 100 bps TWAP tick", ohmWethOneHundredBpsTick);
        _logPrice(
            "OHM/WETH 100 bps OHM/USD",
            _getOhmUsdPriceAtTick(
                IUniswapV3Pool(UNISWAP_OHM_WETH_ONE_HUNDRED_BPS),
                ohmWethOneHundredBpsTick,
                wethUsdPrice
            )
        );
        _logTick("OHM/sUSDS TWAP tick", ohmSusdsTick);
        _logPrice(
            "OHM/sUSDS OHM/USD",
            _getOhmUsdPriceAtTick(IUniswapV3Pool(UNISWAP_OHM_SUSDS), ohmSusdsTick, susdsUsdPrice)
        );
        _logPrice("Chainlink OHM/ETH x ETH/USD", _getChainlinkOhmUsdPrice());
    }

    function _logPrice(string memory label_, uint256 price_) internal pure {
        console2.log(label_, _formatPrice(price_, PRICE_LOG_DECIMALS));
    }

    function _logTick(string memory label_, int24 tick_) internal pure {
        console2.log(label_, _formatTick(tick_));
    }

    function _formatPrice(
        uint256 price_,
        uint8 decimalPlaces_
    ) internal pure returns (string memory) {
        uint256 scale = 1e18;
        uint256 whole = price_ / scale;
        uint256 fraction = (price_ % scale) / (10 ** (18 - decimalPlaces_));

        return
            string.concat(Strings.toString(whole), ".", _formatFraction(fraction, decimalPlaces_));
    }

    function _formatFraction(
        uint256 fraction_,
        uint8 decimalPlaces_
    ) internal pure returns (string memory) {
        bytes memory buffer = new bytes(decimalPlaces_);
        uint256 value = fraction_;

        for (uint256 i = decimalPlaces_; i > 0; i--) {
            buffer[i - 1] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    function _formatTick(int24 tick_) internal pure returns (string memory) {
        int256 tick = int256(tick_);
        uint256 absTick = tick < 0 ? uint256(-tick) : uint256(tick);

        return tick < 0 ? string.concat("-", Strings.toString(absTick)) : Strings.toString(absTick);
    }

    function _assertPoolTick(IUniswapV3Pool pool_, int24 expectedTick_) internal view {
        (, int24 tick, , , , , ) = pool_.slot0();
        assertEq(tick, expectedTick_, "Pool tick should be locked");
    }

    function _getInitializedTickRange(
        IUniswapV3Pool pool_,
        int24 tick_
    ) internal view returns (int24 lowerTick_, int24 upperTick_) {
        int24 tickSpacing = pool_.tickSpacing();
        int24 compressedTick = tick_ / tickSpacing;
        int24 lowerCompressedTick = _getPreviousInitializedCompressedTick(pool_, compressedTick);
        int24 upperCompressedTick = _getNextInitializedCompressedTick(pool_, compressedTick + 1);

        lowerTick_ = lowerCompressedTick * tickSpacing;
        upperTick_ = upperCompressedTick * tickSpacing;
    }

    function _getPreviousInitializedCompressedTick(
        IUniswapV3Pool pool_,
        int24 compressedTick_
    ) internal view returns (int24) {
        int16 wordPosition;
        uint8 bitPosition;
        (wordPosition, bitPosition) = _getTickBitmapPosition(compressedTick_);

        for (uint256 i; i <= OHM_SUSDS_TICK_WORD_SEARCH_LIMIT; i++) {
            uint256 mask = bitPosition == 255
                ? type(uint256).max
                : (uint256(1) << (uint256(bitPosition) + 1)) - 1;
            uint256 maskedBitmap = pool_.tickBitmap(wordPosition) & mask;

            if (maskedBitmap != 0) {
                for (uint256 bit = uint256(bitPosition) + 1; bit > 0; bit--) {
                    uint256 candidateBit = bit - 1;
                    if (maskedBitmap & (uint256(1) << candidateBit) != 0)
                        return _getCompressedTickFromBitmapPosition(wordPosition, candidateBit);
                }
            }

            wordPosition--;
            bitPosition = 255;
        }

        revert InitializedTickRangeNotFound(address(pool_), compressedTick_);
    }

    function _getNextInitializedCompressedTick(
        IUniswapV3Pool pool_,
        int24 compressedTick_
    ) internal view returns (int24) {
        int16 wordPosition;
        uint8 bitPosition;
        (wordPosition, bitPosition) = _getTickBitmapPosition(compressedTick_);

        for (uint256 i; i <= OHM_SUSDS_TICK_WORD_SEARCH_LIMIT; i++) {
            uint256 mask = type(uint256).max << uint256(bitPosition);
            uint256 maskedBitmap = pool_.tickBitmap(wordPosition) & mask;

            if (maskedBitmap != 0) {
                for (uint256 bit = uint256(bitPosition); bit < 256; bit++) {
                    if (maskedBitmap & (uint256(1) << bit) != 0)
                        return _getCompressedTickFromBitmapPosition(wordPosition, bit);
                }
            }

            wordPosition++;
            bitPosition = 0;
        }

        revert InitializedTickRangeNotFound(address(pool_), compressedTick_);
    }

    function _getTickBitmapPosition(
        int24 compressedTick_
    ) internal pure returns (int16 wordPosition_, uint8 bitPosition_) {
        /// forge-lint: disable-next-line(unsafe-typecast)
        wordPosition_ = int16(compressedTick_ >> 8);
        /// forge-lint: disable-next-line(unsafe-typecast)
        bitPosition_ = uint8(uint24(compressedTick_ % 256));
    }

    function _getCompressedTickFromBitmapPosition(
        int16 wordPosition_,
        uint256 bitPosition_
    ) internal pure returns (int24) {
        /// forge-lint: disable-next-line(unsafe-typecast)
        return int24(int256(wordPosition_) * 256 + int256(bitPosition_));
    }

    function _getTwapTickForOhmUsdPrice(
        IUniswapV3Pool pool_,
        uint256 targetOhmUsdPrice_,
        uint256 quoteUsdPrice_
    ) internal view returns (int24 tick_) {
        assertEq(pool_.token0(), OHM, "OHM should be token0");

        int24 low = 100000;
        int24 high = 260000;

        while (low < high) {
            /// forge-lint: disable-next-line(unsafe-typecast)
            int24 mid = int24((int256(low) + int256(high) + 1) / 2);
            uint256 priceAtMid = _getOhmUsdPriceAtTick(pool_, mid, quoteUsdPrice_);

            if (priceAtMid <= targetOhmUsdPrice_) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        tick_ = low;
    }

    function _consultTwapTick(
        IUniswapV3Pool pool_,
        uint32 observationWindow_
    ) internal view returns (int24 tick_) {
        (tick_, ) = OracleLibrary.consult(address(pool_), observationWindow_);
    }

    function _getOhmUsdPriceAtTick(
        IUniswapV3Pool pool_,
        int24 tick_,
        uint256 quoteUsdPrice_
    ) internal view returns (uint256) {
        address quoteToken = pool_.token0() == OHM ? pool_.token1() : pool_.token0();
        uint8 quoteTokenDecimals;

        if (quoteToken == WETH) {
            quoteTokenDecimals = WETH_DECIMALS;
        } else if (quoteToken == SUSDS) {
            quoteTokenDecimals = SUSDS_DECIMALS;
        } else {
            revert UnsupportedOhmQuoteToken(quoteToken);
        }

        uint256 baseInQuotePrice = OracleLibrary.getQuoteAtTick(
            tick_,
            OHM_BASE_AMOUNT,
            OHM,
            quoteToken
        );

        return quoteUsdPrice_.mulDiv(baseInQuotePrice, 10 ** quoteTokenDecimals);
    }

    function _mockUniswapTwap(
        IUniswapV3Pool pool_,
        uint32 observationWindow_,
        int24 tick_
    ) internal {
        (
            ,
            ,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        ) = pool_.slot0();

        vm.mockCall(
            address(pool_),
            abi.encodeWithSelector(bytes4(keccak256("slot0()"))),
            abi.encode(
                TickMath.getSqrtRatioAtTick(tick_),
                tick_,
                observationIndex,
                observationCardinality,
                observationCardinalityNext,
                feeProtocol,
                unlocked
            )
        );

        uint32[] memory observationWindow = new uint32[](2);
        observationWindow[0] = observationWindow_;
        observationWindow[1] = 0;

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = 0;
        /// forge-lint: disable-next-line(unsafe-typecast)
        tickCumulatives[1] = int56(tick_) * int56(uint56(observationWindow_));

        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);

        vm.mockCall(
            address(pool_),
            abi.encodeWithSelector(bytes4(keccak256("observe(uint32[])")), observationWindow),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
    }

    function _mockChainlinkOhmEthPrice(
        uint256 targetOhmUsdPrice_
    ) internal returns (uint256 mockedOhmUsdPrice_) {
        AggregatorV2V3Interface ohmEthFeed = AggregatorV2V3Interface(CHAINLINK_OHM_ETH);
        uint256 ethUsdPrice = _getChainlinkEthUsdPrice();
        uint8 ohmEthDecimals = ohmEthFeed.decimals();
        uint256 ohmEthAnswer = targetOhmUsdPrice_.mulDiv(10 ** ohmEthDecimals, ethUsdPrice);

        vm.mockCall(
            CHAINLINK_OHM_ETH,
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(
                uint80(1),
                /// forge-lint: disable-next-line(unsafe-typecast)
                int256(ohmEthAnswer),
                block.timestamp,
                block.timestamp,
                uint80(1)
            )
        );

        uint256 ohmEthPrice = ohmEthAnswer.mulDiv(1e18, 10 ** ohmEthDecimals);
        mockedOhmUsdPrice_ = ohmEthPrice.mulDiv(ethUsdPrice, 1e18);
    }

    function _getChainlinkOhmUsdPrice() internal view returns (uint256) {
        AggregatorV2V3Interface ohmEthFeed = AggregatorV2V3Interface(CHAINLINK_OHM_ETH);
        (, int256 ohmEthAnswer, , , ) = ohmEthFeed.latestRoundData();
        assertGt(ohmEthAnswer, 0, "Chainlink OHM/ETH price should be positive");

        uint8 ohmEthDecimals = ohmEthFeed.decimals();
        /// forge-lint: disable-next-line(unsafe-typecast)
        uint256 ohmEthPrice = uint256(ohmEthAnswer).mulDiv(1e18, 10 ** ohmEthDecimals);

        return ohmEthPrice.mulDiv(_getChainlinkEthUsdPrice(), 1e18);
    }

    function _getChainlinkEthUsdPrice() internal view returns (uint256) {
        AggregatorV2V3Interface ethUsdFeed = AggregatorV2V3Interface(CHAINLINK_ETH_USD);
        (, int256 ethUsdAnswer, , , ) = ethUsdFeed.latestRoundData();
        assertGt(ethUsdAnswer, 0, "Chainlink ETH/USD price should be positive");

        uint8 ethUsdDecimals = ethUsdFeed.decimals();
        /// forge-lint: disable-next-line(unsafe-typecast)
        return uint256(ethUsdAnswer).mulDiv(1e18, 10 ** ethUsdDecimals);
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
        vm.clearMockedCalls();
        _mockOhmPrice(price_);
        _;
    }

    function _mockOhmPrice(uint256 price_) internal {
        // Mock the getPrice function to return a specific OHM price. This allows tests to
        // exercise premium scenarios without manipulating pool state.
        bytes4 getPriceWithVariantSelector = bytes4(keccak256("getPrice(address,uint8)"));
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
        vm.mockCall(
            address(price),
            abi.encodeWithSelector(getPriceWithVariantSelector, OHM, IPRICEv2.Variant.LAST),
            abi.encode(price_, SafeCast.encodeUInt48(block.timestamp))
        );
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
        observationWindow[0] = OHM_WETH_THIRTY_BPS_OBSERVATION_WINDOW;
        observationWindow[1] = 0;

        vm.mockCallRevert(
            UNISWAP_OHM_WETH_THIRTY_BPS,
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
        beat // Epoch 0
        givenOhmPrice(17e18) // Below 50% premium
        warpToNextHeartbeat
        beat // Epoch 1
        warpToNextHeartbeat
        beat // Epoch 2
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
        beat // Epoch 0
        warpToNextHeartbeat
        beat // Epoch 1
        warpToNextHeartbeat
        beat // Epoch 2
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
        beat // Epoch 0, auction results next index is 1
        givenOhmPrice(24e18)
        warpToNextHeartbeat
        beat // Epoch 1
        warpToNextHeartbeat
        beat // Epoch 2
        givenOhmPrice(24e18)
        warpToNextHeartbeat
    {
        uint256 expectedInitialPrice = 24e36; // Bond market scaling
        uint256 activeMarketIdBefore = emissionManager.activeMarketId();

        // Expect event. The market ID depends on live Bond Protocol state at the fork block, so
        // ignore topic 1 and assert the stable payout/quote/price fields.
        vm.expectEmit(false, true, true, true);
        emit MarketCreated(
            0,
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
        assertGt(
            emissionManager.activeMarketId(),
            activeMarketIdBefore,
            "Active market ID should increase"
        );
    }

    // when the heartbeat launches a YRF market
    //  [X] the YRF market is created with the price from the price feed

    function test_yieldRepurchaseFacility()
        public
        givenOhmPrice(24e18) // Above 50% premium
        warpToNextHeartbeat
    {
        // At FORK_BLOCK, YRF starts at epoch 5. The next heartbeat reaches epoch 6 and creates
        // the market, so pre-beating here would emit MarketCreated before the expectation below.
        // Calculate the expected initial price
        // From YRF._createMarket()
        // 10 ** (18 * 2) / ((24e18 * 97) / 100)
        // = 42955326460481099
        // Adjusted by 1e17 for bond market scaling
        uint256 expectedInitialPrice = 42955326460481099 * 1e17;

        // Expect event. The market ID depends on live Bond Protocol state at the fork block, so
        // ignore topic 1 and assert the stable payout/quote/price fields.
        vm.expectEmit(false, true, true, true);
        emit MarketCreated(
            0,
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
