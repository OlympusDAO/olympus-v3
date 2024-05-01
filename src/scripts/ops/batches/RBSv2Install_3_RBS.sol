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
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ERC4626Price} from "modules/PRICE/submodules/feeds/ERC4626Price.sol";
import {UniswapV2PoolTokenPrice} from "modules/PRICE/submodules/feeds/UniswapV2PoolTokenPrice.sol";
import {UniswapV3Price} from "modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

// Bophades policies
import {Appraiser} from "policies/OCA/Appraiser.sol";
import {IAppraiser} from "policies/OCA/interfaces/IAppraiser.sol";
import {PriceConfigV2} from "policies/OCA/PriceConfig.v2.sol";
import {OlympusHeart} from "policies/RBS/Heart.sol";
import {Operator} from "policies/RBS/Operator.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {BondCallback} from "policies/Bonds/BondCallback.sol";
import {TreasuryConfig} from "policies/OCA/TreasuryConfig.sol";
import {SupplyConfig} from "policies/OCA/SupplyConfig.sol";

// Libraries
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// UniswapV3
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

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
    // address usdPerFxsPriceFeed;
    address ethPerBtcPriceFeed;
    address usdPerBtcPriceFeed;

    // Uniswap V3 Pools
    address daiWethUniV3Pool;
    // address btrflyWethUniV3Pool;
    address ohmWethUniV3Pool;

    // Allocators
    address veFXSAllocator;

    // New Olympus Contracts
    address priceV2;
    address chainlinkPriceFeeds;
    address erc4626Price;
    address uniswapV2PoolTokenPrice;
    address uniswapV3Price;
    address simplePriceFeedStrategy;

    address appraiser;
    address priceConfigV2;
    address heartV2;
    address operatorV2;
    address treasuryConfig;
    address supplyConfig;

    // Wallets
    address daoWorkingWallet;

    uint32 internal constant DEFAULT_RESERVE_TWAP_OBSERVATION_WINDOW = 30 days;
    uint32 internal constant DEFAULT_TWAP_OBSERVATION_WINDOW = 7 days;
    uint32 internal constant DEFAULT_CHAINLINK_UPDATE_THRESHOLD = 24 hours;
    uint32 internal constant DEFAULT_UNISWAPV3_TWAP_OBSERVATION_WINDOW = 24 hours;

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
        // usdPerFxsPriceFeed = envAddress("current", "external.chainlink.fxsUsdPriceFeed");
        ethPerBtcPriceFeed = envAddress("current", "external.chainlink.btcEthPriceFeed");
        usdPerBtcPriceFeed = envAddress("current", "external.chainlink.btcUsdPriceFeed");

        daiWethUniV3Pool = envAddress("current", "external.uniswapV3.DaiWethPool");
        // btrflyWethUniV3Pool = envAddress("current", "external.uniswapV3.BtrflyWethPool");
        ohmWethUniV3Pool = envAddress("current", "external.uniswapV3.OhmWethPool");

        veFXSAllocator = envAddress("current", "olympus.legacy.veFXSAllocator");

        priceV2 = envAddress("current", "olympus.modules.OlympusPriceV2");
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

        daoWorkingWallet = envAddress("current", "olympus.legacy.workingWallet");
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
        //     - Install ChainlinkPriceFeeds submodule
        //     - Install ERC4626Price submodule
        //     - Install UniswapV2PoolTokenPrice submodule
        //     - Install UniswapV3Price submodule
        //     - Install SimplePriceFeedStrategy submodule
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
        // Caution: the last observation time for the assets needs to be set in a way that it will not be stale (which would cause a revert)
        string memory argData = vm.readFile("./src/scripts/ops/batches/RBSv2Install_3_RBS.json");

        // 1. Configure WETH price feed and moving average data on PRICE
        // - Uses two data sources for redundancy:
        //   - Chainlink ETH-USD price feed
        //   - Chainlink BTC-ETH price feed divided by Chainlink BTC-USD price feed (which resolves to USD per ETH)
        //   - Three Chainlink feeds are used as the likelihood of all three breaking is low
        // - The price will be the average of the above two
        // - No moving average tracked or used
        // - This is first, as DAI relies on it
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

        // 2. Configure DAI price feed and moving average data on PRICE
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
                            observationWindowSeconds: DEFAULT_UNISWAPV3_TWAP_OBSERVATION_WINDOW
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

            // Already added as a moving average asset in Heart

            console2.log("    DAI price: %s (18 dp)", OlympusPricev2(priceV2).getPrice(dai));
        }

        // 3. Configure sDAI price feed and moving average data on PRICE
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

        // // 4. Configure veFXS price feed and moving average data on PRICE
        // // - Uses the Chainlink price feed with the standard observation window
        // // - Track and store the moving average, so that a broken price feed doesn't brick the system
        // {
        //     PRICEv2.Component[] memory veFXSFeeds = new PRICEv2.Component[](1);
        //     veFXSFeeds[0] = PRICEv2.Component(
        //         toSubKeycode("PRICE.CHAINLINK"),
        //         ChainlinkPriceFeeds.getOneFeedPrice.selector,
        //         abi.encode(
        //             ChainlinkPriceFeeds.OneFeedParams(
        //                 AggregatorV2V3Interface(usdPerFxsPriceFeed),
        //                 DEFAULT_CHAINLINK_UPDATE_THRESHOLD
        //             )
        //         )
        //     );

        //     uint256 fxsLastObsTime_ = argData.readUint(".fxsLastObsTime"); // Should be within the last 8 hours
        //     uint256[] memory fxsObs_ = argData.readUintArray(".fxsObs"); // 7 days * 24 hours / 8 hours = 21 observations

        //     console2.log("Adding veFXS price feed to PRICE");
        //     addToBatch(
        //         priceConfigV2,
        //         abi.encodeWithSelector(
        //             PriceConfigV2.addAssetPrice.selector,
        //             veFXS,
        //             true, // store moving average
        //             true, // use the moving average as part of price strategy
        //             DEFAULT_TWAP_OBSERVATION_WINDOW, // moving average duration
        //             fxsLastObsTime_, // needs to be > block.timestamp - observation frequency
        //             fxsObs_,
        //             PRICEv2.Component(
        //                 toSubKeycode("PRICE.SIMPLESTRATEGY"),
        //                 SimplePriceFeedStrategy.getAveragePrice.selector,
        //                 abi.encode(0)
        //             ),
        //             veFXSFeeds
        //         )
        //     );

        //     console2.log("    veFXS price: %s (18 dp)", OlympusPricev2(priceV2).getPrice(veFXS));
        // }

        // // 5. Configure FXS price feed and moving average data on PRICE
        // // - Uses the Chainlink price feed with the standard observation window
        // // - Track and store the moving average, so that a broken price feed doesn't brick the system
        // {
        //     PRICEv2.Component[] memory fxsFeeds = new PRICEv2.Component[](1);
        //     fxsFeeds[0] = PRICEv2.Component(
        //         toSubKeycode("PRICE.CHAINLINK"),
        //         ChainlinkPriceFeeds.getOneFeedPrice.selector,
        //         abi.encode(
        //             ChainlinkPriceFeeds.OneFeedParams(
        //                 AggregatorV2V3Interface(usdPerFxsPriceFeed),
        //                 DEFAULT_CHAINLINK_UPDATE_THRESHOLD
        //             )
        //         )
        //     );

        //     uint256 fxsLastObsTime_ = argData.readUint(".fxsLastObsTime"); // Should be within the last 8 hours
        //     uint256[] memory fxsObs_ = argData.readUintArray(".fxsObs"); // 7 days * 24 hours / 8 hours = 21 observations

        //     console2.log("Adding FXS price feed to PRICE");
        //     addToBatch(
        //         priceConfigV2,
        //         abi.encodeWithSelector(
        //             PriceConfigV2.addAssetPrice.selector,
        //             fxs,
        //             true, // store moving average
        //             true, // use the moving average as part of price strategy
        //             DEFAULT_TWAP_OBSERVATION_WINDOW, // moving average
        //             fxsLastObsTime_, // needs to be > block.timestamp - observation frequency
        //             fxsObs_,
        //             PRICEv2.Component(
        //                 toSubKeycode("PRICE.SIMPLESTRATEGY"),
        //                 SimplePriceFeedStrategy.getAveragePrice.selector,
        //                 abi.encode(0)
        //             ),
        //             fxsFeeds
        //         )
        //     );

        //     console2.log("    FXS price: %s (18 dp)", OlympusPricev2(priceV2).getPrice(fxs));
        // }

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
                        observationWindowSeconds: DEFAULT_UNISWAPV3_TWAP_OBSERVATION_WINDOW
                    })
                )
            );

            uint256 ohmLastObsTime_ = argData.readUint(".ohmLastObsTime"); // Should be within the last 8 hours
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

            // Already added as a moving average asset in Heart

            console2.log("    OHM price: %s (9 dp)", OlympusPricev2(priceV2).getPrice(ohm));
        }

        // // 7. Configure BTRFLY on PRICE
        // // - Uses a Uniswap V3 TWAP with the configured observation window
        // // - Does not require an internal moving average, as the Uniswap V3 is resilient
        // {
        //     PRICEv2.Component[] memory btrflyFeeds = new PRICEv2.Component[](1);
        //     btrflyFeeds[0] = PRICEv2.Component(
        //         toSubKeycode("PRICE.UNIV3"),
        //         UniswapV3Price.getTokenTWAP.selector,
        //         abi.encode(
        //             UniswapV3Price.UniswapV3Params({
        //                 pool: IUniswapV3Pool(btrflyWethUniV3Pool),
        //                 observationWindowSeconds: DEFAULT_UNISWAPV3_TWAP_OBSERVATION_WINDOW
        //             })
        //         )
        //     );

        //     uint256 btrflyLastObsTime_ = 0;
        //     uint256[] memory btrflyObs_ = new uint256[](0);

        //     console2.log("Adding BTRFLY price feed to PRICE");
        //     addToBatch(
        //         priceConfigV2,
        //         abi.encodeWithSelector(
        //             PriceConfigV2.addAssetPrice.selector,
        //             btrfly,
        //             false, // store moving average
        //             false, // use the moving average as part of price strategy
        //             0,
        //             btrflyLastObsTime_,
        //             btrflyObs_,
        //             PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
        //             btrflyFeeds
        //         )
        //     );

        //     console2.log("    BTRFLY price: %s (18 dp)", OlympusPricev2(priceV2).getPrice(btrfly));
        // }

        // ==================== SECTION 3: RBS v2 Activation ==================== //

        // This DAO MS batch:
        // 1. Activates Appraiser policy
        // 2. Activates Operator policy
        // 3. Activates Heart policy
        // 4. Add DAO MS to the Appraiser role
        // 5. Configure metric moving average assets on Heart
        // 6. Sets operator address on bond callback
        // 7. Set roles for policy access control
        // 8. Initializes the operator policy
        // 9. Test the output

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

        // 2a. Set the target price on the Operator
        {
            // Sourced from: https://etherscan.io/address/0xd6C4D723fdadCf0D171eF9A2a3Bfa870675b282f#readContract#F8
            uint256 operatorTargetPrice = argData.readUint(".operatorTargetPrice");

            console2.log("Setting target price on Operator to: %s (18dp)", operatorTargetPrice);
            addToBatch(
                operatorV2,
                abi.encodeWithSelector(Operator.setManualTargetPrice.selector, operatorTargetPrice)
            );
        }

        // 3. Activate new heart policy
        console2.log("Activating Heart policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, heartV2)
        );

        // 4. Add DAO MS to the Appraiser role
        {
            //      - Give DAO MS the appraiser_admin role
            console2.log("Granting appraiser_admin role for Appraiser policy to DAO MS");
            addToBatch(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("appraiser_admin"),
                    daoMS
                )
            );
        }

        // 5. Configure metric moving average assets on Heart
        //  - 30 days
        {
            uint32 movingAverageDuration = uint32(30 days);
            uint256 lastObsTime_ = argData.readUint(".lbboLastObsTime"); // Should be within the last 8 hours
            uint256[] memory obs_ = argData.readUintArray(".lbboObs"); // 30 days * 24 hours / 8 hours = 90 observations

            console2.log("Configure LBBO moving average on Appraiser");
            addToBatch(
                appraiser,
                abi.encodeWithSelector(
                    Appraiser.updateMetricMovingAverage.selector,
                    IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
                    movingAverageDuration,
                    uint48(lastObsTime_),
                    obs_
                )
            );
        }

        // 6. Set operator address on bond callback
        console2.log("Setting operator address on bond callback");
        addToBatch(
            bondCallback,
            abi.encodeWithSelector(BondCallback.setOperator.selector, operatorV2)
        );

        // 7. Set roles for policy access control
        // Operator policy
        //     - Give Heart the operator_operate role
        console2.log("Granting operator_operate role for Operator policy to Heart");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("operator_operate"),
                heartV2
            )
        );
        // Appraiser policy
        //      - Give Heart the appraiser_store role
        console2.log("Granting appraiser_store role for Appraiser policy to Heart");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("appraiser_store"),
                heartV2
            )
        );

        // 8. Initialize the operator policy
        console2.log("Initializing Operator policy");
        addToBatch(operatorV2, abi.encodeWithSelector(Operator.initialize.selector));

        // 9. Test the output
        {
            console2.log(
                "    LBBO (18dp)",
                Appraiser(appraiser).getMetric(IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM)
            );

            (uint256 lbbo, ) = Appraiser(appraiser).getMetric(
                IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM,
                IAppraiser.Variant.MOVINGAVERAGE
            );
            console2.log("    LBBO Moving Average (18dp)", lbbo);
            console2.log("    Operator target price (18dp):", Operator(operatorV2).targetPrice());
        }
    }

    /// @notice     Activates PRICEv2 module and PriceConfigV2 policy
    /// @dev        This is a very long, very ugly function as all of the components
    /// @dev        need to be completed in a single transaction/batch in order for
    /// @dev        RBS to upgrade and operate successfully.
    function RBSv2Install_3_1(bool send_) external isDaoBatch(send_) {
        install();
    }

    function RBSv2Install_3_TEST(bool) external {
        initTestBatch();
        install();
    }
}
