// SPDX-License-Identifier: AGPL-3.0-or-later
// solhint-disable custom-errors
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import {Kernel, Actions} from "src/Kernel.sol";

/// @notice     Installs the RGSTY module and the ContractRegistryAdmin policy
contract ContractRegistryInstall is OlyBatch {
    address public kernel;
    address public rolesAdmin;
    address public rgsty;
    address public contractRegistryAdmin;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        rgsty = envAddress("current", "olympus.modules.OlympusContractRegistry");
        contractRegistryAdmin = envAddress("current", "olympus.policies.ContractRegistryAdmin");
    }

    // Entry point for the batch #1
    function script1_install(bool send_) external isDaoBatch(send_) {
        // RGSTY Install Script

        // Validate addresses
        require(rgsty != address(0), "RGSTY address is not set");
        require(contractRegistryAdmin != address(0), "ContractRegistryAdmin address is not set");

        // A. Kernel Actions
        // A.1. Install the RGSTY module on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.InstallModule, rgsty)
        );

        // A.2. Install the ContractRegistryAdmin policy on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                contractRegistryAdmin
            )
        );

        console2.log("Batch completed");
    }
}
