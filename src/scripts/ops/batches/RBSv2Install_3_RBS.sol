// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import "src/Kernel.sol";

// Bophades modules
import {OlympusPrice} from "modules/PRICE/OlympusPrice.sol";
import "modules/PRICE/OlympusPrice.v2.sol";

// PRICE submodules
import {BunniPrice} from "modules/PRICE/submodules/feeds/BunniPrice.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ERC4626Price} from "modules/PRICE/submodules/feeds/ERC4626Price.sol";
import {UniswapV2PoolTokenPrice} from "modules/PRICE/submodules/feeds/UniswapV2PoolTokenPrice.sol";
import {UniswapV3Price} from "modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

// SPPLY submodules
import {BunniSupply} from "modules/SPPLY/submodules/BunniSupply.sol";

// Bophades policies
import {Appraiser} from "policies/OCA/Appraiser.sol";
import {IAppraiser} from "policies/OCA/interfaces/IAppraiser.sol";
import {PriceConfigV2} from "policies/OCA/PriceConfig.v2.sol";
import {OlympusHeart} from "policies/RBS/Heart.sol";
import {Operator} from "policies/RBS/Operator.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {BondCallback} from "policies/Bonds/BondCallback.sol";
import {BunniManager} from "policies/UniswapV3/BunniManager.sol";
import {TreasuryConfig} from "policies/OCA/TreasuryConfig.sol";
import {SupplyConfig} from "policies/OCA/SupplyConfig.sol";

// Libraries
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// UniswapV3
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

