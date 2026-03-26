// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @title LZCrossChainBridgeL2Batch
/// @notice L2 MS batch scripts for the LZCrossChainBridge periphery contract.
///         Run after LZBridgeGatewayL2Batch has set up the gateway.
///
///         Entry points:
///         - `disableOldBridge`: disable old CrossChainBridge (pre-migration)
///         - `setupL2`         : enable bridge (gateway set in constructor)
///         - `enable`          : enable only
///         - `disable`         : disable only
contract LZCrossChainBridgeL2Batch is BatchScriptV2 {
    // =========== ENTRY POINTS =========== //

    /// @notice L2 (pre-migration): disable old CrossChainBridge.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function disableOldBridge(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");

        console2.log("\n=== Disabling Old CrossChainBridge (L2:", chain, ") ===");
        console2.log("Old Bridge:", oldBridge);

        addToBatch(oldBridge, abi.encodeWithSignature("setBridgeStatus(bool)", false));

        proposeBatch();
    }

    /// @notice L2 setup: enable the periphery bridge (gateway set in constructor).
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function setupL2(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");

        console2.log("\n=== LZCrossChainBridge Setup (L2:", chain, ") ===");
        console2.log("Bridge:", bridgeAddr);

        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        proposeBatch();
    }

    /// @notice Enable the periphery bridge on L2.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function enable(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");

        console2.log("\n=== Enabling LZCrossChainBridge (L2:", chain, ") ===");
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        proposeBatch();
    }

    /// @notice Disable the periphery bridge on L2.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function disable(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");

        console2.log("\n=== Disabling LZCrossChainBridge (L2:", chain, ") ===");
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        proposeBatch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
