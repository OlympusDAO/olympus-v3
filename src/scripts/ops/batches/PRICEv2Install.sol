// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";
import "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {Bookkeeper} from "src/policies/OCA/Bookkeeper.sol";
import {BondCallback} from "src/policies/Bonds/BondCallback.sol";
import {Operator} from "src/policies/RBS/Operator.sol";
import {OlympusHeart} from "src/policies/RBS/Heart.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract PRICEv2Install is OlyBatch {
    address kernel;
    address rolesAdmin;
    address ohm;
    address bondCallback;

    address PRICEv2;
    address bookkeeper;
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
        kernel = envAddress("olympus.Kernel");
        ohm = envAddress("olympus.legacy.OHM");
        PRICEv2 = envAddress("olympus.modules.OlympusPriceV2");
        bookkeeper = envAddress("olympus.policies.Bookkeeper");
        // TODO figure out version control of contracts in env.json (e.g. old Operator vs. new Operator)
        oldOperator;
        oldHeart;
        operator = envAddress("olympus.policies.Operator");
        heart = envAddress("olympus.policies.OlympusHeart");
        bondCallback = envAddress("olympus.policies.BondCallback");
        simplePriceFeedStrategy = envAddress("olympus.submodules.PRICE.SimplePriceFeedStrategy");
        chainlinkPriceFeeds = envAddress("olympus.submodules.PRICE.ChainlinkPriceFeeds");
        balancerPoolTokenPrice = envAddress("olympus.submodules.PRICE.BalancerPoolTokenPrice");
        uniV2PoolTokenPrice = envAddress("olympus.submodules.PRICE.UniswapV2PoolTokenPrice");
        uniV3PriceFeed = envAddress("olympus.submodules.PRICE.UniswapV3Price");
    }

    function PRICEv2_Install_1(bool send_) external isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. deactivate old operator and heart policies + withdraws remaining rewards from old heart
        // 2. deactivates old operator and heart policies on kernel
        // 3. installs the new oracle system contracts on the kernel
        // 4. sets roles for new policy access control
        // 5. installs submodules on the new PRICEv2 module
        // 6. sets operator address on bond callback

        // Deactivate old heart
        addToBatch(oldHeart, abi.encodeWithSelector(OlympusHeart.deactivate.selector));

        // Deactivate old operator
        addToBatch(oldOperator, abi.encodeWithSelector(Operator.deactivate.selector));

        // Withdraw remaining rewards from old heart
        addToBatch(
            oldHeart,
            abi.encodeWithSelector(OlympusHeart.withdrawUnspentRewards.selector, ohm)
        );

        // Deactivate old policies on Kernel
        // Operator policy
        // Heart policy
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                oldOperator,
                Actions.DeactivatePolicy
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                oldHeart,
                Actions.DeactivatePolicy
            )
        );

        // Install new contracts on Kernel
        // PRICEv2 module (upgrade from PRICEv1)
        // Bookkeeper policy
        // Operator policy
        // Heart policy
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, PRICEv2, Actions.UpgradeModule)
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                bookkeeper,
                Actions.ActivatePolicy
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, operator, Actions.ActivatePolicy)
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, heart, Actions.ActivatePolicy)
        );

        // Provide roles to priviledged addresses for policy access
        // Bookkeeper policy
        //     - Give DAO MS the bookkeeper_admin role
        //     - Give DAO MS the bookkeeper_policy role
        //     - Give Policy MS the bookkeeper_policy role
        // Operator policy
        //     - Give DAO MS the operator_admin role
        //     - Give Policy MS the operator_policy role
        //     - Give Heart the operator_operate role
        // Heart policy
        //     - Give DAO MS the heart_admin role
        //     - Give Policy MS the heart_admin role
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
                policyMS
            )
        );
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("operator_admin"), daoMS)
        );
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("operator_policy"),
                policyMS
            )
        );
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("operator_operate"),
                heart
            )
        );
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart_admin"), daoMS)
        );
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart_admin"), policyMS)
        );

        // Install submodules on PRICEv2 module
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

    function PRICEv2_Install_2(bool send_) public isPolicyBatch(send_) {
        // This Policy MS Batch:
        // 1. Configures OHM price feed and moving average data on PRICEv2
        // 2. Configures DAI price feed and moving average data on PRICEv2
        // TODO where to add parameters? -> effects shell script
    }

    function PRICEv2_Install_3(bool send_) public isDaoBatch(send_) {
        // This DAO MS Batch:
        // 1. Add rewards to new heart
        // 1. Initializes the operator policy
        uint256 ohmRewards = 0; // TODO determine how to set

        // Add rewards to new heart
        addToBatch(ohm, abi.encodeWithSelector(ERC20.transfer.selector, heart, ohmRewards));

        // Initialize the operator policy
        addToBatch(operator, abi.encodeWithSelector(Operator.initialize.selector));
    }
}
