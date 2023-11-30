// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import "src/Kernel.sol";
import {OlympusPrice} from "modules/PRICE/OlympusPrice.sol";
import "modules/PRICE/OlympusPrice.v2.sol";
import {BalancerPoolTokenPrice} from "modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";
import {BunniPrice} from "modules/PRICE/submodules/feeds/BunniPrice.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ERC4626Price} from "modules/PRICE/submodules/feeds/ERC4626Price.sol";
import {UniswapV2PoolTokenPrice} from "modules/PRICE/submodules/feeds/UniswapV2PoolTokenPrice.sol";
import {UniswapV3Price} from "modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {Appraiser} from "policies/OCA/Appraiser.sol";
import {Bookkeeper} from "policies/OCA/Bookkeeper.sol";
import {OlympusHeart} from "policies/RBS/Heart.sol";
import {Operator} from "policies/RBS/Operator.sol";
import {PriceConfig} from "policies/RBS/PriceConfig.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {BondCallback} from "policies/Bonds/BondCallback.sol";
import {BunniManager} from "policies/UniswapV3/BunniManager.sol";

contract RBSv2Install_3 is OlyBatch {
    // Existing Olympus Contracts
    address kernel;
    address price;
    address heart;
    address operator;
    address priceConfig;
    address rolesAdmin;
    address bondCallback;
    address clearinghouse;

    // Tokens
    address ohm;
    address dai;
    address sdai;
    address polBunni;
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
    address ohmDaiPool;

    // Allocators
    address veFXSAllocator;

    // BLV
    address blvLido;
    address blvLusd;

    // Other
    address daoWorkingWallet;

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

    function loadEnv() internal override {
        kernel = envAddress("current", "olympus.Kernel");
        price = envAddress("current", "olympus.modules.OlympusPriceV1");
        heart = envAddress("last", "olympus.policies.OlympusHeart");
        operator = envAddress("last", "olympus.policies.Operator");
        priceConfig = envAddress("current", "olympus.policies.PriceConfig");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        bondCallback = envAddress("current", "olympus.policies.BondCallback");
        clearinghouse = envAddress("current", "olympus.policies.Clearinghouse");

        ohm = envAddress("current", "olympus.legacy.OHM");
        dai = envAddress("current", "external.tokens.DAI");
        sdai = envAddress("current", "external.tokens.sDAI");
        polBunni = envAddress("current", "external.tokens.polBunni");

        ohmEthPriceFeed = envAddress("current", "external.chainlink.ohmEthPriceFeed");
        ethUsdPriceFeed = envAddress("current", "external.chainlink.ethUsdPriceFeed");
        daiEthPriceFeed = envAddress("current", "external.chainlink.daiEthPriceFeed");
        daiUsdPriceFeed = envAddress("current", "external.chainlink.daiUsdPriceFeed");
        fxsUsdPriceFeed = envAddress("current", "external.chainlink.fxsUsdPriceFeed");
        usdcUsdPriceFeed = envAddress("current", "external.chainlink.usdcUsdPriceFeed");

        daiUsdcPool = envAddress("current", "external.uniswapV3.DaiUsdcPool");
        wethUsdcPool = envAddress("current", "external.uniswapV3.WethUsdcPool");
        ohmDaiPool = envAddress("current", "external.uniswapV2.OhmDaiPool");

        veFXSAllocator = envAddress("current", "olympus.legacy.veFXSAllocator");

        blvLido = envAddress("current", "olympus.policies.BLVaultManagerLido");
        blvLusd = envAddress("current", "olympus.policies.BLVaultManagerLusd");

        daoWorkingWallet = envAddress("current", "olympus.legacy.workingWallet");

        priceV2 = envAddress("current", "olympus.modules.OlympusPriceV2");
        balancerPoolTokenPrice = envAddress("current", "olympus.submodules.PRICE.BalancerPoolTokenPrice");
        bunniPrice = envAddress("current", "olympus.submodules.PRICE.BunniPrice");
        chainlinkPriceFeeds = envAddress("current", "olympus.submodules.PRICE.ChainlinkPriceFeeds");
        erc4626Price = envAddress("current", "olympus.submodules.PRICE.ERC4626Price");
        uniswapV2PoolTokenPrice = envAddress("current", "olympus.submodules.PRICE.UniswapV2PoolTokenPrice");
        uniswapV3Price = envAddress("current", "olympus.submodules.PRICE.UniswapV3Price");
        simplePriceFeedStrategy = envAddress("current", "olympus.submodules.PRICE.SimplePriceFeedStrategy");
        appraiser = envAddress("current", "olympus.policies.Appraiser");
        bookkeeper = envAddress("current", "olympus.policies.Bookkeeper");
        newHeart = envAddress("current", "olympus.policies.OlympusHeart");
        newOperator = envAddress("current", "olympus.policies.Operator");
        bunniManager = envAddress("current", "olympus.policies.BunniManager");
    }

    function RBSv2Install_3_1(bool send_) external isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. deactivates old heart + operator policies at contract level
        // 2. deactivates old heart + operator policies at kernel level
        // 3. upgrades the price module to v2
        // 4. activates appraiser policy
        // 5. activates bookkeeper policy
        // 6. activates new heart policy
        // 7. activates new operator policy
        // 8. sets roles for new policy access control
        // 9. installs submodules on price v2
        // 10. sets operator address on bond callback

        // 1. Deactivate old heart + operator policies at contract level
        addToBatch(heart, abi.encodeWithSelector(OlympusHeart.deactivate.selector));
        addToBatch(operator, abi.encodeWithSelector(Operator.deactivate.selector));

        // 2. Deactivate old heart + operator policies at kernel level
        addToBatch(kernel, abi.encodeWithSelector(Kernel.executeAction.selector, Actions.DeactivatePolicy, heart));
        addToBatch(kernel, abi.encodeWithSelector(Kernel.executeAction.selector, Actions.DeactivatePolicy, operator));

        // 3. Upgrade the price module to v2
        addToBatch(kernel, abi.encodeWithSelector(Kernel.executeAction.selector, Actions.UpgradeModule, priceV2));

        // 4. Activate appraiser policy
        addToBatch(kernel, abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, appraiser));

        // 5. Activate bookkeeper policy
        addToBatch(kernel, abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, bookkeeper));

        // 6. Activate new heart policy
        addToBatch(kernel, abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, newHeart));

        // 7. Activate new operator policy
        addToBatch(kernel, abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, newOperator));

        // 8. Set roles for new policy access control
        // Bookkeeper policy
        //     - Give DAO MS the bookkeeper_admin role
        //     - Give DAO MS the bookkeeper_policy role
        //     - Give Policy MS the bookkeeper_policy role
        // Operator policy
        //     - Give Heart the operator_operate role
        addToBatch(rolesAdmin, abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("bookkeeper_admin"), daoMS));
        addToBatch(rolesAdmin, abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("bookkeeper_policy"), daoMS));
        addToBatch(rolesAdmin, abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("bookkeeper_policy"), policyMS));
        addToBatch(rolesAdmin, abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("operator_operate"), newHeart));

        // 9. Install submodules on price v2
        //     - Install BalancerPoolTokenPrice submodule
        //     - Install BunniPrice submodule
        //     - Install ChainlinkPriceFeeds submodule
        //     - Install ERC4626Price submodule
        //     - Install UniswapV2PoolTokenPrice submodule
        //     - Install UniswapV3Price submodule
        //     - Install SimplePriceFeedStrategy submodule
        addToBatch(bookkeeper, abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, balancerPoolTokenPrice));
        addToBatch(bookkeeper, abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, bunniPrice));
        addToBatch(bookkeeper, abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, chainlinkPriceFeeds));
        addToBatch(bookkeeper, abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, erc4626Price));
        addToBatch(bookkeeper, abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, uniswapV2PoolTokenPrice));
        addToBatch(bookkeeper, abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, uniswapV3Price));
        addToBatch(bookkeeper, abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, simplePriceFeedStrategy));

        // 10. Set operator address on bond callback
        addToBatch(bondCallback, abi.encodeWithSelector(BondCallback.setOperator.selector, newOperator));
    }

    function RBSv2Install_3_2(
        bool send_,
        uint256[] memory ohmObs_,
        uint48 ohmLastObsTime_,
        uint256[] memory daiObs_,
        uint48 daiLastObsTime_,
        uint256[] memory sdaiObs_,
        uint48 sdaiLastObsTime_,
        uint256[] memory polBunniObs_,
        uint48 polBunniLastObsTime_,
        uint256[] memory wethObs_,
        uint48 wethLastObsTime_,
        uint256[] memory veFXSObs_,
        uint48 veFXSLastObsTime_,
        uint256[] memory fxsObs_,
        uint48 fxsLastObsTime_,
        uint256[] memory usdcObs_,
        uint48 usdcLastObsTime_
    ) public isPolicyBatch(send_) {
        // This Policy MS batch:
        // 1. Configures OHM price feed and moving average data on PRICE
        // 2. Configures DAI price feed and moving average data on PRICE
        // 3. Configures sDAI price feed and moving average data on PRICE
        // 4. Configures polBunni price feed and moving average data on PRICE
        // 5. Configure WETH price feed and moving average data on PRICE
        // 6. Configure veFXS price feed and moving average data on PRICE
        // 7. Configure FXS price feed and moving average data on PRICE
        // 8. Configure USDC price feed and moving average data on PRICE
        // 9. Add and categorize DAI
        // 10. Add and categorize sDAI
        // 11. Add and categorize POL
        // 12. Add and categorize OHM
        // 13. Add and categorize WETH
        // 14. Add and categorize veFXS
        // 15. Add and categorize FXS
        // 16. Categorize protocol-owned-treasury supply
        // 17. Categorize dao supply
        // 18. Categorize BLV supply

        // 1. Configure OHM price feed and moving average data on PRICE
        PRICEv2.Component[] memory ohmFeeds = new PRICEv2.Component[](1);
        ohmFeeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.UNIV3"),
            UniswapV3Price.getTokenTWAP.selector,
            abi.encode(ohmDaiPool, 18, "")
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.addAssetPrice.selector,
                ohm,
                false, // don't store moving average
                false, // don't use the moving average as part of price strategy
                0,
                ohmLastObsTime_,
                ohmObs_,
                PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                ohmFeeds
            )
        );

        // 2. Configure DAI price feed and moving average data on PRICE
        PRICEv2.Component[] memory daiFeeds = new PRICEv2.Component[](2);
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
        )
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

        // 3. Configure sDAI price feed and moving average data on PRICE
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
                sdaiLastObsTime_,
                sdaiObs_,
                PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                sdaiFeeds
            )
        );

        // 4. Configure polBunni price feed and moving average data on PRICE
        PRICEv2.Component[] memory polBunniFeeds = new PRICEv2.Component[](1);
        polBunniFeeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.BNI"),
            BunniPrice.getBunniTokenPrice.selector,
            abi.encode(polBunni, ERC20(polBunni).decimals(), "") // TODO: Change bytes params?
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.addAssetPrice.selector,
                polBunni,
                false, // don't store moving average
                false, // don't use the moving average as part of price strategy
                0, // 30 day moving average
                polBunniLastObsTime_,
                polBunniObs_,
                PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                polBunniFeeds
            )
        );

        // 5. Configure WETH price feed and moving average data on PRICE
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
                bookkeeper.addAssetPrice.selector,
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

        // 6. Configure veFXS price feed and moving average data on PRICE
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
                bookkeeper.addAssetPrice.selector,
                veFXS,
                false, // don't store moving average
                false, // don't use the moving average as part of price strategy
                0, // 30 day moving average
                veFXSLastObsTime_,
                veFXSObs_,
                PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                veFXSFeeds
            )
        );

        // 7. Configure FXS price feed and moving average data on PRICE
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
                bookkeeper.addAssetPrice.selector,
                fxs,
                false, // don't store moving average
                false, // don't use the moving average as part of price strategy
                0, // 30 day moving average
                fxsLastObsTime_,
                fxsObs_,
                PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                fxsFeeds
            )
        );

        // 8. Configure USDC price feed and moving average data on PRICE
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
                bookkeeper.addAssetPrice.selector,
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

        // 9. Add and categorize DAI on Bookkeeper
        //      - liquid, stable, reserves
        address[] memory locations = new address[](1);
        locations[0] = clearinghouse;
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.addAsset.selector, dai, locations)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, dai, AssetCategory.wrap("liquid"))
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, dai, AssetCategory.wrap("stable"))
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, dai, AssetCategory.wrap("reserves"))
        );

        // 10. Add and categorize sDAI on Bookkeeper
        //      - liquid, stable, reserves
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.addAsset.selector, sdai, locations)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, sdai, AssetCategory.wrap("liquid"))
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, sdai, AssetCategory.wrap("stable"))
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, sdai, AssetCategory.wrap("reserves"))
        );

        // 11. Add and categorize POL
        //      - liquid, protocol-owned-liquidity
        address[] memory polLocations = new address[](1);
        polLocations[0] = BunniManager(bunniManager).bunniHub();
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.addAsset.selector, polBunni, polLocations)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, polBunni, AssetCategory.wrap("liquid"))
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, polBunni, AssetCategory.wrap("protocol-owned-liquidity"))
        );

        // 12. Categorize manual offset
        

        // 13. Add and categorize WETH
        //      - liquid, volatile
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.addAsset.selector, weth, new address[](0))
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, weth, AssetCategory.wrap("liquid"))
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, weth, AssetCategory.wrap("volatile"))
        );

        // 14. Add and categorize veFXS
        //      - illiquid, volatile
        address[] memory veFXSLocations = new address[](1);
        veFXSLocations[0] = veFXSAllocator;
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.addAsset.selector, veFXS, veFXSLocations)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, veFXS, AssetCategory.wrap("illiquid"))
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, veFXS, AssetCategory.wrap("volatile"))
        );

        // 15. Add and categorize FXS
        //      - illiquid, volatile
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.addAsset.selector, fxs, veFXSLocations)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, fxs, AssetCategory.wrap("illiquid"))
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeAsset.selector, fxs, AssetCategory.wrap("volatile"))
        );

        // 16. Categorize protocol-owned-treasury supply
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeSupply.selector, daoMS, SupplyCategory.wrap("protocol-owned-treasury"))
        );
        // TODO - Manual offset??
        // TODO - Bricked supply??

        // 17. Categorize dao supply
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeSupply.selector, daoWorkingWallet, SupplyCategory.wrap("dao"))
        );

        // 18. Categorize BLV supply
        // TODO - fix. this is wrong. i don't fully understand the supply categorization with submodules
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeSupply.selector, blvLido, SupplyCategory.wrap("blv"))
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.categorizeSupply.selector, blvLusd, SupplyCategory.wrap("blv"))
        );
    }

    function RBSv2Install_3_3(bool send_) public isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. Initializes the operator policy

        // 1. Initialize the operator policy
        addToBatch(newOperator, abi.encodeWithSelector(Operator.initialize.selector));
    }
}
