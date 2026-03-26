// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @title LZCrossChainBridgeBatch
/// @notice Ethereum MS batch scripts for the LZCrossChainBridge periphery contract.
///
///         Entry points:
///         - `disableOldBridge` (post-OCG): disable old CrossChainBridge (pre-migration)
///         - `setup` (post-OCG):            deactivate old CrossChainBridge + enable periphery bridge
///         - `enable`:                      enable only
///         - `disable`:                     disable only
contract LZCrossChainBridgeBatch is BatchScriptV2 {
    // =========== ENTRY POINTS =========== //

    /// @notice Ethereum (post-OCG, pre-migration): disable old CrossChainBridge.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function disableOldBridge(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");

        console2.log("\n=== Disabling Old CrossChainBridge (Ethereum) ===");
        console2.log("Old Bridge:", oldBridge);

        addToBatch(oldBridge, abi.encodeWithSignature("setBridgeStatus(bool)", false));

        proposeBatch();
    }

    /// @notice Ethereum setup (post-OCG): deactivate old CrossChainBridge and enable the periphery bridge.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function setup(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");
        address kernel = _envAddressNotZero("olympus.Kernel");
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");

        console2.log("\n=== LZCrossChainBridge Setup (Ethereum, post-OCG) ===");
        console2.log("Bridge:", bridgeAddr);

        // 1. Deactivate old CrossChainBridge in Kernel
        console2.log("Deactivating old CrossChainBridge:", oldBridge);
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldBridge
            )
        );

        // 2. Enable bridge
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.enable.selector, ""));

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
