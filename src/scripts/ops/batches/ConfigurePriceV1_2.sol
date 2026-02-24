// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ISimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";
import {SubKeycode, toSubKeycode} from "src/Submodules.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

// PRICE contracts
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
    // ========== STATE ========== //

    /// @notice Addresses of assets and Pyth contract (loaded from args or env)
    address internal _usds;
    address internal _susds;
    address internal _weth;
    address internal _ohm;
    address internal _pyth;

    /// @notice Configuration parameters (loaded from args)
    uint32 internal _ohmObservationWindow;

    // ========== PRICE VALIDATION CONSTANTS ========== //

    // TODO adjust price bounds at time of deployment
    /// @notice Price validation bounds (18 decimals)
    /// @dev    These are sanity bounds to catch misconfigured feeds
    uint256 internal constant USDS_MIN_PRICE = 0.99e18;
    uint256 internal constant USDS_MAX_PRICE = 1.01e18;
    uint256 internal constant ETH_MIN_PRICE = 1500e18;
    uint256 internal constant ETH_MAX_PRICE = 2000e18;
    uint256 internal constant OHM_MIN_PRICE = 17e18;
    uint256 internal constant OHM_MAX_PRICE = 22e18;

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
        address priceConfig = _envAddressNotZero("olympus.policies.OlympusPriceConfig");

        // Load asset addresses from env
        _usds = _envAddressNotZero("external.tokens.USDS");
        _susds = _envAddressNotZero("external.tokens.sUSDS");
        _weth = _envAddressNotZero("external.tokens.wETH");
        _ohm = _envAddressNotZero("olympus.legacy.OHM");

        // Load Pyth contract address from args file (shared by all Pyth feeds)
        _pyth = _readBatchArgAddress("configurePriceV1_2", "pyth");

        // Load configuration parameters from args file
        _ohmObservationWindow = uint32(
            _readBatchArgUint256("configurePriceV1_2", "ohmObservationWindow")
        );

        console2.log("Kernel:", kernel);
        console2.log("PriceConfig:", priceConfig);
        console2.log("USDS:", _usds);
        console2.log("sUSDS:", _susds);
        console2.log("wETH:", _weth);
        console2.log("OHM:", _ohm);

        // Install submodules first
        _installSubmodules(priceConfig);

        // Then configure each asset
        _configureUSDS(priceConfig);
        _configureSusds(priceConfig);
        _configureWeth(priceConfig);
        _configureOhm(priceConfig);

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
        address redstoneDaiUsd = _readBatchArgAddress("configurePriceV1_2", "redstoneDaiUsd");
        bytes32 pythUsdsUsdId = _readBatchArgBytes32("configurePriceV1_2", "pythUsdsUsdFeedId");

        // Read max confidence for Pyth USDS feed from args file
        uint256 pythUsdsUsdMaxConfidence = _readBatchArgUint256(
            "configurePriceV1_2",
            "pythUsdsUsdMaxConfidence"
        );

        // Read deviation parameters from args file
        uint16 usdsDeviationBps = uint16(
            _readBatchArgUint256("configurePriceV1_2", "usdsDeviationBps")
        );
        bool usdsStrictMode = _readBatchArgUint256("configurePriceV1_2", "usdsStrictMode") == 1;

        // Read update threshold from args file
        uint48 usdsUpdateThreshold = uint48(
            _readBatchArgUint256("configurePriceV1_2", "usdsUpdateThreshold")
        );

        console2.log("Chainlink USDS/USD:", chainlinkUsdsUsd);
        console2.log("RedStone DAI/USD:", redstoneDaiUsd);
        console2.logBytes32(pythUsdsUsdId);
        console2.log("Pyth contract:", _pyth);

        // Create strategy component: getAveragePriceExcludingDeviations
        IPRICEv2.Component memory strategy = _encodeDeviationStrategy(
            SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            usdsDeviationBps,
            usdsStrictMode
        );

        // Create feed components using getOneFeedPrice
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](3);
        feeds[0] = _encodeFeed(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(chainlinkUsdsUsd),
                    updateThreshold: usdsUpdateThreshold
                })
            )
        );
        feeds[1] = _encodeFeed(
            toSubKeycode("PRICE.CHAINLINK"), // RedStone uses Chainlink interface
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(redstoneDaiUsd),
                    updateThreshold: usdsUpdateThreshold
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
                    updateThreshold: usdsUpdateThreshold,
                    maxConfidence: pythUsdsUsdMaxConfidence
                })
            )
        );

        // Add asset via PriceConfig
        _addAsset(priceConfig_, _usds, strategy, feeds);

        console2.log("USDS asset configured");
    }

    /// @notice Configure sUSDS asset (uses ERC4626 submodule)
    /// @param priceConfig_ Address of the PriceConfig v2 policy
    function _configureSusds(address priceConfig_) internal {
        console2.log("\n=== Configuring sUSDS Asset ===");

        // Create strategy component: ERC4626 price (uses underlying USDS price)
        // Note: Empty params for ERC4626 - it determines the underlying from the asset itself
        IPRICEv2.Component memory strategy = IPRICEv2.Component({
            target: toSubKeycode("PRICE.ERC4626"),
            selector: ERC4626Price.getPriceFromUnderlying.selector,
            params: "" // Empty params - underlying is derived from the asset being configured
        });

        // No feeds needed for ERC4626 - it uses the underlying asset's price
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](0);

        // Add asset via PriceConfig
        _addAsset(priceConfig_, _susds, strategy, feeds);

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

        // Read max confidence for Pyth ETH feed from args file
        uint256 pythEthUsdMaxConfidence = _readBatchArgUint256(
            "configurePriceV1_2",
            "pythEthUsdMaxConfidence"
        );

        // Read deviation parameters from args file
        uint16 wethDeviationBps = uint16(
            _readBatchArgUint256("configurePriceV1_2", "wethDeviationBps")
        );
        bool wethStrictMode = _readBatchArgUint256("configurePriceV1_2", "wethStrictMode") == 1;

        // Read update threshold from args file
        uint48 wethUpdateThreshold = uint48(
            _readBatchArgUint256("configurePriceV1_2", "wethUpdateThreshold")
        );

        console2.log("Chainlink ETH/USD:", chainlinkEthUsd);
        console2.log("RedStone ETH/USD:", redstoneEthUsd);
        console2.logBytes32(pythEthUsdId);
        console2.log("Pyth contract:", _pyth);

        // Create strategy component: getAveragePriceExcludingDeviations
        IPRICEv2.Component memory strategy = _encodeDeviationStrategy(
            SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            wethDeviationBps,
            wethStrictMode
        );

        // Create feed components using getOneFeedPrice
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](3);
        feeds[0] = _encodeFeed(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(chainlinkEthUsd),
                    updateThreshold: wethUpdateThreshold
                })
            )
        );
        feeds[1] = _encodeFeed(
            toSubKeycode("PRICE.CHAINLINK"), // RedStone uses Chainlink interface
            ChainlinkPriceFeeds.getOneFeedPrice.selector,
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(redstoneEthUsd),
                    updateThreshold: wethUpdateThreshold
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
                    updateThreshold: wethUpdateThreshold,
                    maxConfidence: pythEthUsdMaxConfidence
                })
            )
        );

        // Add asset via PriceConfig
        _addAsset(priceConfig_, _weth, strategy, feeds);

        console2.log("wETH asset configured");
    }

    /// @notice Configure OHM asset
    /// @param priceConfig_ Address of the PriceConfig v2 policy
    function _configureOhm(address priceConfig_) internal {
        console2.log("\n=== Configuring OHM Asset ===");

        // Read Uniswap pool addresses from args file
        address uniswapOhmWeth = _readBatchArgAddress("configurePriceV1_2", "uniswapOhmWeth");
        address uniswapOhmSusds = _readBatchArgAddress("configurePriceV1_2", "uniswapOhmSusds");

        // Read strict mode and observation window from args file
        bool ohmStrictMode = _readBatchArgUint256("configurePriceV1_2", "ohmStrictMode") == 1;

        // Load initial price from args file (18 decimals, represents USD price)
        uint256 ohmInitialPrice = _readBatchArgUint256("configurePriceV1_2", "ohmInitialPrice");

        console2.log("Uniswap OHM/WETH:", uniswapOhmWeth);
        console2.log("Uniswap OHM/sUSDS:", uniswapOhmSusds);
        console2.log("OHM initial price:", ohmInitialPrice);

        // Create strategy component: getAveragePrice with strict mode
        IPRICEv2.Component memory strategy = _encodeAverageStrategy(ohmStrictMode);

        // Create feed components for the two Uniswap pools using getTokenPrice
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](2);
        feeds[0] = _encodeFeed(
            toSubKeycode("PRICE.UNIV3"),
            UniswapV3Price.getTokenPrice.selector,
            abi.encode(
                _ohm, // lookupToken (OHM)
                abi.encode(
                    UniswapV3Price.UniswapV3Params({
                        pool: IUniswapV3Pool(uniswapOhmWeth),
                        observationWindowSeconds: _ohmObservationWindow
                    })
                )
            )
        );
        feeds[1] = _encodeFeed(
            toSubKeycode("PRICE.UNIV3"),
            UniswapV3Price.getTokenPrice.selector,
            abi.encode(
                _ohm, // lookupToken (OHM)
                abi.encode(
                    UniswapV3Price.UniswapV3Params({
                        pool: IUniswapV3Pool(uniswapOhmSusds),
                        observationWindowSeconds: _ohmObservationWindow
                    })
                )
            )
        );

        // Create pre-populated observations array (21 observations for 7-day moving average)
        // Observation frequency is 8 hours, so 7 days = 21 observations
        uint256[] memory ohmObservations = new uint256[](21);
        for (uint256 i = 0; i < 21; i++) {
            ohmObservations[i] = ohmInitialPrice;
        }

        // Set last observation time to current time
        uint48 ohmLastObservationTime = uint48(block.timestamp);

        // Add asset via PriceConfig with moving average configuration
        _addAssetWithMA(
            priceConfig_,
            _ohm,
            true, // storeMovingAverage
            false, // useMovingAverage
            604800, // movingAverageDuration (7 days in seconds)
            ohmLastObservationTime,
            ohmObservations,
            strategy,
            feeds
        );

        console2.log("OHM asset configured with 7-day moving average");
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
        IPRICEv2.Component[] memory feeds_
    ) internal {
        addToBatch(
            priceConfig_,
            abi.encodeWithSelector(
                PriceConfigv2.addAssetPrice.selector,
                asset_,
                false, // storeMovingAverage
                false, // useMovingAverage
                uint32(0), // movingAverageDuration
                uint48(0), // lastObservationTime
                new uint256[](0), // observations
                strategy_,
                feeds_
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
    function _addAssetWithMA(
        address priceConfig_,
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        IPRICEv2.Component memory strategy_,
        IPRICEv2.Component[] memory feeds_
    ) internal {
        addToBatch(
            priceConfig_,
            abi.encodeWithSelector(
                PriceConfigv2.addAssetPrice.selector,
                asset_,
                storeMovingAverage_,
                useMovingAverage_,
                movingAverageDuration_,
                lastObservationTime_,
                observations_,
                strategy_,
                feeds_
            )
        );
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

    // ========== POST-BATCH VALIDATION ========== //

    /// @notice Validates that configured prices are within reasonable bounds
    /// @dev    Call this function after the batch has been executed to verify prices
    /// @param priceModule_ Address of the PRICE v1.2 module
    function validatePricesAreSane(address priceModule_) external view {
        console2.log("\n=== Validating Asset Prices ===");

        IPRICEv2 price = IPRICEv2(priceModule_);

        // Load asset addresses from env
        address usds = _envAddressNotZero("external.tokens.USDS");
        address weth = _envAddressNotZero("external.tokens.wETH");
        address ohm = _envAddressNotZero("olympus.legacy.OHM");

        // Validate USDS price
        uint256 usdsPrice = price.getPrice(usds);
        console2.log("USDS price:", usdsPrice);
        _assertPriceInRange(usdsPrice, USDS_MIN_PRICE, USDS_MAX_PRICE, "USDS");

        // Validate wETH price
        uint256 wethPrice = price.getPrice(weth);
        console2.log("wETH price:", wethPrice);
        _assertPriceInRange(wethPrice, ETH_MIN_PRICE, ETH_MAX_PRICE, "wETH");

        // Validate OHM price
        uint256 ohmPrice = price.getPrice(ohm);
        console2.log("OHM price:", ohmPrice);
        _assertPriceInRange(ohmPrice, OHM_MIN_PRICE, OHM_MAX_PRICE, "OHM");

        console2.log("All prices are within reasonable bounds");
    }

    /// @notice Asserts that a price is within a reasonable range
    /// @param price_ The price to validate
    /// @param minPrice_ Minimum acceptable price
    /// @param maxPrice_ Maximum acceptable price
    /// @param assetName_ Name of the asset (for error message)
    function _assertPriceInRange(
        uint256 price_,
        uint256 minPrice_,
        uint256 maxPrice_,
        string memory assetName_
    ) internal pure {
        if (price_ < minPrice_) {
            revert(string.concat(assetName_, " price below minimum"));
        }
        if (price_ > maxPrice_) {
            revert(string.concat(assetName_, " price above maximum"));
        }
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
