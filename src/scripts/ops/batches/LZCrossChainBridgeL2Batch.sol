// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.16.2/console2.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

/// @title LZCrossChainBridgeL2Batch
/// @notice L2 MS batch scripts for the LZCrossChainBridge periphery contract.
///         Run after LZBridgeGatewayL2Batch has set up the gateway.
///
///         Entry points:
///         - `initializeConfigurator`: one-shot owner call pinning the periphery bridge to
///                                     the LZBridgeAndDelegateConfig policy. Must run before
///                                     `setupL2` so the configurator-gated setters are
///                                     reachable.
///         - `disableOldBridge`:       disable old CrossChainBridge (pre-migration)
///         - `setupL2`:                enable bridge (gateway set in constructor)
///         - `enable`:                 enable only
///         - `disable`:                disable only
contract LZCrossChainBridgeL2Batch is BatchScriptV2 {
    // =========== ERRORS =========== //

    error LZCrossChainBridgeL2Batch_CanonicalChain();

    // =========== ENTRY POINTS =========== //

    /// @notice L2 (post-OCG): one-shot bootstrap of the periphery bridge's configurator variable.
    ///         The DAO MS is the owner and is the only address able to perform the
    ///         bootstrap; after this call the configurator variable is pinned to the
    ///         LZBridgeAndDelegateConfig policy and every subsequent rotation goes through
    ///         the timelock queue exposed by the config.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function initializeConfigurator(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");
        address configAddr = _envAddressNotZero("olympus.policies.LZBridgeAndDelegateConfig");

        console2.log("\n=== Initialize LZCrossChainBridge.configurator (L2:", chain, ") ===");
        console2.log("Bridge:", bridgeAddr);
        console2.log("Configurator:", configAddr);

        addToBatch(bridgeAddr, abi.encodeCall(ILZCrossChainBridge.setConfigurator, (configAddr)));

        proposeBatch();
    }

    /// @notice L2 (pre-migration): disable old CrossChainBridge.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function disableOldBridge(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");

        console2.log("\n=== Disabling Old CrossChainBridge (L2:", chain, ") ===");
        console2.log("Old Bridge:", oldBridge);

        addToBatch(oldBridge, abi.encodeWithSignature("setBridgeStatus(bool)", false));

        proposeBatch();
    }

    /// @notice L2 setup: enable the periphery bridge (gateway set in constructor).
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function setupL2(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");

        console2.log("\n=== LZCrossChainBridge Setup (L2:", chain, ") ===");
        console2.log("Bridge:", bridgeAddr);

        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        proposeBatch();
    }

    /// @notice Enable the periphery bridge on L2.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function enable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");

        console2.log("\n=== Enabling LZCrossChainBridge (L2:", chain, ") ===");
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        proposeBatch();
    }

    /// @notice Disable the periphery bridge on L2.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function disable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");

        console2.log("\n=== Disabling LZCrossChainBridge (L2:", chain, ") ===");
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        proposeBatch();
    }

    // =========== INTERNAL HELPERS =========== //

    /// @notice Reverts if called on a canonical chain (mainnet/sepolia).
    /// @dev    This batch script is only for non-canonical (L2) chains.
    function _requireNonCanonical() internal view {
        if (ChainUtils._isCanonicalChain(chain)) revert LZCrossChainBridgeL2Batch_CanonicalChain();
    }
}
