// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.24;

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {CCIPBurnMintTokenPool} from "src/policies/bridge/CCIPBurnMintTokenPool.sol";
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
    CCIPBurnMintTokenPool public tokenPool;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        tokenPool = CCIPBurnMintTokenPool(
            envAddress("current", "olympus.policies.CCIPBurnMintTokenPool")
        );
    }

    function install(bool send_) external isDaoBatch(send_) {
        // Assumptions
        // - The token pool has been linked to OHM in the CCIP token admin registry
        // - The token pool is already configured

        // Install the CCIPBurnMintTokenPool policy
        console2.log("Installing CCIPBurnMintTokenPool policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                address(tokenPool)
            )
        );

        // Enable the CCIPBurnMintTokenPool policy
        console2.log("Enabling CCIPBurnMintTokenPool policy");
        addToBatch(kernel, abi.encodeWithSelector(PolicyEnabler.enable.selector, ""));

        console2.log("Completed");
    }
}
