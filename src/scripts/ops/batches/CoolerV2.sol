// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import {Kernel, Actions} from "src/Kernel.sol";
import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";

/// @notice     Activates the Cooler V2 contracts
// solhint-disable gas-custom-errors
contract CoolerV2 is OlyBatch {
    using stdJson for string;

    address public kernel;

    // Modules
    address public govDelegation;

    // Policies
    address public coolerV2;
    address public coolerV2TreasuryBorrower;
    address public coolerV2LtvOracle;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");

        // Modules
        govDelegation = envAddress("current", "olympus.modules.OlympusGovDelegation");

        // Policies
        coolerV2 = envAddress("current", "olympus.policies.CoolerV2");
        coolerV2TreasuryBorrower = envAddress(
            "current",
            "olympus.policies.CoolerV2TreasuryBorrower"
        );
        coolerV2LtvOracle = envAddress("current", "olympus.policies.CoolerV2LtvOracle");
    }

    // Entry point for the batch #1
    function run(bool send_) external isDaoBatch(send_) {
        // Validate addresses
        require(coolerV2 != address(0), "Cooler V2 address is not set");
        require(
            coolerV2TreasuryBorrower != address(0),
            "Cooler V2 treasury borrower address is not set"
        );
        require(coolerV2LtvOracle != address(0), "Cooler V2 LTV oracle address is not set");

        // 1. Install modules
        console2.log("Installing modules");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.InstallModule,
                govDelegation
            )
        );

        // 2. Install policies
        console2.log("Installing policies");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                coolerV2LtvOracle
            )
        );

        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, coolerV2)
        );

        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                coolerV2TreasuryBorrower
            )
        );

        // 3. Set the treasury borrower on the MonoCooler contract
        // The first time, this can be done by anyone
        if (IMonoCooler(coolerV2).treasuryBorrower() != coolerV2TreasuryBorrower) {
            console2.log("Setting treasury borrower");
            addToBatch(
                coolerV2,
                abi.encodeWithSelector(
                    IMonoCooler.setTreasuryBorrower.selector,
                    coolerV2TreasuryBorrower
                )
            );
        } else {
            console2.log("Treasury borrower is already set");
        }

        console2.log("Batch completed");
    }
}
