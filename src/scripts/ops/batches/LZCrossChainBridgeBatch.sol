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
///
///         Entry points:
///         - `setGateway` (pre-OCG): point periphery bridge at the new LZBridgeGateway
///         - `setup (post-OCG):      enable periphery bridge + deactivate old CrossChainBridge
///         - `enable`:               enable only
///         - `disable`:              disable only
contract LZCrossChainBridgeBatch is LZBridgeBatchScript {
    // =========== ENTRY POINTS =========== //

    /// @notice Ethereum (pre-OCG): set gateway on the periphery bridge.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function setGateway(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");

        console2.log("\n=== LZCrossChainBridge Set Gateway (Ethereum, pre-OCG) ===");
        console2.log("Bridge:", bridgeAddr);
        console2.log("Gateway:", gatewayAddr);

        addToBatch(
            bridgeAddr,
            abi.encodeWithSelector(LZCrossChainBridge.setGateway.selector, gatewayAddr)
        );

        proposeBatch();
    }

    /// @notice Ethereum setup (post-OCG): enable the periphery bridge and deactivate the old one.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function setup(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");
        address kernel = _envAddressNotZero("olympus.Kernel");
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");

        console2.log("\n=== LZCrossChainBridge Setup (Ethereum, post-OCG) ===");
        console2.log("Bridge:", bridgeAddr);

        // 1. Enable bridge
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        // 2. Deactivate old CrossChainBridge in Kernel
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
