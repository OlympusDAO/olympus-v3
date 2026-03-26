// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

/// @title LZBridgeGatewayBatch
/// @notice Ethereum MS batch scripts for the LZBridgeGateway policy.
///
///         Entry points:
///         - `activateGateway` (pre-OCG): activate new gateway in Kernel
///         - `setBridgedSupply` (post-OCG): set initial bridged supply tracking
///
///         The old CrossChainBridge is deactivated post-OCG via LZCrossChainBridgeBatch.setup().
contract LZBridgeGatewayBatch is BatchScriptV2 {
    // =========== ERRORS =========== //

    error LZBridgeGatewayBatch_NonCanonicalChain();

    // =========== ENTRY POINTS =========== //

    /// @notice Ethereum Phase 1 (pre-OCG): activate new gateway in Kernel.
    ///         The old CrossChainBridge remains active during the OCG voting period
    ///         and is deactivated post-OCG via LZCrossChainBridgeBatch.setup().
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function activateGateway(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireCanonical();

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
    ///         LZ config and peers are set by the OCG proposal.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (must contain "setBridgedSupply.initialBridgedSupply").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function setBridgedSupply(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _requireCanonical();

        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        // TODO: Set initialBridgedSupply in args file before execution
        uint256 initialBridgedSupply = _readBatchArgUint256(
            "setBridgedSupply",
            "initialBridgedSupply"
        );

        console2.log("\n=== Ethereum Phase 2: Set Bridged Supply ===");
        console2.log("Setting initial bridged supply:", initialBridgedSupply);

        addToBatch(
            gatewayAddr,
            abi.encodeWithSelector(LZBridgeGateway.setBridgedSupply.selector, initialBridgedSupply)
        );

        proposeBatch();
    }

    // =========== INTERNAL HELPERS =========== //

    /// @notice Reverts if called on a non-canonical chain (L2).
    /// @dev    This batch script is only for canonical chains (mainnet/sepolia).
    function _requireCanonical() internal view {
        if (!ChainUtils._isCanonicalChain(chain)) revert LZBridgeGatewayBatch_NonCanonicalChain();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
