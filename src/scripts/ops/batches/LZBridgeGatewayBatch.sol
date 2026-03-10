// SPDX-License-Identifier: Unlicensed
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {LZBridgeBatchScript} from "./lib/LZBridgeBatchScript.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";

/// @title LZBridgeGatewayBatch
/// @notice Ethereum MS batch scripts for the LZBridgeGateway policy.
///
///         Entry points:
///         - `activateGateway` (pre-OCG): activate new gateway in Kernel
///         - `setBridgedSupply` (post-OCG): set initial bridged supply tracking
///
///         The old CrossChainBridge is deactivated post-OCG via LZCrossChainBridgeBatch.setup().
contract LZBridgeGatewayBatch is LZBridgeBatchScript {
    // =========== ENTRY POINTS =========== //

    /// @notice Ethereum Phase 1 (pre-OCG): activate new gateway in Kernel.
    ///         The old CrossChainBridge remains active during the OCG voting period
    ///         and is deactivated post-OCG via LZCrossChainBridgeBatch.setup().
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function activateGateway(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address kernel = _envAddressNotZero("olympus.Kernel");
        address newGateway = _envAddressNotZero("olympus.policies.LZBridgeGateway");

        console2.log("\n=== Ethereum Phase 1: Activate Gateway ===");
        console2.log("New LZBridgeGateway:", newGateway);

        // Activate new LZBridgeGateway
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                newGateway
            )
        );

        proposeBatch();
    }

    /// @notice Ethereum Phase 2 (post-OCG): set initial bridged supply.
    ///         LZ config and trusted remotes are set by the OCG proposal.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function setBridgedSupply(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");

        console2.log("\n=== Ethereum Phase 2: Set Bridged Supply ===");
        console2.log("Setting initial bridged supply:", INITIAL_BRIDGED_SUPPLY);

        addToBatch(
            gatewayAddr,
            abi.encodeWithSelector(
                LZBridgeGateway.setBridgedSupply.selector,
                INITIAL_BRIDGED_SUPPLY
            )
        );

        proposeBatch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
