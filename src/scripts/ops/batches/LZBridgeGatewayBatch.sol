// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
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
    error LZBridgeGatewayBatch_ZeroInitialBridgedSupply();

    // =========== STATE =========== //

    /// @notice Expected bridged supply for post-batch validation.
    uint256 internal _expectedBridgedSupply;

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

        _setPostBatchValidateSelector(this._validateActivateGateway.selector);

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
        if (initialBridgedSupply == 0) revert LZBridgeGatewayBatch_ZeroInitialBridgedSupply();

        console2.log("\n=== Ethereum Phase 2: Set Bridged Supply ===");
        console2.log("Setting initial bridged supply:", initialBridgedSupply);

        // Pre-condition: bridgedSupply and mintApproval must be zero
        LZBridgeGateway gateway = LZBridgeGateway(gatewayAddr);
        uint256 currentSupply = gateway.bridgedSupply();
        // solhint-disable-next-line custom-errors
        require(currentSupply == 0, "bridgedSupply must be 0 before setting initial value");

        MINTRv1 mintr = gateway.MINTR();
        uint256 currentApproval = mintr.mintApproval(gatewayAddr);
        // solhint-disable-next-line custom-errors
        require(currentApproval == 0, "mintApproval must be 0 before setting initial value");

        console2.log("  Pre-condition: bridgedSupply is 0");
        console2.log("  Pre-condition: mintApproval is 0");

        // Store for post-batch validation
        _expectedBridgedSupply = initialBridgedSupply;

        addToBatch(
            gatewayAddr,
            abi.encodeWithSelector(LZBridgeGateway.setBridgedSupply.selector, initialBridgedSupply)
        );

        _setPostBatchValidateSelector(this._validateSetBridgedSupply.selector);

        proposeBatch();
    }

    // =========== VALIDATION =========== //

    /// @notice Validate activateGateway state after batch execution.
    /// @dev Checks that the gateway is active in the Kernel.
    function _validateActivateGateway() external view {
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        LZBridgeGateway gateway = LZBridgeGateway(gatewayAddr);

        console2.log("\nValidating activateGateway post-batch state");

        if (!gateway.isActive()) {
            revert("LZBridgeGateway is not active in the Kernel");
        }
        console2.log("  LZBridgeGateway is active in the Kernel");

        console2.log("activateGateway post-batch validation passed");
    }

    /// @notice Validate setBridgedSupply state after batch execution.
    /// @dev Checks that bridgedSupply was set correctly and that the MINTR
    ///      mint approval matches (invariant: mintApproval == bridgedSupply).
    function _validateSetBridgedSupply() external view {
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        LZBridgeGateway gateway = LZBridgeGateway(gatewayAddr);

        console2.log("\nValidating setBridgedSupply post-batch state");

        // 1. Validate bridgedSupply is non-zero and matches expected value
        uint256 actualSupply = gateway.bridgedSupply();
        if (actualSupply == 0) {
            revert("bridgedSupply is 0 after setBridgedSupply");
        }
        if (actualSupply != _expectedBridgedSupply) {
            revert(
                string.concat(
                    "bridgedSupply should be ",
                    vm.toString(_expectedBridgedSupply),
                    ", but is ",
                    vm.toString(actualSupply)
                )
            );
        }
        console2.log("  bridgedSupply:", actualSupply);

        // 2. Validate mint approval == bridgedSupply (invariant)
        MINTRv1 mintr = gateway.MINTR();
        uint256 approval = mintr.mintApproval(gatewayAddr);
        if (approval != _expectedBridgedSupply) {
            revert(
                string.concat(
                    "mintApproval should be ",
                    vm.toString(_expectedBridgedSupply),
                    ", but is ",
                    vm.toString(approval)
                )
            );
        }
        console2.log("  mintApproval:", approval);

        console2.log("setBridgedSupply post-batch validation passed");
    }

    // =========== INTERNAL HELPERS =========== //

    /// @notice Reverts if called on a non-canonical chain (L2).
    /// @dev    This batch script is only for canonical chains (mainnet/sepolia).
    function _requireCanonical() internal view {
        if (!ChainUtils._isCanonicalChain(chain)) revert LZBridgeGatewayBatch_NonCanonicalChain();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
