// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// Interfaces
import {IPRICEv1} from "src/modules/PRICE/IPRICE.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";
import {SubKeycode, toSubKeycode} from "src/Submodules.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";

// Bophades
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";

// PRICE contracts
import {PRICEv1} from "src/modules/PRICE/PRICE.v1.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";

// PRICE Submodules
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ERC4626Price} from "src/modules/PRICE/submodules/feeds/ERC4626Price.sol";
import {PythPriceFeeds} from "src/modules/PRICE/submodules/feeds/PythPriceFeeds.sol";
import {UniswapV3Price} from "src/modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Configures PRICE v1.2 module assets via PriceConfig v2 policy
/// @dev    Deployment of PRICE module and PriceConfig happens separately
///         This script only handles configuration
contract ConfigurePriceV1_2 is BatchScriptV2 {
    using SafeCast for uint256;

    // ========== STATE ========== //

    /// @notice Addresses of assets and Pyth contract (loaded from args or env)
    address internal _usds;
    address internal _susds;
    address internal _weth;
    address internal _ohm;
    address internal _pyth;

    /// @notice Configuration parameters (loaded from args)
    uint32 internal _uniswapOhmWethObservationWindow;
    uint32 internal _uniswapOhmSusdsObservationWindow;
    uint256 internal _preUpgradeOhmTargetPrice;

    // ========== CONFIGURATION FUNCTIONS ========== //

    /// @notice Configure PRICE v1.2 module with all assets
    /// @param useDaoMS_ Whether to use the DAO multisig
    /// @param signOnly_ Whether to only sign the batch
    /// @param argsFilePath_ Path to the args file containing price feed addresses
    function configurePriceV1_2(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFilePath_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFilePath_, ledgerDerivationPath, signature_) {
        console2.log("=== Configuring PRICE v1.2 Module ===");

        // Load dependencies from env
        address kernel = _envAddressNotZero("olympus.Kernel");
        address priceModule = _envAddressNotZero("olympus.modules.OlympusPriceV1");
        address priceConfig = _envAddressNotZero("olympus.policies.OlympusPriceConfigV2");

        // Load asset addresses from env
        _usds = _envAddressNotZero("external.tokens.USDS");
        _susds = _envAddressNotZero("external.tokens.sUSDS");
        _weth = _envAddressNotZero("external.tokens.WETH");
        _ohm = _envAddressNotZero("olympus.legacy.OHM");

        // Load Pyth contract address from args file (shared by all Pyth feeds)
        _pyth = _readBatchArgAddress("configurePriceV1_2", "pyth");

        vm.label(kernel, "Kernel");
        vm.label(priceModule, "PRICE v1.2");
        vm.label(priceConfig, "PriceConfig v2");
        vm.label(_usds, "USDS");
        vm.label(_susds, "sUSDS");
        vm.label(_weth, "WETH");
        vm.label(_ohm, "OHM");
        vm.label(_pyth, "Pyth");

        // Load configuration parameters from args file
        _uniswapOhmWethObservationWindow = _readBatchArgUint256(
            "configurePriceV1_2",
            "uniswapOhmWethObservationWindow"
        ).encodeUInt32();

        _uniswapOhmSusdsObservationWindow = _readBatchArgUint256(
            "configurePriceV1_2",
            "uniswapOhmSusdsObservationWindow"
        ).encodeUInt32();

        console2.log("Kernel:", kernel);
        console2.log("PriceConfig:", priceConfig);
        console2.log("USDS:", _usds);
        console2.log("sUSDS:", _susds);
        console2.log("wETH:", _weth);
        console2.log("OHM:", _ohm);

        // Validate the PRICE version
        {
            (uint8 major, uint8 minor) = IVersioned(priceModule).VERSION();

            // Needs to be at least v1.2
            // If major is 1, minor must be at least 2
            if (major < 1) revert("PRICE module version is unsupported");
            if (major == 1 && minor < 2) revert("PRICE module version is unsupported");
        }

        PRICEv1 oldPrice = PRICEv1(address(Kernel(kernel).getModuleForKeycode(toKeycode("PRICE"))));
        vm.label(address(oldPrice), "PRICE v1 current module");
        _preUpgradeOhmTargetPrice = oldPrice.getTargetPrice();
        if (IPRICEv1(priceModule).observationFrequency() != oldPrice.observationFrequency()) {
            revert("PRICE observation frequency mismatch");
        }

        // Upgrade PRICE v1.2 module in the kernel
        console2.log("Upgrading PRICE module");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.UpgradeModule,
                priceModule
            )
        );

        // Activate PriceConfig V2 policy in the kernel
        console2.log("Activating PriceConfig V2 policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                priceConfig
            )
        );

        // Install submodules first
        _installSubmodules(priceConfig);

        // Then configure each asset
        _configureUSDS(priceConfig);
        _configureSusds(priceConfig);
        _configureWeth(priceConfig);
        _configureOhm(priceConfig, oldPrice);

        console2.log("PRICE v1.2 configuration batch prepared");
        proposeBatch();
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Install PRICE submodules
    /// @param priceConfig_ Address of the PriceConfig v2 policy
    function _installSubmodules(address priceConfig_) internal {
        console2.log("\n=== Installing PRICE Submodules ===");

        // Load submodule addresses from env
        address chainlinkFeeds = _envAddressNotZero("olympus.submodules.PRICE.ChainlinkPriceFeeds");
        address pythFeeds = _envAddressNotZero("olympus.submodules.PRICE.PythPriceFeeds");
        address uniswapV3Price = _envAddressNotZero("olympus.submodules.PRICE.UniswapV3Price");
        address erc4626Price = _envAddressNotZero("olympus.submodules.PRICE.ERC4626Price");
        address simpleStrategy = _envAddressNotZero(
            "olympus.submodules.PRICE.SimplePriceFeedStrategy"
        );

        vm.label(chainlinkFeeds, "PRICE.ChainlinkPriceFeeds");
        vm.label(pythFeeds, "PRICE.PythPriceFeeds");
        vm.label(uniswapV3Price, "PRICE.UniswapV3Price");
        vm.label(erc4626Price, "PRICE.ERC4626Price");
        vm.label(simpleStrategy, "PRICE.SimplePriceFeedStrategy");

        // Install ChainlinkPriceFeeds
        console2.log("1. Installing ChainlinkPriceFeeds submodule");
        addToBatch(
            priceConfig_,
            abi.encodeWithSelector(PriceConfigv2.installSubmodule.selector, chainlinkFeeds)
        );

        // Install PythPriceFeeds
        console2.log("2. Installing PythPriceFeeds submodule");
        addToBatch(
            priceConfig_,
            abi.encodeWithSelector(PriceConfigv2.installSubmodule.selector, pythFeeds)
        );

        // Install UniswapV3Price
        console2.log("3. Installing UniswapV3Price submodule");
        addToBatch(
            priceConfig_,
            abi.encodeWithSelector(PriceConfigv2.installSubmodule.selector, uniswapV3Price)
        );

        // Install ERC4626Price
        console2.log("4. Installing ERC4626Price submodule");
        addToBatch(
            priceConfig_,
            abi.encodeWithSelector(PriceConfigv2.installSubmodule.selector, erc4626Price)
        );

        // Install SimplePriceFeedStrategy
        console2.log("5. Installing SimplePriceFeedStrategy submodule");
        addToBatch(
            priceConfig_,
            abi.encodeWithSelector(PriceConfigv2.installSubmodule.selector, simpleStrategy)
        );

        console2.log("All submodules installation batched");
    }

    /// @notice Configure USDS asset
    /// @param priceConfig_ Address of the PriceConfig v2 policy
    function _configureUSDS(address priceConfig_) internal {
        console2.log("\n=== Configuring USDS Asset ===");

        // Read price feed addresses from args file
        address chainlinkUsdsUsd = _readBatchArgAddress("configurePriceV1_2", "chainlinkUsdsUsd");
        address chainlinkDaiUsd = _readBatchArgAddress("configurePriceV1_2", "chainlinkDaiUsd");

        // Read deviation parameters from args file
        uint16 usdsPriceFeedDeviationBps = SafeCast.encodeUInt16(
            _readBatchArgUint256("configurePriceV1_2", "usdsPriceFeedDeviationBps")
        );
        bool usdsRevertOnInsufficientPriceFeeds = _readBatchArgBool(
            "configurePriceV1_2",
            "usdsRevertOnInsufficientPriceFeeds"
        );

        // Read update thresholds from args file
        uint48 chainlinkUsdsUsdUpdateThreshold = SafeCast.encodeUInt48(
            _readBatchArgUint256("configurePriceV1_2", "chainlinkUsdsUsdUpdateThreshold")
        );
        uint48 chainlinkDaiUsdUpdateThreshold = SafeCast.encodeUInt48(
            _readBatchArgUint256("configurePriceV1_2", "chainlinkDaiUsdUpdateThreshold")
        );
        uint48 pythUsdsUsdUpdateThreshold = SafeCast.encodeUInt48(
            _readBatchArgUint256("configurePriceV1_2", "pythUsdsUsdUpdateThreshold")
        );

        // Read Pyth feed parameters from args file
        bytes32 pythUsdsUsdId = _readBatchArgBytes32("configurePriceV1_2", "pythUsdsUsdFeedId");
        uint256 pythUsdsUsdMaxConfidence = _readBatchArgUint256(
            "configurePriceV1_2",
            "pythUsdsUsdMaxConfidence"
        );

        vm.label(chainlinkUsdsUsd, "Chainlink USDS/USD");
        vm.label(chainlinkDaiUsd, "Chainlink DAI/USD");

        console2.log("Chainlink USDS/USD:", chainlinkUsdsUsd);
        console2.log("Chainlink DAI/USD:", chainlinkDaiUsd);
        console2.log("Pyth contract:", _pyth);
        console2.log("Pyth USDS/USD ID:");
        console2.logBytes32(pythUsdsUsdId);

        // Create strategy component: getAveragePriceExcludingDeviations
        IPRICEv2.Component memory strategy = _encodeDeviationStrategy(
            SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            usdsPriceFeedDeviationBps,
            usdsRevertOnInsufficientPriceFeeds
        );

        // Create feed components using getOneFeedPrice
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](3);
        feeds[0] = _encodeFeed(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(chainlinkUsdsUsd),
                    updateThreshold: chainlinkUsdsUsdUpdateThreshold
                })
            )
        );
        feeds[1] = _encodeFeed(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(chainlinkDaiUsd),
                    updateThreshold: chainlinkDaiUsdUpdateThreshold
                })
            )
        );
        feeds[2] = _encodeFeed(
            toSubKeycode("PRICE.PYTH"),
            PythPriceFeeds.getOneFeedPrice.selector,
            abi.encode(
                PythPriceFeeds.OneFeedParams({
                    pyth: _pyth,
                    priceFeedId: pythUsdsUsdId,
                    updateThreshold: pythUsdsUsdUpdateThreshold,
                    maxConfidence: pythUsdsUsdMaxConfidence
                })
            )
        );

        // Add asset via PriceConfig
        _addAsset(
            priceConfig_,
            _usds,
            strategy,
            feeds,
            _readFeedExpectations(feeds.length, "usds")
        );

        console2.log("USDS asset configured");
    }

    /// @notice Configure sUSDS asset (uses ERC4626 submodule)
    /// @param priceConfig_ Address of the PriceConfig v2 policy
    function _configureSusds(address priceConfig_) internal {
        console2.log("\n=== Configuring sUSDS Asset ===");

        // Empty strategy (single feed, no aggregation needed)
        IPRICEv2.Component memory strategy = IPRICEv2.Component({
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

        // Add asset via PriceConfig
        _addAsset(
            priceConfig_,
            _susds,
            strategy,
            feeds,
            _readFeedExpectations(feeds.length, "susds")
        );

        console2.log("sUSDS asset configured");
    }

    /// @notice Configure wETH asset
    /// @param priceConfig_ Address of the PriceConfig v2 policy
    function _configureWeth(address priceConfig_) internal {
        console2.log("\n=== Configuring wETH Asset ===");

        // Read price feed addresses from args file
        address chainlinkEthUsd = _readBatchArgAddress("configurePriceV1_2", "chainlinkEthUsd");
        address redstoneEthUsd = _readBatchArgAddress("configurePriceV1_2", "redstoneEthUsd");
        bytes32 pythEthUsdId = _readBatchArgBytes32("configurePriceV1_2", "pythEthUsdFeedId");
        address chainlinkBtcUsd = _readBatchArgAddress("configurePriceV1_2", "chainlinkBtcUsd");
        address chainlinkEthBtc = _readBatchArgAddress("configurePriceV1_2", "chainlinkEthBtc");

        // Read max confidence for Pyth ETH feed from args file
        uint256 pythEthUsdMaxConfidence = _readBatchArgUint256(
            "configurePriceV1_2",
            "pythEthUsdMaxConfidence"
        );

        // Read deviation parameters from args file
        uint16 wethPriceFeedDeviationBps = SafeCast.encodeUInt16(
            _readBatchArgUint256("configurePriceV1_2", "wethPriceFeedDeviationBps")
        );
        bool wethRevertOnInsufficientPriceFeeds = _readBatchArgBool(
            "configurePriceV1_2",
            "wethRevertOnInsufficientPriceFeeds"
        );

        vm.label(chainlinkEthUsd, "Chainlink ETH/USD");
        vm.label(redstoneEthUsd, "RedStone ETH/USD");
        vm.label(chainlinkBtcUsd, "Chainlink BTC/USD");
        vm.label(chainlinkEthBtc, "Chainlink ETH/BTC");

        console2.log("Chainlink ETH/USD:", chainlinkEthUsd);
        console2.log("RedStone ETH/USD:", redstoneEthUsd);
        console2.log("Pyth contract:", _pyth);
        console2.log("Pyth ETH/USD ID:");
        console2.logBytes32(pythEthUsdId);
        console2.log("Chainlink BTC/USD:", chainlinkBtcUsd);
        console2.log("Chainlink ETH/BTC:", chainlinkEthBtc);
        console2.log(
            "Chainlink ETH/USD update threshold:",
            _readBatchArgUint256("configurePriceV1_2", "chainlinkEthUsdUpdateThreshold")
        );
        console2.log(
            "RedStone ETH/USD update threshold:",
            _readBatchArgUint256("configurePriceV1_2", "redstoneEthUsdUpdateThreshold")
        );
        console2.log(
            "Pyth ETH/USD update threshold:",
            _readBatchArgUint256("configurePriceV1_2", "pythEthUsdUpdateThreshold")
        );

        // Create strategy component: getAveragePriceExcludingDeviations
        // When exactly two WETH feeds survive, the strategy benchmarks each price against
        // their average. A 500 bps deviation allows boundary prices of $1,900 and $2,100
        // around a $2,000 average, i.e. a 10% spread between the two surviving feeds.
        IPRICEv2.Component memory strategy = _encodeDeviationStrategy(
            SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            wethPriceFeedDeviationBps,
            wethRevertOnInsufficientPriceFeeds
        );

        // Create feed components using getOneFeedPrice for first 3 feeds
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](4);
        feeds[0] = _encodeFeed(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(chainlinkEthUsd),
                    updateThreshold: SafeCast.encodeUInt48(
                        _readBatchArgUint256("configurePriceV1_2", "chainlinkEthUsdUpdateThreshold")
                    )
                })
            )
        );
        feeds[1] = _encodeFeed(
            toSubKeycode("PRICE.CHAINLINK"), // RedStone uses Chainlink interface
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(redstoneEthUsd),
                    updateThreshold: SafeCast.encodeUInt48(
                        _readBatchArgUint256("configurePriceV1_2", "redstoneEthUsdUpdateThreshold")
                    )
                })
            )
        );
        feeds[2] = _encodeFeed(
            toSubKeycode("PRICE.PYTH"),
            PythPriceFeeds.getOneFeedPrice.selector,
            abi.encode(
                PythPriceFeeds.OneFeedParams({
                    pyth: _pyth,
                    priceFeedId: pythEthUsdId,
                    updateThreshold: SafeCast.encodeUInt48(
                        _readBatchArgUint256("configurePriceV1_2", "pythEthUsdUpdateThreshold")
                    ),
                    maxConfidence: pythEthUsdMaxConfidence
                })
            )
        );
        // 4th feed: Derived ETH-USD from ETH-BTC × BTC-USD. ETH/BTC has a 24-hour
        // heartbeat, while BTC/USD uses the standard 1-hour Chainlink feed threshold.
        feeds[3] = _encodeFeed(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams({
                    firstFeed: AggregatorV2V3Interface(chainlinkEthBtc),
                    firstUpdateThreshold: SafeCast.encodeUInt48(
                        _readBatchArgUint256("configurePriceV1_2", "chainlinkEthBtcUpdateThreshold")
                    ),
                    secondFeed: AggregatorV2V3Interface(chainlinkBtcUsd),
                    secondUpdateThreshold: SafeCast.encodeUInt48(
                        _readBatchArgUint256("configurePriceV1_2", "chainlinkBtcUsdUpdateThreshold")
                    )
                })
            )
        );

        // Add asset via PriceConfig
        _addAsset(
            priceConfig_,
            _weth,
            strategy,
            feeds,
            _readFeedExpectations(feeds.length, "weth")
        );

        console2.log("wETH asset configured");
    }

    /// @notice Configure OHM asset
    /// @param priceConfig_ Address of the PriceConfig v2 policy
    function _configureOhm(address priceConfig_, PRICEv1 oldPrice_) internal {
        console2.log("\n=== Configuring OHM Asset ===");

        // Read strict mode from args file
        bool ohmRevertOnInsufficientPriceFeeds = _readBatchArgBool(
            "configurePriceV1_2",
            "ohmRevertOnInsufficientPriceFeeds"
        );

        // Create strategy component: getAveragePrice with strict mode
        IPRICEv2.Component memory strategy = _encodeAverageStrategy(
            ohmRevertOnInsufficientPriceFeeds
        );
        IPRICEv2.Component[] memory feeds = _getOhmFeeds();

        IPriceConfigv2.PriceFeedExpectation[] memory feedExpectations = _readFeedExpectations(
            feeds.length,
            "ohm"
        );
        console2.log("OHM initial price:", feedExpectations[0].expectedPrice);

        // Set last observation time to current time
        (
            uint32 ohmMovingAverageDuration,
            uint48 ohmLastObservationTime,
            uint256[] memory ohmObservations
        ) = _getMigratedOhmObservations(oldPrice_);

        // Add asset via PriceConfig with moving average configuration
        _addAssetWithMA(
            priceConfig_,
            _ohm,
            true, // storeMovingAverage
            false, // useMovingAverage
            ohmMovingAverageDuration,
            ohmLastObservationTime,
            ohmObservations,
            strategy,
            feeds,
            feedExpectations
        );

        console2.log("OHM asset configured with migrated 30-day moving average");
    }

    function _getOhmFeeds() internal returns (IPRICEv2.Component[] memory feeds_) {
        // Read Uniswap pool addresses from args file
        address uniswapOhmWeth = _readBatchArgAddress("configurePriceV1_2", "uniswapOhmWeth");
        address uniswapOhmSusds = _readBatchArgAddress("configurePriceV1_2", "uniswapOhmSusds");
        address chainlinkOhmEth = _envAddressNotZero("external.chainlink.ohmEthPriceFeed");
        address chainlinkEthUsd = _readBatchArgAddress("configurePriceV1_2", "chainlinkEthUsd");

        uint48 chainlinkOhmEthUpdateThreshold = SafeCast.encodeUInt48(
            _readBatchArgUint256("configurePriceV1_2", "chainlinkOhmEthUpdateThreshold")
        );
        uint48 chainlinkEthUsdUpdateThreshold = SafeCast.encodeUInt48(
            _readBatchArgUint256("configurePriceV1_2", "chainlinkEthUsdUpdateThreshold")
        );

        vm.label(uniswapOhmWeth, "Uniswap OHM/WETH");
        vm.label(uniswapOhmSusds, "Uniswap OHM/sUSDS");
        vm.label(chainlinkOhmEth, "Chainlink OHM/ETH");
        vm.label(chainlinkEthUsd, "Chainlink ETH/USD");

        console2.log("Uniswap OHM/WETH:", uniswapOhmWeth);
        console2.log("Uniswap OHM/sUSDS:", uniswapOhmSusds);
        console2.log("Chainlink OHM/ETH:", chainlinkOhmEth);
        console2.log("Chainlink ETH/USD:", chainlinkEthUsd);

        // Create feed components for the two Uniswap pools and Chainlink OHM/ETH x ETH/USD
        feeds_ = new IPRICEv2.Component[](3);
        feeds_[0] = _encodeFeed(
            toSubKeycode("PRICE.UNIV3"),
            UniswapV3Price.getTokenTWAP.selector,
            abi.encode(
                UniswapV3Price.UniswapV3Params({
                    pool: IUniswapV3Pool(uniswapOhmWeth),
                    observationWindowSeconds: _uniswapOhmWethObservationWindow
                })
            )
        );
        feeds_[1] = _encodeFeed(
            toSubKeycode("PRICE.UNIV3"),
            UniswapV3Price.getTokenTWAP.selector,
            abi.encode(
                UniswapV3Price.UniswapV3Params({
                    pool: IUniswapV3Pool(uniswapOhmSusds),
                    observationWindowSeconds: _uniswapOhmSusdsObservationWindow
                })
            )
        );
        feeds_[2] = _encodeFeed(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams({
                    firstFeed: AggregatorV2V3Interface(chainlinkOhmEth),
                    firstUpdateThreshold: chainlinkOhmEthUpdateThreshold,
                    secondFeed: AggregatorV2V3Interface(chainlinkEthUsd),
                    secondUpdateThreshold: chainlinkEthUsdUpdateThreshold
                })
            )
        );
    }

    function _getMigratedOhmObservations(
        PRICEv1 oldPrice_
    )
        internal
        view
        returns (
            uint32 ohmMovingAverageDuration_,
            uint48 ohmLastObservationTime_,
            uint256[] memory ohmObservations_
        )
    {
        ohmMovingAverageDuration_ = uint32(oldPrice_.movingAverageDuration());

        uint32 oldNumObservations = oldPrice_.numObservations();
        uint256 expectedNumObservations = uint256(ohmMovingAverageDuration_) /
            uint256(oldPrice_.observationFrequency());

        if (expectedNumObservations != uint256(oldNumObservations)) {
            revert("OHM observation count mismatch");
        }

        // Migrate the live PRICE v1 ring buffer into v1.2. PRICE v2 initializes nextObsIndex
        // to 0, so rotate the old buffer such that the oldest observation remains index 0.
        ohmObservations_ = new uint256[](oldNumObservations);
        uint256 oldestObservationIndex = oldPrice_.nextObsIndex();
        for (uint256 i = 0; i < oldNumObservations; i++) {
            uint256 sourceIndex = (oldestObservationIndex + i) % oldNumObservations;
            ohmObservations_[i] = oldPrice_.observations(sourceIndex);
        }

        ohmLastObservationTime_ = oldPrice_.lastObservationTime();
    }

    /// @notice Add an asset to the PRICE module via PriceConfig
    /// @param priceConfig_ Address of the PriceConfig v2 policy
    /// @param asset_ Address of the asset to add
    /// @param strategy_ Strategy component
    /// @param feeds_ Array of feed components
    function _addAsset(
        address priceConfig_,
        address asset_,
        IPRICEv2.Component memory strategy_,
        IPRICEv2.Component[] memory feeds_,
        IPriceConfigv2.PriceFeedExpectation[] memory feedExpectations_
    ) internal {
        addToBatch(
            priceConfig_,
            abi.encodeWithSelector(
                PriceConfigv2.addAsset.selector,
                asset_,
                false, // storeMovingAverage
                false, // useMovingAverage
                uint32(0), // movingAverageDuration
                uint48(0), // lastObservationTime
                new uint256[](0), // observations
                strategy_,
                feeds_,
                feedExpectations_
            )
        );
    }

    /// @notice Add an asset to the PRICE module with moving average configuration
    /// @param priceConfig_ Address of the PriceConfig v2 policy
    /// @param asset_ Address of the asset to add
    /// @param storeMovingAverage_ Whether to store moving average observations
    /// @param useMovingAverage_ Whether to use moving average in price strategy
    /// @param movingAverageDuration_ Duration of the moving average window in seconds
    /// @param lastObservationTime_ Timestamp of the last observation
    /// @param observations_ Array of pre-populated observations
    /// @param strategy_ Strategy component
    /// @param feeds_ Array of feed components
    /// @param feedExpectations_ Expected price and tolerance for each feed
    function _addAssetWithMA(
        address priceConfig_,
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        IPRICEv2.Component memory strategy_,
        IPRICEv2.Component[] memory feeds_,
        IPriceConfigv2.PriceFeedExpectation[] memory feedExpectations_
    ) internal {
        addToBatch(
            priceConfig_,
            abi.encodeWithSelector(
                PriceConfigv2.addAsset.selector,
                asset_,
                storeMovingAverage_,
                useMovingAverage_,
                movingAverageDuration_,
                lastObservationTime_,
                observations_,
                strategy_,
                feeds_,
                feedExpectations_
            )
        );
    }

    /// @notice Read price feed expectations from the batch args file
    /// @dev    Keys use the format `{assetPrefix}ExpectedPrice` and `{assetPrefix}ExpectedToleranceBps`.
    /// @param length_ Number of configured feeds for the asset
    /// @param assetPrefix_ Lowercase asset prefix used in the args file
    /// @return expectations_ Expected price/tolerance entries for each feed
    function _readFeedExpectations(
        uint256 length_,
        string memory assetPrefix_
    ) internal view returns (IPriceConfigv2.PriceFeedExpectation[] memory expectations_) {
        uint256 expectedPrice = _readBatchArgUint256(
            "configurePriceV1_2",
            string.concat(assetPrefix_, "ExpectedPrice")
        );
        uint16 toleranceBps = SafeCast.encodeUInt16(
            _readBatchArgUint256(
                "configurePriceV1_2",
                string.concat(assetPrefix_, "ExpectedToleranceBps")
            )
        );

        expectations_ = _makeFeedExpectations(length_, expectedPrice, toleranceBps);
    }

    /// @notice Create a price feed expectation array for feeds that should share a price envelope
    /// @param length_ Number of configured feeds for the asset
    /// @param expectedPrice_ Expected feed price in PRICE decimals
    /// @param toleranceBps_ Allowed deviation from expected price in basis points
    /// @return expectations_ Expected price/tolerance entries for each feed
    function _makeFeedExpectations(
        uint256 length_,
        uint256 expectedPrice_,
        uint16 toleranceBps_
    ) internal pure returns (IPriceConfigv2.PriceFeedExpectation[] memory expectations_) {
        expectations_ = new IPriceConfigv2.PriceFeedExpectation[](length_);
        for (uint256 i; i < length_; i++) {
            expectations_[i] = IPriceConfigv2.PriceFeedExpectation({
                expectedPrice: expectedPrice_,
                toleranceBps: toleranceBps_
            });
        }
    }

    // ========== ENCODING HELPERS ========== //

    /// @notice Encode a deviation strategy component
    /// @param selector_ Function selector
    /// @param deviationBps_ Deviation in basis points
    /// @param revertOnInsufficientCount_ Strict mode flag
    /// @return strategy_ The encoded strategy component
    function _encodeDeviationStrategy(
        bytes4 selector_,
        uint16 deviationBps_,
        bool revertOnInsufficientCount_
    ) internal pure returns (IPRICEv2.Component memory strategy_) {
        strategy_ = IPRICEv2.Component({
            target: toSubKeycode("PRICE.SIMPLESTRATEGY"),
            selector: selector_,
            params: abi.encode(
                ISimplePriceFeedStrategy.DeviationParams({
                    deviationBps: deviationBps_,
                    revertOnInsufficientCount: revertOnInsufficientCount_
                })
            )
        });
    }

    /// @notice Encode an average strategy component
    /// @param revertOnInsufficientCount_ Strict mode flag
    /// @return strategy_ The encoded strategy component
    function _encodeAverageStrategy(
        bool revertOnInsufficientCount_
    ) internal pure returns (IPRICEv2.Component memory strategy_) {
        strategy_ = IPRICEv2.Component({
            target: toSubKeycode("PRICE.SIMPLESTRATEGY"),
            selector: SimplePriceFeedStrategy.getAveragePrice.selector,
            params: abi.encode(revertOnInsufficientCount_)
        });
    }

    /// @notice Encode a feed component
    /// @param target_ Submodule keycode
    /// @param selector_ Function selector
    /// @param params_ Encoded parameters
    /// @return feed_ The encoded feed component
    function _encodeFeed(
        SubKeycode target_,
        bytes4 selector_,
        bytes memory params_
    ) internal pure returns (IPRICEv2.Component memory feed_) {
        feed_ = IPRICEv2.Component({target: target_, selector: selector_, params: params_});
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
