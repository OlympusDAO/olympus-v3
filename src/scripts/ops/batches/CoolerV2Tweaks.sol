// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import {Kernel, Actions} from "src/Kernel.sol";
import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {LoanConsolidator} from "src/policies/LoanConsolidator.sol";
import {CoolerV2Migrator} from "src/periphery/CoolerV2Migrator.sol";

/// @notice     Post-launch tweaks for the Cooler V2 contracts
// solhint-disable gas-custom-errors
contract CoolerV2Tweaks is OlyBatch {
    using stdJson for string;

    address public constant CLEARINGHOUSE_V1 = 0xD6A6E8d9e82534bD65821142fcCd91ec9cF31880;

    address public kernel;

    // Policies
    address public coolerV1LoanConsolidator;
    address public coolerV2Migrator;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");

        // Policies
        coolerV1LoanConsolidator = envAddress("current", "olympus.policies.LoanConsolidator");
        coolerV2Migrator = envAddress("current", "olympus.periphery.CoolerV2Migrator");
    }

    // Entry point for the batch #1
    function run(bool send_) external isDaoBatch(send_) {
        // Validate addresses
        require(
            coolerV1LoanConsolidator != address(0),
            "Cooler V1 loan consolidator address is not set"
        );
        require(coolerV2Migrator != address(0), "Cooler V2 migrator address is not set");

        // 1. Disable the Cooler V1 loan consolidator
        console2.log("Disabling the Cooler V1 loan consolidator");
        addToBatch(
            coolerV1LoanConsolidator,
            abi.encodeWithSelector(LoanConsolidator.deactivate.selector)
        );

        // 2. Deactivate the Cooler V1 loan consolidator
        console2.log("Deactivating the Cooler V1 loan consolidator policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                coolerV1LoanConsolidator
            )
        );

        // 3. Add the Clearinghouse V1 Cooler Factory to the Cooler V2 migrator
        address coolerFactory = address(Clearinghouse(CLEARINGHOUSE_V1).factory());

        console2.log("Adding the Clearinghouse V1 Cooler Factory to the Cooler V2 migrator");
        addToBatch(
            coolerV2Migrator,
            abi.encodeWithSelector(CoolerV2Migrator.addCoolerFactory.selector, coolerFactory)
        );

        console2.log("Batch completed");
    }
}
