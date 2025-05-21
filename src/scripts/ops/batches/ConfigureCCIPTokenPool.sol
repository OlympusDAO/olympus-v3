// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.24;

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {CCIPMintBurnTokenPool} from "src/policies/bridge/CCIPMintBurnTokenPool.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

import {console2} from "forge-std/console2.sol";

/// @title ConfigureCCIPTokenPool
/// @notice Multi-sig batch to configure the CCIP bridge
///         This scripts is designed to define the desired configuration,
///         and the script will execute the necessary transactions to
///         configure the CCIP bridge to the desired state.
contract ConfigureCCIPTokenPool is OlyBatch {
    // Define the per-chain configuration
    // chain -> supported destination chains
    // chain -> token pool addresses
    // chain -> outbound rate limiter config
    // chain -> inbound rate limiter config
    // chain -> token address

    address public kernel;
    CCIPMintBurnTokenPool public tokenPool;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        tokenPool = CCIPMintBurnTokenPool(
            envAddress("current", "olympus.policies.CCIPMintBurnTokenPool")
        );
    }

    function install(bool send_) external isDaoBatch(send_) {
        // Assumptions
        // - The token pool has been linked to OHM in the CCIP token admin registry
        // - The token pool is already configured

        // Install the CCIPMintBurnTokenPool policy
        console2.log("Installing CCIPMintBurnTokenPool policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                address(tokenPool)
            )
        );

        // Enable the CCIPMintBurnTokenPool policy
        console2.log("Enabling CCIPMintBurnTokenPool policy");
        addToBatch(kernel, abi.encodeWithSelector(PolicyEnabler.enable.selector, ""));

        console2.log("Completed");
    }
}
