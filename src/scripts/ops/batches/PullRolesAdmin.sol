// SPDX-License-Identifier: AGPL-3.0-or-later
// solhint-disable custom-errors
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

/// @notice     Pulls the admin role from the deployer to the DAO multisig
contract PullRolesAdmin is OlyBatch {
    using stdJson for string;

    address public kernel;
    address public rolesAdmin;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
    }

    // Entry point for the batch #1
    function pullAdmin(bool send_) external isDaoBatch(send_) {
        // Validate addresses
        require(rolesAdmin != address(0), "RolesAdmin address is not set");

        console2.log("Pulling admin role from deployer to DAO multisig");
        console2.log("RolesAdmin:", rolesAdmin);

        // 1. Pull the admin role from the deployer to the DAO multisig
        addToBatch(rolesAdmin, abi.encodeWithSelector(RolesAdmin.pullNewAdmin.selector));

        console2.log("Batch completed");
    }
}
