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

// TODO check for batches relying on previous state

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

    // Uniswap Pools
    address daiUsdcPool;
    address wethUsdcPool;
    address ohmWethPool;
    uint256 ohmWethTokenId;

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

    // Wallets
    address daoWorkingWallet;

    function loadEnv() internal override {
        kernel = envAddress("current", "olympus.Kernel");
        price = envAddress("current", "olympus.modules.OlympusPriceV1");
        heart = envAddress("last", "olympus.policies.OlympusHeart");
        operator = envAddress("last", "olympus.policies.Operator");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        bondCallback = envAddress("current", "olympus.policies.BondCallback");
        treasuryCustodian = envAddress("current", "olympus.policies.TreasuryCustodian");

        ohm = envAddress("current", "olympus.legacy.OHM");
        dai = envAddress("current", "external.tokens.DAI");
        sdai = envAddress("current", "external.tokens.sDAI");

        ohmEthPriceFeed = envAddress("current", "external.chainlink.ohmEthPriceFeed");
        ethUsdPriceFeed = envAddress("current", "external.chainlink.ethUsdPriceFeed");
        daiEthPriceFeed = envAddress("current", "external.chainlink.daiEthPriceFeed");
        daiUsdPriceFeed = envAddress("current", "external.chainlink.daiUsdPriceFeed");
        fxsUsdPriceFeed = envAddress("current", "external.chainlink.fxsUsdPriceFeed");
        usdcUsdPriceFeed = envAddress("current", "external.chainlink.usdcUsdPriceFeed");

        daiUsdcPool = envAddress("current", "external.uniswapV3.DaiUsdcPool");
        wethUsdcPool = envAddress("current", "external.uniswapV3.WethUsdcPool");
        ohmWethPool = envAddress("current", "external.uniswapV3.OhmWethPool");
        ohmWethTokenId = envUint("current", "external.uniswapV3.OhmWethTokenId");

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
        // 1. Configures DAI price feed and moving average data on PRICE
        // 2. Configures sDAI price feed and moving average data on PRICE
        // 3. Configure WETH price feed and moving average data on PRICE
        // 4. Configure veFXS price feed and moving average data on PRICE
        // 5. Configure FXS price feed and moving average data on PRICE
        // 6. Configure USDC price feed and moving average data on PRICE
        // 7. Add and categorize DAI in TRSRY
        // 8. Add and categorize sDAI in TRSRY
        // 9. Add and categorize WETH in TRSRY
        // 10. Add and categorize veFXS in TRSRY
        // 11. Add and categorize FXS in TRSRY

        // OHM not needed - BunniManager will handle this

        // 1. Configure DAI price feed and moving average data on PRICE
        {
            PRICEv2.Component[] memory daiFeeds = new PRICEv2.Component[](2);
            {
                daiFeeds[0] = PRICEv2.Component(
                    toSubKeycode("PRICE.CHAINLINK"),
                    ChainlinkPriceFeeds.getOneFeedPrice.selector,
                    abi.encode(
                        ChainlinkPriceFeeds.OneFeedParams(
                            AggregatorV2V3Interface(daiUsdPriceFeed),
                            uint48(24 hours)
                        )
                    )
                );
                daiFeeds[1] = PRICEv2.Component(
                    toSubKeycode("PRICE.UNIV3"),
                    UniswapV3Price.getTokenTWAP.selector,
                    abi.encode(daiUsdcPool, 18, "")
                );
            }

            addToBatch(
                bookkeeper,
                abi.encodeWithSelector(
                    Bookkeeper.addAssetPrice.selector,
                    dai,
                    true, // store moving average
                    true, // use the moving average as part of price strategy
                    uint32(30 days), // 30 day moving average
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
        {
            uint256[] memory sdaiObs_ = new uint256[](0);
            PRICEv2.Component[] memory sdaiFeeds = new PRICEv2.Component[](1);
            sdaiFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.ERC4626"),
                ERC4626Price.getPriceFromUnderlying.selector,
                abi.encode(sdai, ERC20(sdai).decimals(), "")
            );
            addToBatch(
                bookkeeper,
                abi.encodeWithSelector(
                    Bookkeeper.addAssetPrice.selector,
                    sdai,
                    false, // don't store moving average
                    false, // don't use the moving average as part of price strategy
                    0, // 30 day moving average
                    0,
                    sdaiObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    sdaiFeeds
                )
            );
        }

        // 3. Configure WETH price feed and moving average data on PRICE
        {
            PRICEv2.Component[] memory wethFeeds = new PRICEv2.Component[](2);
            wethFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(ethUsdPriceFeed),
                        uint48(24 hours)
                    )
                )
            );
            wethFeeds[1] = PRICEv2.Component(
                toSubKeycode("PRICE.UNIV3"),
                UniswapV3Price.getTokenTWAP.selector,
                abi.encode(wethUsdcPool, 18, "")
            );
            addToBatch(
                bookkeeper,
                abi.encodeWithSelector(
                    Bookkeeper.addAssetPrice.selector,
                    weth,
                    true, // store moving average
                    true, // use the moving average as part of price strategy
                    uint32(30 days), // 30 day moving average
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
        {
            uint256[] memory veFXSObs_ = new uint256[](0);
            PRICEv2.Component[] memory veFXSFeeds = new PRICEv2.Component[](1);
            veFXSFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(fxsUsdPriceFeed),
                        uint48(24 hours)
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
                    0, // 30 day moving average
                    0,
                    veFXSObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    veFXSFeeds
                )
            );
        }

        // 5. Configure FXS price feed and moving average data on PRICE
        {
            uint256[] memory fxsObs_ = new uint256[](0);
            PRICEv2.Component[] memory fxsFeeds = new PRICEv2.Component[](1);
            fxsFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(fxsUsdPriceFeed),
                        uint48(24 hours)
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
                    0, // 30 day moving average
                    0,
                    fxsObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    fxsFeeds
                )
            );
        }

        // 6. Configure USDC price feed and moving average data on PRICE
        {
            PRICEv2.Component[] memory usdcFeeds = new PRICEv2.Component[](1);
            usdcFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(usdcUsdPriceFeed),
                        uint48(24 hours)
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
                    uint32(30 days), // 30 day moving average
                    usdcLastObsTime_,
                    usdcObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    usdcFeeds
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
        //      - liquid, volatile
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

        // 10. Add and categorize veFXS
        //      - illiquid, volatile
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

        // 11. Add and categorize FXS
        //      - illiquid, volatile
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
    }

    /// @notice     Configures protocol owned liquidity
    function RBSv2Install_3_3(
        bool send_
    ) public isDAOBatch(send_) {
        // This DAO MS batch:
        // 1. Activates the BunniManager policy
        // 2. Withdraws liquidity from the existing Uniswap V3 pool
        // 3. Deploys an LP token for pool
        // 4. Deposits liquidity into the poll
        // 5. Activates the LP token
        // 6. Set roles for policy access control (bunni_admin)

        // 1. Activate the BunniManager policy
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, bunniManager)
        );

        // 2. Withdraw liquidity from the existing Uniswap V3 pool
        uint256 ohmBalance;
        uint256 wethBalance;
        {
            // Get the current OHM and wETH balances
            uint256 prevOhmBalance = ERC20(ohm).balanceOf(daoMS);
            uint256 prevWethBalance = ERC20(weth).balanceOf(daoMS);

            // Collect fees

            // Withdraw liquidity

            // Get the new OHM and wETH balances
            // TODO can't get these in the same function?
        }
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