/// @notice     Activates and configures PRICE v2
/// @notice     Configures TRSRY assets
/// @notice     Activates RBSv2 (Appraiser, Heart, Operator)
contract RBSv2Install_3_RBS is OlyBatch, StdAssertions {
    using stdJson for string;

    // Existing Olympus Contracts
    address kernel;
    address price;
    address heart;
    address operator;
    address rolesAdmin;
    address bondCallback;
    address priceConfigV1;
    address treasuryV1_1;

    // Tokens
    address ohm;
    address dai;
    address sdai;
    address weth;
    address veFXS;
    address fxs;
    address btrfly;

    // Price Feeds
    address usdPerEthPriceFeed;
    address ethPerDaiPriceFeed;
    address usdPerDaiPriceFeed;
    address usdPerFxsPriceFeed;
    address ethPerBtcPriceFeed;
    address usdPerBtcPriceFeed;

    // Uniswap V3 Pools
    address daiWethUniV3Pool;
    address btrflyWethUniV3Pool;

    // Uniswap V3 POL
    address ohmWethUniV3Pool;
    uint256 ohmWethTokenId;
    int24 ohmWethTickLower;
    int24 ohmWethTickUpper;
    address positionManager;

    // BunniManager configuration
    uint16 twapMaxDeviationBps;
    uint32 twapObservationWindow;

    // Allocators
    address veFXSAllocator;

    // New Olympus Contracts
    address priceV2;
    address bunniPrice;
    address chainlinkPriceFeeds;
    address erc4626Price;
    address uniswapV2PoolTokenPrice;
    address uniswapV3Price;
    address simplePriceFeedStrategy;
    address appraiser;
    address priceConfigV2;
    address heartV2;
    address operatorV2;
    address bunniManager;
    address bunniLens;
    address treasuryConfig;
    address supplyConfig;

    // Wallets
    address daoWorkingWallet;

    uint32 internal constant DEFAULT_RESERVE_TWAP_OBSERVATION_WINDOW = 30 days;
    uint32 internal constant DEFAULT_TWAP_OBSERVATION_WINDOW = 7 days;
    uint32 internal constant DEFAULT_CHAINLINK_UPDATE_THRESHOLD = 24 hours;

    function loadEnv() internal override {
        kernel = envAddress("current", "olympus.Kernel");

        price = envAddress("current", "olympus.modules.OlympusPriceV1");
        treasuryV1_1 = envAddress("current", "olympus.modules.OlympusTreasuryV1_1");

        heart = envAddress("current", "olympus.policies.OlympusHeart");
        operator = envAddress("current", "olympus.policies.Operator");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        bondCallback = envAddress("current", "olympus.policies.BondCallback");
        priceConfigV1 = envAddress("current", "olympus.policies.PriceConfigV1");
        treasuryConfig = envAddress("current", "olympus.policies.TreasuryConfig");
        supplyConfig = envAddress("current", "olympus.policies.SupplyConfig");

        ohm = envAddress("current", "olympus.legacy.OHM");
        dai = envAddress("current", "external.tokens.DAI");
        sdai = envAddress("current", "external.tokens.sDAI");
        weth = envAddress("current", "external.tokens.WETH");
        veFXS = envAddress("current", "external.tokens.veFXS");
        fxs = envAddress("current", "external.tokens.FXS");
        btrfly = envAddress("current", "external.tokens.BTRFLY");

        usdPerEthPriceFeed = envAddress("current", "external.chainlink.ethUsdPriceFeed");
        ethPerDaiPriceFeed = envAddress("current", "external.chainlink.daiEthPriceFeed");
        usdPerDaiPriceFeed = envAddress("current", "external.chainlink.daiUsdPriceFeed");
        usdPerFxsPriceFeed = envAddress("current", "external.chainlink.fxsUsdPriceFeed");
        ethPerBtcPriceFeed = envAddress("current", "external.chainlink.btcEthPriceFeed");
        usdPerBtcPriceFeed = envAddress("current", "external.chainlink.btcUsdPriceFeed");

        daiWethUniV3Pool = envAddress("current", "external.uniswapV3.DaiWethPool");
        btrflyWethUniV3Pool = envAddress("current", "external.uniswapV3.BtrflyWethPool");
        ohmWethUniV3Pool = envAddress("current", "external.uniswapV3.OhmWethPool");
        ohmWethTokenId = envUint("current", "external.UniswapV3LegacyPOL.OhmWethTokenId");
        ohmWethTickLower = int24(envInt("current", "external.UniswapV3LegacyPOL.OhmWethMinTick"));
        ohmWethTickUpper = int24(envInt("current", "external.UniswapV3LegacyPOL.OhmWethMaxTick"));
        positionManager = envAddress(
            "current",
            "external.UniswapV3LegacyPOL.NonfungiblePositionManager"
        );
        bunniLens = envAddress("current", "external.Bunni.BunniLens");

        twapMaxDeviationBps = uint16(envUint("current", "external.Bunni.TwapMaxDeviationBps"));
        twapObservationWindow = uint32(envUint("current", "external.Bunni.TwapObservationWindow"));

        veFXSAllocator = envAddress("current", "olympus.legacy.veFXSAllocator");

        priceV2 = envAddress("current", "olympus.modules.OlympusPriceV2");
        bunniPrice = envAddress("current", "olympus.submodules.PRICE.BunniPrice");
        chainlinkPriceFeeds = envAddress("current", "olympus.submodules.PRICE.ChainlinkPriceFeeds");
        erc4626Price = envAddress("current", "olympus.submodules.PRICE.ERC4626Price");
        uniswapV2PoolTokenPrice = envAddress(
            "current",
            "olympus.submodules.PRICE.UniswapV2PoolTokenPrice"
        );
        uniswapV3Price = envAddress("current", "olympus.submodules.PRICE.UniswapV3Price");
        simplePriceFeedStrategy = envAddress(
            "current",
            "olympus.submodules.PRICE.SimplePriceFeedStrategy"
        );
        appraiser = envAddress("current", "olympus.policies.Appraiser");
        priceConfigV2 = envAddress("current", "olympus.policies.PriceConfigV2");
        heartV2 = envAddress("current", "olympus.policies.OlympusHeartV2");
        operatorV2 = envAddress("current", "olympus.policies.OperatorV2");
        bunniManager = envAddress("current", "olympus.policies.BunniManager");

        daoWorkingWallet = envAddress("current", "olympus.legacy.workingWallet");
    }

    function _bunniManagerTestSetup() internal {
        console2.log("\n");
        console2.log("*** SIMULATION SETUP (NOT FOR PRODUCTION) ***");

        // The following are needed when simulating on a fork, as batches cannot be signed
        // Install TRSRY v1.1
        {
            console2.log("Upgrading TRSRY module to new version at %s", treasuryV1_1);

            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.UpgradeModule,
                    treasuryV1_1
                )
            );
            console2.log("    Upgraded OlympusTreasury to new version");
        }

        // Activate TreasuryConfig
        {
            console2.log("Activating TreasuryConfig policy");

            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.ActivatePolicy,
                    treasuryConfig
                )
            );

            console2.log("Granting policy role for TreasuryConfig policy");
            addToBatch(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("treasuryconfig_policy"),
                    daoMS
                )
            );
        }

        // Configure TRSRY v1.1 to track wETH
        {
            console2.log("Adding WETH to TRSRY");
            addToBatch(
                treasuryConfig,
                abi.encodeWithSelector(TreasuryConfig.addAsset.selector, weth, new address[](0))
            );
        }

        // Install SPPLY
        {
            address spply = envAddress("current", "olympus.modules.OlympusSupply");
            console2.log("Installing OlympusSupply module");

            addToBatch(
                kernel,
                abi.encodeWithSelector(Kernel.executeAction.selector, Actions.InstallModule, spply)
            );
        }

        // Activate SupplyConfig
        {
            console2.log("Installing SupplyConfig policy");
            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.ActivatePolicy,
                    supplyConfig
                )
            );

            console2.log("Granting admin role for SupplyConfig policy");
            addToBatch(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("supplyconfig_admin"),
                    daoMS
                )
            );
            console2.log("Granting policy role for SupplyConfig policy");
            addToBatch(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("supplyconfig_policy"),
                    daoMS
                )
            );
        }

        // Install BunniSupply
        {
            address bunniSupply = envAddress("current", "olympus.submodules.SPPLY.BunniSupply");

            console2.log("Installing BunniSupply submodule");
            addToBatch(
                supplyConfig,
                abi.encodeWithSelector(
                    SupplyConfig.installSubmodule.selector,
                    BunniSupply(bunniSupply)
                )
            );
        }

        console2.log("*** END SIMULATION SETUP ***");
        console2.log("\n");
    }

    function install() public {
        // ==================== SECTION 1: PRICE v2 Installation ==================== //

        // This DAO MS batch:
        // 1. deactivates old heart + operator policies at contract level
        // 2. deactivates old heart + operator policies at kernel level
        // 3. upgrades the PRICE module to v2
        // 4. activates priceConfigV2 policy
        // 5. sets roles for new policy access control
        // 6. installs submodules on price v2

        // 1. Deactivate old heart + operator policies at contract level
        // 1a. Grant operator_policy role to the DAO MS
        console2.log("Granting operator_policy role to DAO MS");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("operator_policy"), daoMS)
        );

        // 1b. Actual deactivation
        console2.log("Deactivating existing Heart contract");
        addToBatch(heart, abi.encodeWithSelector(OlympusHeart.deactivate.selector));
        console2.log("Deactivating existing Operator contract");
        addToBatch(operator, abi.encodeWithSelector(Operator.deactivate.selector));

        // 2. Deactivate old heart + operator policies at kernel level
        console2.log("Deactivating existing Heart policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.DeactivatePolicy, heart)
        );
        console2.log("Deactivating existing Operator policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                operator
            )
        );

        // 3. Upgrade the PRICE module to v2
        // Requires that Operator is deactivated
        console2.log("Upgrading PRICE module to v2");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.UpgradeModule, priceV2)
        );

        // 4. Activate PriceConfigV2 policy
        console2.log("Activating PriceConfigV2 policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                priceConfigV2
            )
        );

        // 4a. Disable PriceConfigV1 policy (superseded by PriceConfigV2)
        console2.log("Deactivating PriceConfigV1 policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                priceConfigV1
            )
        );

        // 5. Set roles for new policy access control
        // PriceConfigV2 policy
        //     - Give DAO MS the priceconfig_admin role
        //     - Give DAO MS the priceconfig_policy role
        console2.log("Granting admin role for PriceConfigV2 policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("priceconfig_admin"),
                daoMS
            )
        );
        console2.log("Granting policy role for PriceConfigV2 policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("priceconfig_policy"),
                daoMS
            )
        );

        // 6. Install submodules on PRICEv2
        //     - Install BunniPrice submodule
        //     - Install ChainlinkPriceFeeds submodule
        //     - Install ERC4626Price submodule
        //     - Install UniswapV2PoolTokenPrice submodule
        //     - Install UniswapV3Price submodule
        //     - Install SimplePriceFeedStrategy submodule
        console2.log("Installing BunniPrice submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, bunniPrice)
        );
        console2.log("Installing ChainlinkPriceFeeds submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, chainlinkPriceFeeds)
        );
        console2.log("Installing ERC4626Price submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, erc4626Price)
        );
        console2.log("Installing UniswapV2PoolTokenPrice submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, uniswapV2PoolTokenPrice)
        );
        console2.log("Installing UniswapV3Price submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, uniswapV3Price)
        );
        console2.log("Installing SimplePriceFeedStrategy submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, simplePriceFeedStrategy)
        );

        // ==================== SECTION 2: PRICE v2 Configuration ==================== //

        // This Policy MS batch:
        // 1. Configure WETH on PRICE
        // 2. Configure DAI on PRICE
        // 3. Configure sDAI on PRICE
        // 4. Configure veFXS on PRICE
        // 5. Configure FXS on PRICE
        // 6. Configure OHM on PRICE
        // 7. Configure BTRFLY on PRICE

        // 0. Load variables from the JSON file
        // TODO final values need to be added
        string memory argData = vm.readFile("./src/scripts/ops/batches/RBSv2Install_3_RBS.json");

        // 1. Configure DAI price feed and moving average data on PRICE
        // - Uses three data sources for redundancy
        //   - Chainlink DAI-USD price feed
        //   - Chainlink DAI-ETH price feed divided by Chainlink ETH-USD price feed (which resolves to USD per DAI)
        //   - DAI-wETH Uniswap V3 pool TWAP
        // - Configures PRICE to track a moving average (as it is used by the Operator)
        // - Does not use the moving average as input to the price
        {
            PRICEv2.Component[] memory daiFeeds = new PRICEv2.Component[](3);
            {
                daiFeeds[0] = PRICEv2.Component(
                    toSubKeycode("PRICE.CHAINLINK"),
                    ChainlinkPriceFeeds.getOneFeedPrice.selector,
                    abi.encode(
                        ChainlinkPriceFeeds.OneFeedParams(
                            AggregatorV2V3Interface(usdPerDaiPriceFeed),
                            DEFAULT_CHAINLINK_UPDATE_THRESHOLD
                        )
                    )
                );
                daiFeeds[1] = PRICEv2.Component(
                    toSubKeycode("PRICE.CHAINLINK"),
                    ChainlinkPriceFeeds.getTwoFeedPriceMul.selector,
                    abi.encode(
                        ChainlinkPriceFeeds.TwoFeedParams(
                            AggregatorV2V3Interface(ethPerDaiPriceFeed),
                            DEFAULT_CHAINLINK_UPDATE_THRESHOLD,
                            AggregatorV2V3Interface(usdPerEthPriceFeed),
                            DEFAULT_CHAINLINK_UPDATE_THRESHOLD
                        )
                    )
                );
                daiFeeds[2] = PRICEv2.Component(
                    toSubKeycode("PRICE.UNIV3"),
                    UniswapV3Price.getTokenTWAP.selector,
                    abi.encode(
                        UniswapV3Price.UniswapV3Params({
                            pool: IUniswapV3Pool(daiWethUniV3Pool),
                            observationWindowSeconds: twapObservationWindow, // This is shorter, as it is compared against reserves
                            maxDeviationBps: twapMaxDeviationBps
                        })
                    )
                );
            }

            uint256 daiLastObsTime_ = argData.readUint(".daiLastObsTime");
            uint256[] memory daiObs_ = argData.readUintArray(".daiObs"); // 30 days * 24 hours / 8 hours = 90 observations

            console2.log("Adding DAI price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    dai,
                    true, // store moving average
                    false, // don't use the moving average as part of price strategy
                    DEFAULT_RESERVE_TWAP_OBSERVATION_WINDOW, // moving average duration
                    daiLastObsTime_,
                    daiObs_,
                    PRICEv2.Component(
                        toSubKeycode("PRICE.SIMPLESTRATEGY"),
                        SimplePriceFeedStrategy.getAveragePrice.selector,
                        abi.encode(0)
                    ),
                    daiFeeds
                )
            );

            console2.log("    DAI price: %s (18 dp)", OlympusPricev2(priceV2).getPrice(dai));
        }

        // 2. Configure sDAI price feed and moving average data on PRICE
        // - Uses the DAI price to determine the sDAI price
        {
            uint256[] memory sdaiObs_ = new uint256[](0);
            PRICEv2.Component[] memory sdaiFeeds = new PRICEv2.Component[](1);
            sdaiFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.ERC4626"),
                ERC4626Price.getPriceFromUnderlying.selector,
                abi.encode(0)
            );
            console2.log("Adding sDAI price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    sdai,
                    false, // don't store moving average
                    false, // don't use the moving average as part of price strategy
                    0, // 0 day moving average
                    0,
                    sdaiObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    sdaiFeeds
                )
            );

            console2.log("    sDAI price: %s (18 dp)", OlympusPricev2(priceV2).getPrice(sdai));
        }

        // 3. Configure WETH price feed and moving average data on PRICE
        // - Uses two data sources for redundancy:
        //   - Chainlink ETH-USD price feed
        //   - Chainlink BTC-ETH price feed divided by Chainlink BTC-USD price feed (which resolves to USD per ETH)
        //   - Three Chainlink feeds are used as the likelihood of all three breaking is low
        // - The price will be the average of the above two
        // - No moving average tracked or used
        {
            PRICEv2.Component[] memory wethFeeds = new PRICEv2.Component[](2);
            wethFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(usdPerEthPriceFeed),
                        DEFAULT_CHAINLINK_UPDATE_THRESHOLD
                    )
                )
            );
            wethFeeds[1] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getTwoFeedPriceDiv.selector,
                abi.encode(
                    ChainlinkPriceFeeds.TwoFeedParams(
                        AggregatorV2V3Interface(usdPerBtcPriceFeed),
                        DEFAULT_CHAINLINK_UPDATE_THRESHOLD,
                        AggregatorV2V3Interface(ethPerBtcPriceFeed),
                        DEFAULT_CHAINLINK_UPDATE_THRESHOLD
                    )
                )
            );

            uint256[] memory wethObs_ = new uint256[](0);

            console2.log("Adding WETH price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    weth,
                    false, // store moving average
                    false, // use the moving average as part of price strategy
                    DEFAULT_TWAP_OBSERVATION_WINDOW, // moving average duration
                    0,
                    wethObs_,
                    PRICEv2.Component(
                        toSubKeycode("PRICE.SIMPLESTRATEGY"),
                        SimplePriceFeedStrategy.getAveragePrice.selector,
                        abi.encode(0)
                    ),
                    wethFeeds
                )
            );

            console2.log("    wETH price: %s (18 dp)", OlympusPricev2(priceV2).getPrice(weth));
        }

        // 4. Configure veFXS price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        // - Track and store the moving average, so that a broken price feed doesn't brick the system
        {
            PRICEv2.Component[] memory veFXSFeeds = new PRICEv2.Component[](1);
            veFXSFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(usdPerFxsPriceFeed),
                        DEFAULT_CHAINLINK_UPDATE_THRESHOLD
                    )
                )
            );

            uint256 fxsLastObsTime_ = argData.readUint(".fxsLastObsTime");
            uint256[] memory fxsObs_ = argData.readUintArray(".fxsObs"); // 7 days * 24 hours / 8 hours = 21 observations

            console2.log("Adding veFXS price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    veFXS,
                    true, // store moving average
                    true, // use the moving average as part of price strategy
                    DEFAULT_TWAP_OBSERVATION_WINDOW, // moving average duration
                    fxsLastObsTime_,
                    fxsObs_,
                    PRICEv2.Component(
                        toSubKeycode("PRICE.SIMPLESTRATEGY"),
                        SimplePriceFeedStrategy.getAveragePrice.selector,
                        abi.encode(0)
                    ),
                    veFXSFeeds
                )
            );

            console2.log("    veFXS price: %s (18 dp)", OlympusPricev2(priceV2).getPrice(veFXS));
        }

        // 5. Configure FXS price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        // - Track and store the moving average, so that a broken price feed doesn't brick the system
        {
            PRICEv2.Component[] memory fxsFeeds = new PRICEv2.Component[](1);
            fxsFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(usdPerFxsPriceFeed),
                        DEFAULT_CHAINLINK_UPDATE_THRESHOLD
                    )
                )
            );

            uint256 fxsLastObsTime_ = argData.readUint(".fxsLastObsTime");
            uint256[] memory fxsObs_ = argData.readUintArray(".fxsObs"); // 7 days * 24 hours / 8 hours = 21 observations

            console2.log("Adding FXS price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    fxs,
                    true, // store moving average
                    true, // use the moving average as part of price strategy
                    DEFAULT_TWAP_OBSERVATION_WINDOW, // moving average
                    fxsLastObsTime_,
                    fxsObs_,
                    PRICEv2.Component(
                        toSubKeycode("PRICE.SIMPLESTRATEGY"),
                        SimplePriceFeedStrategy.getAveragePrice.selector,
                        abi.encode(0)
                    ),
                    fxsFeeds
                )
            );

            console2.log("    FXS price: %s (18 dp)", OlympusPricev2(priceV2).getPrice(fxs));
        }

        // 6. Configure OHM on PRICE
        // - Uses a TWAP from the Uniswap V3 pool with the configured observation window
        // - Store the MA as it is required by Operator
        {
            PRICEv2.Component[] memory ohmFeeds = new PRICEv2.Component[](1);
            ohmFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.UNIV3"),
                UniswapV3Price.getTokenTWAP.selector,
                abi.encode(
                    UniswapV3Price.UniswapV3Params({
                        pool: IUniswapV3Pool(ohmWethUniV3Pool),
                        observationWindowSeconds: twapObservationWindow, // This is shorter, as it is compared against reserves
                        maxDeviationBps: twapMaxDeviationBps
                    })
                )
            );

            uint256 ohmLastObsTime_ = argData.readUint(".ohmLastObsTime");
            uint256[] memory ohmObs_ = argData.readUintArray(".ohmObs"); // 30 days * 24 hours / 8 hours = 90 observations

            console2.log("Adding OHM price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    ohm,
                    true, // store moving average
                    false, // use the moving average as part of price strategy
                    DEFAULT_RESERVE_TWAP_OBSERVATION_WINDOW, // moving average
                    ohmLastObsTime_,
                    ohmObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    ohmFeeds
                )
            );

            console2.log("    OHM price: %s (9 dp)", OlympusPricev2(priceV2).getPrice(ohm));
        }

        // 7. Configure BTRFLY on PRICE
        // - Uses a Uniswap V3 TWAP with the configured observation window
        // - Does not require an internal moving average, as the Uniswap V3 is resilient
        {
            PRICEv2.Component[] memory btrflyFeeds = new PRICEv2.Component[](1);
            btrflyFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.UNIV3"),
                UniswapV3Price.getTokenTWAP.selector,
                abi.encode(
                    UniswapV3Price.UniswapV3Params({
                        pool: IUniswapV3Pool(btrflyWethUniV3Pool),
                        observationWindowSeconds: twapObservationWindow, // This is shorter, as it is compared against reserves
                        maxDeviationBps: twapMaxDeviationBps
                    })
                )
            );

            uint256 btrflyLastObsTime_ = 0;
            uint256[] memory btrflyObs_ = new uint256[](0);

            console2.log("Adding BTRFLY price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    btrfly,
                    false, // store moving average
                    false, // use the moving average as part of price strategy
                    0,
                    btrflyLastObsTime_,
                    btrflyObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    btrflyFeeds
                )
            );

            console2.log("    BTRFLY price: %s (18 dp)", OlympusPricev2(priceV2).getPrice(btrfly));
        }

        // ==================== SECTION 3: BunniManager Migration ==================== //

        // NOTE: Only enable during fork testing
        // _bunniManagerTestSetup();

        // This DAO MS batch:
        // 1. Set roles for policy access control (bunni_admin)
        // 2. Activates the BunniManager policy
        // 3. Sets the BunniLens variable on the BunniManager policy
        // 4. Withdraws liquidity from the existing Uniswap V3 pool
        // 5. Transfers withdrawn wETH to TRSRY v1.1
        // 6. Deploys an LP token for pool
        // 7. Deposits liquidity into the poll
        // 8. Activates the LP token

        // 1. Set roles for policy access control
        // BunniManager policy
        //     - Give DAO MS the bunni_admin role
        console2.log("Granting admin role for BunniManager policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("bunni_admin"), daoMS)
        );

        // 2. Activate the BunniManager policy
        console2.log("Activating BunniManager policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                bunniManager
            )
        );

        // 3. Sets the BunniLens variable on the BunniManager policy
        // This cannot be performed at deployment-time
        // It also needs to be performed after policy activation
        console2.log("Setting BunniLens variable on BunniManager policy: %s", bunniLens);
        addToBatch(
            bunniManager,
            abi.encodeWithSelector(BunniManager.setBunniLens.selector, bunniLens)
        );

        // 4. Withdraw liquidity from the existing Uniswap V3 pool into the DAO MS
        uint256 ohmBalanceWithdrawn;
        uint256 wethBalanceWithdrawn;
        {
            // Determine token ordering
            uint8 ohmIndex;
            {
                address token0 = IUniswapV3Pool(ohmWethUniV3Pool).token0();

                if (token0 == ohm) {
                    ohmIndex = 0;
                } else if (token0 == weth) {
                    ohmIndex = 1;
                } else {
                    revert("Invalid token0");
                }
            }

            // Determine the liquidity and token amounts
            uint128 liquidity;
            uint256 token0AmountMin;
            uint256 token1AmountMin;
            {
                (, , , , , , , uint128 _liquidity, , , , ) = INonfungiblePositionManager(
                    positionManager
                ).positions(ohmWethTokenId);
                liquidity = _liquidity;

                (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(ohmWethUniV3Pool).slot0();
                (uint256 token0Amount, uint256 token1Amount) = LiquidityAmounts
                    .getAmountsForLiquidity(
                        sqrtPriceX96,
                        TickMath.getSqrtRatioAtTick(ohmWethTickLower),
                        TickMath.getSqrtRatioAtTick(ohmWethTickUpper),
                        liquidity
                    );

                // Account for slippage
                token0AmountMin = (token0Amount * (10000 - 100)) / 10000;
                token1AmountMin = (token1Amount * (10000 - 100)) / 10000;
            }

            // Decrease liquidity (which should also collect fees)
            {
                INonfungiblePositionManager.DecreaseLiquidityParams
                    memory decreaseLiquidityParams = INonfungiblePositionManager
                        .DecreaseLiquidityParams(
                            ohmWethTokenId,
                            liquidity,
                            token0AmountMin,
                            token1AmountMin,
                            block.timestamp
                        );

                console2.log("Decreasing liquidity for existing Uniswap V3 OHM-wETH pool");
                console2.log("    Liquidity is", liquidity);

                addToBatch(
                    positionManager,
                    abi.encodeWithSelector(
                        INonfungiblePositionManager.decreaseLiquidity.selector,
                        decreaseLiquidityParams
                    )
                );
            }

            // Collect liquidity
            {
                INonfungiblePositionManager.CollectParams
                    memory collectParams = INonfungiblePositionManager.CollectParams(
                        ohmWethTokenId,
                        address(daoMS),
                        type(uint128).max,
                        type(uint128).max
                    );

                console2.log("Collecting liquidity for existing Uniswap V3 OHM-wETH pool");
                (uint256 collectAmount0, uint256 collectAmount1) = abi.decode(
                    addToBatch(
                        positionManager,
                        abi.encodeWithSelector(
                            INonfungiblePositionManager.collect.selector,
                            collectParams
                        )
                    ),
                    (uint256, uint256)
                );

                {
                    (
                        ,
                        ,
                        ,
                        ,
                        ,
                        ,
                        ,
                        uint128 remainingLiquidity,
                        ,
                        ,
                        uint128 tokensOwed0,
                        uint128 tokensOwed1
                    ) = INonfungiblePositionManager(positionManager).positions(ohmWethTokenId);
                    assertEq(remainingLiquidity, 0, "Remaining liquidity should be 0");
                    assertEq(tokensOwed0, 0, "tokensOwed0 should be 0");
                    assertEq(tokensOwed1, 0, "tokensOwed1 should be 0");
                }

                ohmBalanceWithdrawn += ohmIndex == 0 ? collectAmount0 : collectAmount1;
                wethBalanceWithdrawn += ohmIndex == 0 ? collectAmount1 : collectAmount0;
            }

            console2.log("    Withdrawn OHM balance (9dp) is", ohmBalanceWithdrawn);
            console2.log("    Withdrawn WETH balance (18dp) is", wethBalanceWithdrawn);
            console2.log("    NOTE: Withdrawn OHM needs to be burnt manually");
        }

        // 5. Transfer the withdrawn wETH to TRSRY v1.1
        {
            console2.log("Approving withdrawn WETH for transfer to TRSRY v1.1");
            addToBatch(
                weth,
                abi.encodeWithSelector(ERC20.approve.selector, treasuryV1_1, wethBalanceWithdrawn)
            );

            console2.log("Transferring withdrawn WETH to TRSRY v1.1");
            addToBatch(
                weth,
                abi.encodeWithSelector(ERC20.transfer.selector, treasuryV1_1, wethBalanceWithdrawn)
            );
        }

        // 6. Deploy an LP token for the pool using BunniManager
        {
            console2.log("Deploying LP token for Uniswap V3 OHM-wETH pool");
            addToBatch(
                bunniManager,
                abi.encodeWithSelector(BunniManager.deployPoolToken.selector, ohmWethUniV3Pool)
            );
        }

        // 7. Deposit liquidity into the pool using BunniManager
        //  The pool token shares are deposited into TRSRY
        {
            console2.log("Depositing liquidity into Uniswap V3 OHM-wETH pool");
            uint256 poolTokenAmount = abi.decode(
                addToBatch(
                    bunniManager,
                    abi.encodeWithSelector(
                        BunniManager.deposit.selector,
                        ohmWethUniV3Pool,
                        ohm,
                        ohmBalanceWithdrawn,
                        wethBalanceWithdrawn,
                        100 // 1%
                    )
                ),
                (uint256)
            );

            console2.log("    Pool token amount/liquidity is", poolTokenAmount);
        }

        // 8. Activate the LP token
        // This will also register the LP token with TRSRY, PRICE and SPPLY
        {
            console2.log("Activating LP token for Uniswap V3 OHM-wETH pool");
            addToBatch(
                bunniManager,
                abi.encodeWithSelector(
                    BunniManager.activatePoolToken.selector,
                    ohmWethUniV3Pool,
                    twapMaxDeviationBps,
                    twapObservationWindow
                )
            );
        }

        // ==================== SECTION 4: RBS v2 Activation ==================== //

        // This DAO MS batch:
        // 1. Activates Appraiser policy
        // 2. Activates Operator policy
        // 3. Activates Heart policy
        // 4. Sets operator address on bond callback
        // 5. Set roles for policy access control
        // 6. Initializes the operator policy

        // 1. Activate appraiser policy
        console2.log("Activating Appraiser policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, appraiser)
        );

        // 2. Activate new operator policy
        console2.log("Activating Operator policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                operatorV2
            )
        );

        // 3. Activate new heart policy
        console2.log("Activating Heart policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, heartV2)
        );

        // 4. Set operator address on bond callback
        console2.log("Setting operator address on bond callback");
        addToBatch(
            bondCallback,
            abi.encodeWithSelector(BondCallback.setOperator.selector, operatorV2)
        );

        // 5. Set roles for policy access control
        // Operator policy
        //     - Give Heart the operator_operate role
        console2.log("Granting operator_operate role for Operator policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("operator_operate"),
                heartV2
            )
        );

        // 6. Initialize the operator policy
        console2.log("Initializing Operator policy");
        addToBatch(operatorV2, abi.encodeWithSelector(Operator.initialize.selector));

        // 7. Test the output
        {
            console2.log(
                "    LBBO (18dp)",
                Appraiser(appraiser).getMetric(IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM)
            );
            console2.log("    Operator target price (18dp):", Operator(operatorV2).targetPrice());
        }

        // 8. Warp forward to beyond the next heartbeat and test the output again
        // This catches any issues with MA storage
        {
            uint48 warpBlock = uint48(block.timestamp + OlympusHeart(heart).frequency() + 1);
            console2.log("Warping forward to block %s", warpBlock);
            vm.warp(warpBlock);

            console2.log(
                "    Backing (18dp)",
                Appraiser(appraiser).getMetric(IAppraiser.Metric.BACKING)
            );
            console2.log(
                "    LBBO (18dp)",
                Appraiser(appraiser).getMetric(IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM)
            );
        }
    }

    /// @notice     Activates PRICEv2 module and PriceConfigV2 policy
    /// @dev        This is a very long, very ugly function as all of the components
    /// @dev        need to be completed in a single transaction/batch in order for
    /// @dev        RBS to upgrade and operate successfully.
    function RBSv2Install_3_1(bool send_) external isDaoBatch(send_) {
        install();
    }
}
