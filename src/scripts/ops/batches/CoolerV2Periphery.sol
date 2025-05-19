// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @notice     Activates the Cooler V2 periphery contracts
// solhint-disable gas-custom-errors
contract CoolerV2Periphery is OlyBatch {
    using stdJson for string;

    // Policies
    address public coolerV2Composites;
    address public coolerV2Migrator;

    function loadEnv() internal override {
        // Load contract addresses from the environment file

        // Periphery
        coolerV2Migrator = envAddress("current", "olympus.periphery.CoolerV2Migrator");
        coolerV2Composites = envAddress("current", "olympus.periphery.CoolerV2Composites");
    }

    // Entry point for the batch #1
    function run(bool send_) external isDaoBatch(send_) {
        // Validate addresses
        require(coolerV2Migrator != address(0), "Cooler V2 migrator address is not set");
        require(coolerV2Composites != address(0), "Cooler V2 composites address is not set");

        // 1. Activate the periphery contracts
        // These won't work until the Cooler V2 policies are installed by the kernel executor
        // They must be enabled here as the DAO MS is the owner
        // Pre-requisites:
        // - Deployment of Cooler V2 contracts
        // - Installation of Cooler V2 contracts (CoolerV2.sol)
        // - Deployment of Cooler V2 periphery contracts
        console2.log("Enabling Cooler V2 Migrator");
        addToBatch(
            coolerV2Migrator,
            abi.encodeWithSelector(IEnabler.enable.selector, abi.encode(""))
        );

        console2.log("Enabling Cooler V2 Composites");
        addToBatch(
            coolerV2Composites,
            abi.encodeWithSelector(IEnabler.enable.selector, abi.encode(""))
        );

        console2.log("Batch completed");
    }
}
