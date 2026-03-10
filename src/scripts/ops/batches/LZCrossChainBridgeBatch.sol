// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {LZBridgeBatchScript} from "./lib/LZBridgeBatchScript.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @title LZCrossChainBridgeBatch
/// @notice Ethereum MS batch scripts for the LZCrossChainBridge periphery contract.
///         Run after LZBridgeGatewayBatch has activated and configured the gateway.
///
///         Entry points:
///         - `setup`:   setGateway + enable + deactivate old CrossChainBridge (post-OCG)
///         - `enable`:  enable only
///         - `disable`: disable only
contract LZCrossChainBridgeBatch is LZBridgeBatchScript {
    // =========== ENTRY POINTS =========== //

    /// @notice Ethereum setup (post-OCG): set gateway and enable the periphery bridge.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function setup(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        address kernel = _envAddressNotZero("olympus.Kernel");
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");

        console2.log("\n=== LZCrossChainBridge Setup (Ethereum) ===");
        console2.log("Bridge:", bridgeAddr);
        console2.log("Gateway:", gatewayAddr);

        // 1. Set gateway
        addToBatch(
            bridgeAddr,
            abi.encodeWithSelector(LZCrossChainBridge.setGateway.selector, gatewayAddr)
        );

        // 2. Enable bridge
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        // 3. Deactivate old CrossChainBridge in Kernel
        console2.log("Deactivating old CrossChainBridge:", oldBridge);
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldBridge
            )
        );

        proposeBatch();
    }

    /// @notice Enable the periphery bridge.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function enable(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");

        console2.log("\n=== Enabling LZCrossChainBridge ===");
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        proposeBatch();
    }

    /// @notice Disable the periphery bridge.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function disable(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");

        console2.log("\n=== Disabling LZCrossChainBridge ===");
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        proposeBatch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
