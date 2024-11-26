// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import "src/Kernel.sol";

// Bophades policies
import {YieldRepurchaseFacility} from "policies/YieldRepurchaseFacility.sol";
import {OlympusHeart} from "policies/Heart.sol";
import {Operator} from "policies/Operator.sol";
import {Clearinghouse} from "policies/Clearinghouse.sol";
import {ReserveMigrator} from "policies/ReserveMigrator.sol";
import {BondCallback} from "policies/BondCallback.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice
/// @dev Deactivates old heart, operator, yield repo, and clearinghouse contracts.
///      Installs new versions that references USDS instead of DAI. Also, adds the ReserveMigrator contract.
contract USDSMigration is OlyBatch {
    // 1. Deactivate existing contracts that are being replaced locally (i.e. on the contract itself) - DAO MS
    //    + Clearinghouse v2
    //      - Defund to send any reserves back to TRSRY
    //      - Deactivate
    //    + YieldRepurchaseFacility v1
    //      - shutdown to send any reserves back to TRSRY
    //      - make sure that bond market is ended
    //    + Operator v1.4
    //      - Deactivate to prevent swaps and bond markets
    //    + Heart v1.5
    //      - Deactivate so it will not beat

    // 2. Deactivate policies that are being replaced on the Kernel - DAO MS
    //    + Clearinghouse v2
    //    + YieldRepurchaseFacility v1
    //    + Operator v1.4
    //    + Heart v1.5

    // 3. Activate new policies on the Kernel - DAO MS
    //    + Clearinghouse v2.1
    //    + Operator v1.5
    //    + YieldRepurchaseFacility v1.1
    //    + ReserveMigrator v1
    //    + Heart v1.6

    // 4. Initialize new policies and update certain configs - DAO MS
    //    + Set Operator on BondCallback to Operator v1.5
    //    + Set sUSDS as the wrapped token for USDS on BondCallback
    //    + Activate Clearinghouse v2.1
    //    + Initialize YieldRepurchaseFacility v1.1

    // TODO set these
    uint256 initialReserveBalance = 0;
    uint256 initialConversionRate = 0;
    uint256 initialYield = 0;

    address kernel;
    address oldHeart;
    address oldOperator;
    address oldYieldRepo;
    address oldClearinghouse;
    address newHeart;
    address newOperator;
    address newYieldRepo;
    address newClearinghouse;
    address reserveMigrator;
    address emissionManager;
    address bondCallback;
    address usds;
    address susds;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        oldHeart = envAddress("last", "olympus.policies.OlympusHeart");
        oldOperator = envAddress("last", "olympus.policies.Operator");
        oldYieldRepo = envAddress("last", "olympus.policies.YieldRepurchaseFacility");
        oldClearinghouse = envAddress("last", "olympus.policies.Clearinghouse");
        newHeart = envAddress("current", "olympus.policies.OlympusHeart");
        newOperator = envAddress("current", "olympus.policies.Operator");
        newYieldRepo = envAddress("current", "olympus.policies.YieldRepurchaseFacility");
        newClearinghouse = envAddress("current", "olympus.policies.Clearinghouse");
        reserveMigrator = envAddress("current", "olympus.policies.ReserveMigrator");
        emissionManager = envAddress("current", "olympus.policies.EmissionManager");
        bondCallback = envAddress("current", "olympus.policies.BondCallback");
        usds = envAddress("current", "external.tokens.USDS");
        susds = envAddress("current", "external.tokens.sUSDS");
    }

    // Entry point for the script
    function run(bool send_) external isDaoBatch(send_) {
        // 1. Deactivate existing contracts that are being replaced locally
        // 1a. Deactivate OlympusHeart
        addToBatch(oldHeart, abi.encodeWithSelector(OlympusHeart.deactivate.selector));
        // 1b. Deactivate Operator
        addToBatch(oldOperator, abi.encodeWithSelector(Operator.deactivate.selector));
        // 1c. Shutdown YieldRepurchaseFacility
        ERC20[] memory tokensToTransfer = new ERC20[](2);
        tokensToTransfer[0] = ERC20(envAddress("current", "external.tokens.DAI"));
        tokensToTransfer[1] = ERC20(envAddress("current", "external.tokens.sDAI"));
        addToBatch(
            oldYieldRepo,
            abi.encodeWithSelector(YieldRepurchaseFacility.shutdown.selector, tokensToTransfer)
        );
        // 1d. Shutdown the old Clearinghouse
        addToBatch(
            oldClearinghouse,
            abi.encodeWithSelector(Clearinghouse.emergencyShutdown.selector)
        );

        // 2. Deactivate policies that are being replaced on the Kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldHeart
            )
        );
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
                oldYieldRepo
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldClearinghouse
            )
        );

        // 3. Activate new policies on the Kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                newOperator
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                newYieldRepo
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                newClearinghouse
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                reserveMigrator
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, newHeart)
        );

        // STEP 4: Policy initialization steps
        // 4a. Set `BondCallback.operator()` to the new Operator policy
        addToBatch(
            bondCallback,
            abi.encodeWithSelector(BondCallback.setOperator.selector, newOperator)
        );

        // 4b. Set sUSDS as the wrapped token for USDS on BondCallback
        addToBatch(
            bondCallback,
            abi.encodeWithSelector(BondCallback.useWrappedVersion.selector, usds, susds)
        );

        // 4c. Activate the new Clearinghouse policy
        addToBatch(newClearinghouse, abi.encodeWithSelector(Clearinghouse.activate.selector));

        // 4d. Initialize the new YRF
        addToBatch(
            newYieldRepo,
            abi.encodeWithSelector(
                YieldRepurchaseFacility.initialize.selector,
                initialReserveBalance,
                initialConversionRate,
                initialYield
            )
        );
    }
}
