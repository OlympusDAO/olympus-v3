// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";
import "src/modules/PRICE/PRICE.v2.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {Bookkeeper} from "src/policies/OCA/Bookkeeper.sol";
import {BondCallback} from "src/policies/Bonds/BondCallback.sol";
import {Operator} from "src/policies/RBS/Operator.sol";
import {OlympusHeart} from "src/policies/RBS/Heart.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ChainlinkPriceFeeds, AggregatorV2V3Interface} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

contract PRICEv2Install is OlyBatch {
    address kernel;
    address rolesAdmin;
    address ohm;
    address dai;
    address bondCallback;

    address ohmEthPriceFeed;
    address ethUsdPriceFeed;
    address daiEthPriceFeed;
    address daiUsdPriceFeed;

    address PRICE;
    address bookkeeper;
    address priceConfig;
    address oldOperator;
    address oldHeart;
    address operator;
    address heart;
    address simplePriceFeedStrategy;
    address chainlinkPriceFeeds;
    address balancerPoolTokenPrice;
    address uniV2PoolTokenPrice;
    address uniV3PriceFeed;

    function loadEnv() internal override {
        // Load addresses from env
        kernel = envAddress("current", "olympus.Kernel");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        ohm = envAddress("current", "olympus.legacy.OHM");
        dai = envAddress("current", "external.tokens.DAI");
        PRICE = envAddress("current", "olympus.modules.OlympusPricev2");
        bookkeeper = envAddress("current", "olympus.policies.Bookkeeper");
        priceConfig = envAddress("last", "olympus.policies.OlympusPriceConfig");
        oldOperator = envAddress("last", "olympus.policies.Operator");
        oldHeart = envAddress("last", "olympus.policies.OlympusHeart");
        operator = envAddress("current", "olympus.policies.Operator");
        heart = envAddress("current", "olympus.policies.OlympusHeart");
        bondCallback = envAddress("current", "olympus.policies.BondCallback");
        simplePriceFeedStrategy = envAddress(
            "current",
            "olympus.submodules.PRICE.SimplePriceFeedStrategy"
        );
        chainlinkPriceFeeds = envAddress("current", "olympus.submodules.PRICE.ChainlinkPriceFeeds");
        balancerPoolTokenPrice = envAddress(
            "current",
            "olympus.submodules.PRICE.BalancerPoolTokenPrice"
        );
        uniV2PoolTokenPrice = envAddress(
            "current",
            "olympus.submodules.PRICE.UniswapV2PoolTokenPrice"
        );
        uniV3PriceFeed = envAddress("current", "olympus.submodules.PRICE.UniswapV3Price");

        // Load price feeds
        ohmEthPriceFeed = envAddress("current", "external.chainlink.ohmEthPriceFeed");
        ethUsdPriceFeed = envAddress("current", "external.chainlink.ethUsdPriceFeed");
        daiEthPriceFeed = envAddress("current", "external.chainlink.daiEthPriceFeed");
        daiUsdPriceFeed = envAddress("current", "external.chainlink.daiUsdPriceFeed");
    }

    function PRICEv2_Install_1(bool send_) external isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. deactivate old operator and heart policies + withdraws remaining rewards from old heart
        // 2. deactivates old operator and heart policies on kernel
        // 3. installs the new oracle system contracts on the kernel
        // 4. sets roles for new policy access control
        // 5. installs submodules on the new PRICE module
        // 6. sets operator address on bond callback

        // Deactivate old heart
        addToBatch(oldHeart, abi.encodeWithSelector(OlympusHeart.deactivate.selector));

        // // Give DAO MS operator_policy role to deactivate operator
        // addToBatch(
        //     rolesAdmin,
        //     abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("operator_policy"), daoMS)
        // );

        // Deactivate old operator
        addToBatch(oldOperator, abi.encodeWithSelector(Operator.deactivate.selector));

        // // Withdraw remaining rewards from old heart TODO only mainnet since the heart has to have been beat recently
        // addToBatch(
        //     oldHeart,
        //     abi.encodeWithSelector(OlympusHeart.withdrawUnspentRewards.selector, ohm)
        // );

        // Deactivate old policies on Kernel
        // PriceConfig policy
        // Operator policy
        // Heart policy
        // addToBatch(
        //     kernel,
        //     abi.encodeWithSelector(
        //         Kernel.executeAction.selector,
        //         Actions.DeactivatePolicy,
        //         priceConfig
        //     )
        // );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldOperator
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldHeart
            )
        );

        // Install new contracts on Kernel
        // PRICEv2 module (upgrade from PRICEv1)
        // Bookkeeper policy
        // Operator policy
        // Heart policy
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.UpgradeModule, PRICE)
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                bookkeeper
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, operator)
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, heart)
        );

        // Provide roles to priviledged addresses for policy access
        // Bookkeeper policy
        //     - Give DAO MS the bookkeeper_admin role
        //     - Give DAO MS the bookkeeper_policy role
        //     - Give Policy MS the bookkeeper_policy role
        // Operator policy
        //     - Give Heart the operator_operate role
        // addToBatch(
        //     rolesAdmin,
        //     abi.encodeWithSelector(
        //         RolesAdmin.grantRole.selector,
        //         bytes32("bookkeeper_admin"),
        //         daoMS
        //     )
        // );
        // addToBatch(
        //     rolesAdmin,
        //     abi.encodeWithSelector(
        //         RolesAdmin.grantRole.selector,
        //         bytes32("bookkeeper_policy"),
        //         policyMS
        //     )
        // );
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("operator_operate"),
                heart
            )
        );

        // Install submodules on PRICE module
        // SimplePriceFeedStrategy
        // ChainlinkPriceFeeds
        // BalancerPoolTokenPrice
        // UniswapV2PoolTokenPrice
        // UniswapV3Price
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, simplePriceFeedStrategy)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, chainlinkPriceFeeds)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, balancerPoolTokenPrice)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, uniV2PoolTokenPrice)
        );
        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(Bookkeeper.installSubmodule.selector, uniV3PriceFeed)
        );

        // Set the operator policy on the bond callback contract
        addToBatch(
            bondCallback,
            abi.encodeWithSelector(BondCallback.setOperator.selector, operator)
        );
    }

    function PRICEv2_Install_2(
        bool send_,
        uint256[] memory ohmObs_,
        uint48 ohmLastObsTime_,
        uint256[] memory daiObs_,
        uint48 daiLastObsTime_
    ) public isPolicyBatch(send_) {
        // This Policy MS Batch:
        // 1. Configures OHM price feed and moving average data on PRICE
        // 2. Configures DAI price feed and moving average data on PRICE

        // Configure OHM price
        PRICEv2.Component[] memory ohmFeeds = new PRICEv2.Component[](1);
        ohmFeeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 functionSelector_
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams(
                    AggregatorV2V3Interface(ohmEthPriceFeed),
                    uint48(24 hours),
                    AggregatorV2V3Interface(ethUsdPriceFeed),
                    uint48(24 hours)
                )
            )
        );

        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.addAssetPrice.selector,
                ohm,
                true, // store moving average for ohm
                false, // don't use the moving average as part of price strategy
                uint32(30 days), // 30 day moving average
                ohmLastObsTime_,
                ohmObs_,
                PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no strategy for OHM
                ohmFeeds
            )
        );

        // Configure DAI price
        PRICEv2.Component[] memory daiFeeds = new PRICEv2.Component[](2);
        daiFeeds[0] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getTwoFeedPriceMul.selector, // bytes4 functionSelector_
            abi.encode(
                ChainlinkPriceFeeds.TwoFeedParams(
                    AggregatorV2V3Interface(daiEthPriceFeed),
                    uint48(24 hours),
                    AggregatorV2V3Interface(ethUsdPriceFeed),
                    uint48(24 hours)
                )
            )
        );
        daiFeeds[1] = PRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"),
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // bytes4 functionSelector_
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams(
                    AggregatorV2V3Interface(daiUsdPriceFeed),
                    uint48(24 hours)
                )
            )
        );

        addToBatch(
            bookkeeper,
            abi.encodeWithSelector(
                Bookkeeper.addAssetPrice.selector,
                dai,
                true, // store moving average for dai
                true, // use the moving average as part of price strategy
                uint32(30 days), // 30 day moving average
                daiLastObsTime_,
                daiObs_,
                PRICEv2.Component(
                    toSubKeycode("PRICE.SIMPLESTRATEGY"),
                    SimplePriceFeedStrategy.getFirstNonZeroPrice.selector,
                    abi.encode(0)
                ), // strategy for DAI
                daiFeeds
            )
        );
    }

    function PRICEv2_Install_3(bool send_, uint256 ohmRewards_) public isDaoBatch(send_) {
        // This DAO MS Batch:
        // 1. Add rewards to new heart
        // 2. Initializes the operator policy

        // Add rewards to new heart
        addToBatch(ohm, abi.encodeWithSelector(ERC20.transfer.selector, heart, ohmRewards_));

        // Initialize the operator policy
        addToBatch(operator, abi.encodeWithSelector(Operator.initialize.selector));
    }
}
