// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

/// @title LZCrossChainBridgeBatch
/// @notice Ethereum MS batch scripts for the LZCrossChainBridge periphery contract.
///
///         Entry points:
///         - `disableOldBridge` (post-OCG): disable old CrossChainBridge (pre-migration)
///         - `setup` (post-OCG):            deactivate old CrossChainBridge + enable periphery bridge
///         - `enable`:                      enable only
///         - `disable`:                     disable only
contract LZCrossChainBridgeBatch is BatchScriptV2 {
    // =========== ERRORS =========== //

    error LZCrossChainBridgeBatch_NonCanonicalChain();

    // =========== ENTRY POINTS =========== //

    /// @notice Ethereum (post-OCG, pre-migration): disable old CrossChainBridge.
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
        _requireCanonical();

        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");

        console2.log("\n=== Disabling Old CrossChainBridge (Ethereum) ===");
        console2.log("Old Bridge:", oldBridge);

        addToBatch(oldBridge, abi.encodeWithSignature("setBridgeStatus(bool)", false));

        proposeBatch();
    }

    /// @notice Ethereum setup (post-OCG): deactivate old CrossChainBridge and enable the periphery bridge.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function setup(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireCanonical();

        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");
        address kernel = _envAddressNotZero("olympus.Kernel");
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");

        console2.log("\n=== LZCrossChainBridge Setup (Ethereum, post-OCG) ===");
        console2.log("Bridge:", bridgeAddr);

        // 1. Disable old CrossChainBridge (idempotent if disableOldBridge already ran).
        //    Bundled here to guarantee user-facing bridge calls cannot land between
        //    Kernel deactivation and the bridge being marked inactive.
        console2.log("Disabling old CrossChainBridge:", oldBridge);
        addToBatch(oldBridge, abi.encodeWithSignature("setBridgeStatus(bool)", false));

        // 2. Deactivate old CrossChainBridge in Kernel
        console2.log("Deactivating old CrossChainBridge in Kernel");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldBridge
            )
        );

        // 3. Enable bridge
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        proposeBatch();
    }

    /// @notice Enable the periphery bridge.
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
        _requireCanonical();

        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");

        console2.log("\n=== Enabling LZCrossChainBridge ===");
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        proposeBatch();
    }

    /// @notice Disable the periphery bridge.
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
        _requireCanonical();

        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");

        console2.log("\n=== Disabling LZCrossChainBridge ===");
        addToBatch(bridgeAddr, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        proposeBatch();
    }

    // =========== INTERNAL HELPERS =========== //

    /// @notice Reverts if called on a non-canonical chain (L2).
    /// @dev    This batch script is only for canonical chains (mainnet/sepolia).
    function _requireCanonical() internal view {
        if (!ChainUtils._isCanonicalChain(chain))
            revert LZCrossChainBridgeBatch_NonCanonicalChain();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
