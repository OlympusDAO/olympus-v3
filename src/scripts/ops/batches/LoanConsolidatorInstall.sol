// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import {Kernel, Actions} from "src/Kernel.sol";

/// @notice     Installs the LoanConsolidator policy
contract LoanConsolidatorInstall is OlyBatch {
    address kernel;
    address rolesAdmin;
    address loanConsolidator;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        loanConsolidator = envAddress("current", "olympus.policies.LoanConsolidator");
    }

    // Entry point for the batch #1
    function script1_install(bool send_) external isDaoBatch(send_) {
        // LoanConsolidator Install Script

        // Validate addresses
        require(loanConsolidator != address(0), "LoanConsolidator address is not set");

        // A. Kernel Actions
        // A.1. Install the LoanConsolidator policy on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                loanConsolidator
            )
        );

        console2.log("Batch completed");
    }
}
