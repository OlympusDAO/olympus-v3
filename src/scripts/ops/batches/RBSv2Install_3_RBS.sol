// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import "src/Kernel.sol";

// Bophades modules
import {OlympusPrice} from "modules/PRICE/OlympusPrice.sol";
import "modules/PRICE/OlympusPrice.v2.sol";
import {Category as AssetCategory} from "modules/TRSRY/TRSRY.v1.sol";

// PRICE submodules
import {BalancerPoolTokenPrice} from "modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";
import {BunniPrice} from "modules/PRICE/submodules/feeds/BunniPrice.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ERC4626Price} from "modules/PRICE/submodules/feeds/ERC4626Price.sol";
import {UniswapV2PoolTokenPrice} from "modules/PRICE/submodules/feeds/UniswapV2PoolTokenPrice.sol";
import {UniswapV3Price} from "modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

// Bophades policies
import {Appraiser} from "policies/OCA/Appraiser.sol";
import {Bookkeeper} from "policies/OCA/Bookkeeper.sol";
import {OlympusHeart} from "policies/RBS/Heart.sol";
import {Operator} from "policies/RBS/Operator.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {BondCallback} from "policies/Bonds/BondCallback.sol";
import {BunniManager} from "policies/UniswapV3/BunniManager.sol";

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
contract RBSv2Install_3 is OlyBatch {
    // Existing Olympus Contracts
    address kernel;
    address price;
    address heart;
    address operator;
    address rolesAdmin;
    address bondCallback;
    address treasuryCustodian;
    address priceConfig;

    // Tokens
    address ohm;
    address dai;
    address sdai;
    address weth;
    address veFXS;
    address fxs;
    address usdc;

    // Price Feeds
    address ohmEthPriceFeed;
    address ethUsdPriceFeed;
    address daiEthPriceFeed;
    address daiUsdPriceFeed;
    address fxsUsdPriceFeed;
    address usdcUsdPriceFeed;

    // Uniswap V3 Pools
    address daiUsdcUniV3Pool;
    address wethUsdcUniV3Pool;

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
    address balancerPoolTokenPrice;
    address bunniPrice;
    address chainlinkPriceFeeds;
    address erc4626Price;
    address uniswapV2PoolTokenPrice;
    address uniswapV3Price;
    address simplePriceFeedStrategy;
    address appraiser;
    address bookkeeper;
    address newHeart;
    address newOperator;
    address bunniManager;
    address bunniLens;

    // Wallets
    address daoWorkingWallet;

    uint32 internal constant DEFAULT_TWAP_OBSERVATION_WINDOW = 7 days;

    function loadEnv() internal override {
        kernel = envAddress("current", "olympus.Kernel");
        price = envAddress("current", "olympus.modules.OlympusPriceV1");
        heart = envAddress("last", "olympus.policies.OlympusHeart");
        operator = envAddress("last", "olympus.policies.Operator");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        bondCallback = envAddress("current", "olympus.policies.BondCallback");
        treasuryCustodian = envAddress("current", "olympus.policies.TreasuryCustodian");
        priceConfig = envAddress("current", "olympus.policies.OlympusPriceConfig");

        ohm = envAddress("current", "olympus.legacy.OHM");
        dai = envAddress("current", "external.tokens.DAI");
        sdai = envAddress("current", "external.tokens.sDAI");

        ohmEthPriceFeed = envAddress("current", "external.chainlink.ohmEthPriceFeed");
        ethUsdPriceFeed = envAddress("current", "external.chainlink.ethUsdPriceFeed");
        daiEthPriceFeed = envAddress("current", "external.chainlink.daiEthPriceFeed");
        daiUsdPriceFeed = envAddress("current", "external.chainlink.daiUsdPriceFeed");
        fxsUsdPriceFeed = envAddress("current", "external.chainlink.fxsUsdPriceFeed");
        usdcUsdPriceFeed = envAddress("current", "external.chainlink.usdcUsdPriceFeed");

        daiUsdcUniV3Pool = envAddress("current", "external.uniswapV3.DaiUsdcPool");
        wethUsdcUniV3Pool = envAddress("current", "external.uniswapV3.WethUsdcPool");
        ohmWethUniV3Pool = envAddress("current", "external.uniswapV3.OhmWethPool");
        ohmWethTokenId = envUint("current", "external.UniswapV3LegacyPOL.OhmWethTokenId");
        ohmWethTickLower = int24(envInt("current", "external.UniswapV3LegacyPOL.OhmWethTickLower"));
        ohmWethTickUpper = int24(envInt("current", "external.UniswapV3LegacyPOL.OhmWethTickUpper"));
        positionManager = envAddress(
            "current",
            "external.UniswapV3LegacyPOL.NonfungiblePositionManager"
        );

        twapMaxDeviationBps = uint16(envUint("current", "external.Bunni.TwapMaxDeviationBps"));
        twapObservationWindow = uint32(envUint("current", "external.Bunni.TwapObservationWindow"));

        veFXSAllocator = envAddress("current", "olympus.legacy.veFXSAllocator");

        priceV2 = envAddress("current", "olympus.modules.OlympusPriceV2");
        balancerPoolTokenPrice = envAddress(
            "current",
            "olympus.submodules.PRICE.BalancerPoolTokenPrice"
        );
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
        bookkeeper = envAddress("current", "olympus.policies.Bookkeeper");
        newHeart = envAddress("current", "olympus.policies.OlympusHeart");
        newOperator = envAddress("current", "olympus.policies.Operator");
        bunniManager = envAddress("current", "olympus.policies.BunniManager");

        daoWorkingWallet = envAddress("current", "olympus.legacy.workingWallet");
    }

    /// @notice     Activates PRICEv2 module and BookKeeper policy
    function RBSv2Install_3_1(bool send_) external isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. deactivates old heart + operator policies at contract level
        // 2. deactivates old heart + operator policies at kernel level
        // 3. upgrades the PRICE module to v2
        // 4. activates bookkeeper policy
        // 5. sets roles for new policy access control
        // 6. installs submodules on price v2

        // 1. Deactivate old heart + operator policies at contract level
        addToBatch(heart, abi.encodeWithSelector(OlympusHeart.deactivate.selector));
        addToBatch(operator, abi.encodeWithSelector(Operator.deactivate.selector));

        // 2. Deactivate old heart + operator policies at kernel level
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.DeactivatePolicy, heart)
        );
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
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.UpgradeModule, priceV2)
        );

        // 5. Activate bookkeeper policy
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                bookkeeper
            )
        );

        // 5a. Disable TreasuryCustodian policy (superseded by BookKeeper)
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                treasuryCustodian
            )
        );

        // 5b. Disable PriceConfig policy (superseded by BookKeeper)
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                priceConfig
            )
        );

        // 8. Set roles for new policy access control
        // Bookkeeper policy
        //     - Give DAO MS the bookkeeper_admin role
        //     - Give DAO MS the bookkeeper_policy role
        //     - Give Policy MS the bookkeeper_policy role
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("bookkeeper_admin"),
                daoMS
            )
        );
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("bookkeeper_policy"),
                daoMS
            )
        );
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("bookkeeper_policy"),
                policyMS
            )
        );

        // 9. Install submodules on price v2
        //     - Install BalancerPoolTokenPrice submodule
        //     - Install BunniPrice submodule
        //     - Install ChainlinkPriceFeeds submodule
        //     - Install ERC4626Price submodule
        //     - Install UniswapV2PoolTokenPrice submodule
        //     - Install UniswapV3Price submodule
        //     - Install SimplePriceFeedStrategy submodule
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, balancerPoolTokenPrice)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, bunniPrice)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, chainlinkPriceFeeds)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, erc4626Price)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, uniswapV2PoolTokenPrice)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, uniswapV3Price)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, simplePriceFeedStrategy)
        );
    }

    /// @notice     Configures PRICEv2 module and TRSRY assets
    function RBSv2Install_3_2(
        bool send_,
        uint256[] memory daiObs_,
        uint48 daiLastObsTime_,
        uint256[] memory wethObs_,
        uint48 wethLastObsTime_,
        uint256[] memory usdcObs_,
        uint48 usdcLastObsTime_
    ) public isPolicyBatch(send_) {
        // This Policy MS batch:
        // 1. Configures DAI on PRICE
        // 2. Configures sDAI on PRICE
        // 3. Configure WETH on PRICE
        // 4. Configure veFXS on PRICE
        // 5. Configure FXS on PRICE
        // 6. Configure USDC on PRICE
        // 7. Configure OHM on PRICE
        // 7. Add and categorize DAI in TRSRY
        // 8. Add and categorize sDAI in TRSRY
        // 9. Add and categorize WETH in TRSRY
        // 10. Add and categorize veFXS in TRSRY
        // 11. Add and categorize FXS in TRSRY

        // 1. Configure DAI price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        // - Uses the Uniswap V3 pool TWAP with the configured observation window
        // - Configures PRICE to track a moving average
        // - The price will be the average of the above three
        {
            PRICEv2.Component[] memory daiFeeds = new PRICEv2.Component[](2);
            {
                daiFeeds[0] = PRICEv2.Component(
                    toSubKeycode("PRICE.CHAINLINK"),
                    ChainlinkPriceFeeds.getOneFeedPrice.selector,
                    abi.encode(
                        ChainlinkPriceFeeds.OneFeedParams(
                            AggregatorV2V3Interface(daiUsdPriceFeed),
                            DEFAULT_TWAP_OBSERVATION_WINDOW
                        )
                    )
                );
                daiFeeds[1] = PRICEv2.Component(
                    toSubKeycode("PRICE.UNIV3"),
                    UniswapV3Price.getTokenTWAP.selector,
                    abi.encode(
                        UniswapV3Price.UniswapV3Params({
                            pool: IUniswapV3Pool(daiUsdcUniV3Pool),
                            observationWindowSeconds: twapObservationWindow, // This is shorter, as it is compared against reserves
                            maxDeviationBps: twapMaxDeviationBps
                        })
                    )
                );
            }

            addToBatch(
                bookkeeper,
                abi.encodeWithSelector(
                    Bookkeeper.addAssetPrice.selector,
                    dai,
                    true, // store moving average
                    true, // use the moving average as part of price strategy
                    DEFAULT_TWAP_OBSERVATION_WINDOW, // moving average window
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
            addToBatch(
                bookkeeper,
                abi.encodeWithSelector(
                    Bookkeeper.addAssetPrice.selector,
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
        }

        // 3. Configure WETH price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        // - Uses the Uniswap V3 pool TWAP with the configured observation window
        // - Configures PRICE to track a moving average
        // - The price will be the average of the above three
        {
            PRICEv2.Component[] memory wethFeeds = new PRICEv2.Component[](2);
            wethFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(ethUsdPriceFeed),
                        DEFAULT_TWAP_OBSERVATION_WINDOW
                    )
                )
            );
            wethFeeds[1] = PRICEv2.Component(
                toSubKeycode("PRICE.UNIV3"),
                UniswapV3Price.getTokenTWAP.selector,
                abi.encode(
                    UniswapV3Price.UniswapV3Params({
                        pool: IUniswapV3Pool(wethUsdcUniV3Pool),
                        observationWindowSeconds: twapObservationWindow, // This is shorter, as it is compared against reserves
                        maxDeviationBps: twapMaxDeviationBps
                    })
                )
            );
            addToBatch(
                bookkeeper,
                abi.encodeWithSelector(
                    Bookkeeper.addAssetPrice.selector,
                    weth,
                    true, // store moving average
                    true, // use the moving average as part of price strategy
                    DEFAULT_TWAP_OBSERVATION_WINDOW, // moving average
                    wethLastObsTime_,
                    wethObs_,
                    PRICEv2.Component(
                        toSubKeycode("PRICE.SIMPLESTRATEGY"),
                        SimplePriceFeedStrategy.getAveragePrice.selector,
                        abi.encode(0)
                    ),
                    wethFeeds
                )
            );
        }

        // 4. Configure veFXS price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        {
            uint256[] memory veFXSObs_ = new uint256[](0);
            PRICEv2.Component[] memory veFXSFeeds = new PRICEv2.Component[](1);
            veFXSFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(fxsUsdPriceFeed),
                        DEFAULT_TWAP_OBSERVATION_WINDOW
                    )
                )
            );
            addToBatch(
                bookkeeper,
                abi.encodeWithSelector(
                    Bookkeeper.addAssetPrice.selector,
                    veFXS,
                    false, // don't store moving average
                    false, // don't use the moving average as part of price strategy
                    0, // moving average
                    0,
                    veFXSObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    veFXSFeeds
                )
            );
        }

        // 5. Configure FXS price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        {
            uint256[] memory fxsObs_ = new uint256[](0);
            PRICEv2.Component[] memory fxsFeeds = new PRICEv2.Component[](1);
            fxsFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(fxsUsdPriceFeed),
                        DEFAULT_TWAP_OBSERVATION_WINDOW
                    )
                )
            );
            addToBatch(
                bookkeeper,
                abi.encodeWithSelector(
                    Bookkeeper.addAssetPrice.selector,
                    fxs,
                    false, // don't store moving average
                    false, // don't use the moving average as part of price strategy
                    0, // moving average
                    0,
                    fxsObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    fxsFeeds
                )
            );
        }

        // 6. Configure USDC price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        // - Configures PRICE to track a moving average
        // - The price will be the average of the above two
        {
            PRICEv2.Component[] memory usdcFeeds = new PRICEv2.Component[](1);
            usdcFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(usdcUsdPriceFeed),
                        DEFAULT_TWAP_OBSERVATION_WINDOW
                    )
                )
            );
            addToBatch(
                bookkeeper,
                abi.encodeWithSelector(
                    Bookkeeper.addAssetPrice.selector,
                    usdc,
                    true, // store moving average
                    true, // use the moving average as part of price strategy
                    DEFAULT_TWAP_OBSERVATION_WINDOW, // moving average
                    usdcLastObsTime_,
                    usdcObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    usdcFeeds
                )
            );
        }

        // 7. Configure OHM on PRICE
        // - Uses a TWAP from the Uniswap V3 pool with the configured observation window
        {
            PRICEv2.Component[] memory ohmFeeds = new PRICEv2.Component[](1);
            ohmFeeds[1] = PRICEv2.Component(
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

            addToBatch(
                bookkeeper,
                abi.encodeWithSelector(
                    Bookkeeper.addAssetPrice.selector,
                    ohm,
                    false, // store moving average
                    false, // use the moving average as part of price strategy
                    0, // moving average
                    0,
                    0,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    ohmFeeds
                )
            );
        }

        // 7. Add and categorize DAI on Bookkeeper
        //      - liquid, stable, reserves
        //      - Clearinghouse policies use the debt functionality, so don't need to be explicitly added
        address[] memory locations = new address[](2);
        locations[0] = daoWorkingWallet;
        locations[1] = daoMS;
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.addAsset.selector, dai, locations)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                dai,
                AssetCategory.wrap("liquid")
            )
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                dai,
                AssetCategory.wrap("stable")
            )
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                dai,
                AssetCategory.wrap("reserves")
            )
        );

        // 8. Add and categorize sDAI on Bookkeeper
        //      - liquid, stable, reserves
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.addAsset.selector, sdai, locations)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                sdai,
                AssetCategory.wrap("liquid")
            )
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                sdai,
                AssetCategory.wrap("stable")
            )
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                sdai,
                AssetCategory.wrap("reserves")
            )
        );

        // 9. Add and categorize WETH
        //      - liquid, volatile, strategic
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.addAsset.selector, weth, locations)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                weth,
                AssetCategory.wrap("liquid")
            )
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                weth,
                AssetCategory.wrap("volatile")
            )
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                weth,
                AssetCategory.wrap("strategic")
            )
        );

        // 10. Add and categorize veFXS
        //      - illiquid, volatile, strategic
        address[] memory veFXSLocations = new address[](3);
        veFXSLocations[0] = veFXSAllocator;
        veFXSLocations[1] = daoMS;
        veFXSLocations[2] = daoWorkingWallet;
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.addAsset.selector, veFXS, veFXSLocations)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                veFXS,
                AssetCategory.wrap("illiquid")
            )
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                veFXS,
                AssetCategory.wrap("volatile")
            )
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                veFXS,
                AssetCategory.wrap("strategic")
            )
        );

        // 11. Add and categorize FXS
        //      - illiquid, volatile, strategic
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.addAsset.selector, fxs, veFXSLocations)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                fxs,
                AssetCategory.wrap("liquid")
            )
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                fxs,
                AssetCategory.wrap("volatile")
            )
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.categorizeAsset.selector,
                fxs,
                AssetCategory.wrap("strategic")
            )
        );
    }

    /// @notice     Configures protocol owned liquidity
    function RBSv2Install_3_3(bool send_) public isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. Sets the BunniLens variable on the BunniManager policy
        // 2. Activates the BunniManager policy
        // 3. Withdraws liquidity from the existing Uniswap V3 pool
        // 4. Deploys an LP token for pool
        // 5. Deposits liquidity into the poll
        // 6. Activates the LP token
        // 7. Set roles for policy access control (bunni_admin)

        // 1. Sets the BunniLens variable on the BunniManager policy
        // This cannot be performed at deployment-time
        addToBatch(
            bunniManager,
            abi.encodeWithSelector(BunniManager.setBunniLens.selector, bunniLens)
        );

        // 2. Activate the BunniManager policy
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                bunniManager
            )
        );

        // 3. Withdraw liquidity from the existing Uniswap V3 pool
        uint256 ohmBalance;
        uint256 wethBalance;
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

            // Withdraw liquidity (which should also collect fees)
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

                (uint256 amount0, uint256 amount1) = abi.decode(
                    addToBatch(
                        positionManager,
                        abi.encodeWithSelector(
                            INonfungiblePositionManager.decreaseLiquidity.selector,
                            decreaseLiquidityParams
                        )
                    ),
                    (uint256, uint256)
                );
                ohmBalance += ohmIndex == 0 ? amount0 : amount1;
                wethBalance += ohmIndex == 0 ? amount1 : amount0;
            }

            console2.log("Withdrawn OHM balance (9dp) is", ohmBalance);
            console2.log("Withdrawn WETH balance (18dp) is", wethBalance);
        }

        // 4. Deploy an LP token for the pool using BunniManager
        {
            addToBatch(
                bunniManager,
                abi.encodeWithSelector(BunniManager.deployPoolToken.selector, ohmWethUniV3Pool)
            );
        }

        // 5. Deposit liquidity into the pool using BunniManager
        {
            uint256 poolTokenAmount = abi.decode(
                addToBatch(
                    bunniManager,
                    abi.encodeWithSelector(
                        BunniManager.deposit.selector,
                        ohmWethUniV3Pool,
                        ohm,
                        ohmBalance,
                        wethBalance,
                        100 // 1%
                    )
                ),
                (uint256)
            );

            console2.log("Pool token amount is", poolTokenAmount);
        }

        // 6. Activate the LP token
        // This will also register the LP token with TRSRY, PRICE and SPPLY
        {
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

        // 7. Set roles for policy access control
        // BunniManager policy
        //     - Give DAO MS the bunni_admin role
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("bunni_admin"), daoMS)
        );
    }

    /// @notice     Activates RBS (Appraiser, Heart, Operator)
    function RBSv2Install_3_4(bool send_) public isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. Activates Appraiser policy
        // 2. Activates Operator policy
        // 3. Activates Heart policy
        // 4. Sets operator address on bond callback
        // 5. Set roles for policy access control
        // 6. Initializes the operator policy

        // 1. Activate appraiser policy
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, appraiser)
        );

        // 2. Activate new operator policy
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                newOperator
            )
        );

        // 3. Activate new heart policy
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, newHeart)
        );

        // 4. Set operator address on bond callback
        addToBatch(
            bondCallback,
            abi.encodeWithSelector(BondCallback.setOperator.selector, newOperator)
        );

        // 5. Set roles for policy access control
        // Operator policy
        //     - Give Heart the operator_operate role
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("operator_operate"),
                newHeart
            )
        );

        // 6. Initialize the operator policy
        addToBatch(newOperator, abi.encodeWithSelector(Operator.initialize.selector));
    }
}
