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
    //    + Operator vX
    //      - Deactivate to prevent swaps and bond markets
    //    + Heart vX
    //      - Deactivate so it will not beat

    // 2. Deactivate policies that are being replaced on the Kernel - DAO MS
    //    + Clearinghouse v2
    //    + YieldRepurchaseFacility v1
    //    + Operator vX
    //    + Heart vX

    // 3. Activate new policies on the Kernel - DAO MS
    //    + Clearinghouse v2.1
    //    + Operator vX+1
    //    + YieldRepurchaseFacility v1.1
    //    + ReserveMigrator v1
    //    + EmissionManager v1
    //    + Heart vX+1

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
    }

    // Entry point for the script
    function run(bool send_) external isDaoBatch(send_) {
        // 1. Deactivate existing contracts that are being replaced locally
        addToBatch(oldHeart, abi.encodeWithSelector(OlympusHeart.deactivate.selector));
        addToBatch(oldOperator, abi.encodeWithSelector(Operator.deactivate.selector));
        addToBatch(oldYieldRepo, abi.encodeWithSelector(YieldRepurchaseFacility.shutdown.selector));
        addToBatch(oldClearinghouse, abi.encodeWithSelector(Clearinghouse.defund.selector));

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
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                emissionManager
            )
        );
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, newHeart)
        );
    }
}
