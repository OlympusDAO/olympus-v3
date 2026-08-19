// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.30;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.16.2/console2.sol";

import {Kernel, Actions, Policy} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

/// @title LZBridgeGatewayBatch
/// @notice Ethereum MS batch scripts for the LZBridgeGateway policy.
///
///         Entry points:
///         - `activateGateway` (pre-OCG): activate the new gateway, the LZEndpointDelegate policy, and the LZBridgeAndDelegateConfig policy in the Kernel
///         - `initBridgedSupply` (post-OCG): set the initial bridged supply tracking
///
///         The old CrossChainBridge is deactivated post-OCG via LZCrossChainBridgeBatch.setup().
contract LZBridgeGatewayBatch is BatchScriptV2 {
    // =========== ERRORS =========== //

    error LZBridgeGatewayBatch_NonCanonicalChain();
    error LZBridgeGatewayBatch_ZeroInitialBridgedSupply();
    error LZBridgeGatewayBatch_EndpointMismatch(address expected, address actual);

    // =========== STATE =========== //

    /// @notice Expected bridged supply for post-batch validation.
    uint256 internal _expectedBridgedSupply;

    // =========== ENTRY POINTS =========== //

    /// @notice Ethereum Phase 1 (pre-OCG): activate the new gateway, delegate, and config policies in the Kernel.
    ///         The old CrossChainBridge remains active during the OCG voting period and is
    ///         deactivated post-OCG via LZCrossChainBridgeBatch.setup().
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
        address newDelegate = _envAddressNotZero("olympus.policies.LZEndpointDelegate");
        address newConfig = _envAddressNotZero("olympus.policies.LZBridgeAndDelegateConfig");

        console2.log("\n=== Ethereum Phase 1: Activate Gateway + Delegate + Config ===");
        console2.log("New LZBridgeGateway:", newGateway);
        console2.log("New LZEndpointDelegate:", newDelegate);
        console2.log("New LZBridgeAndDelegateConfig:", newConfig);

        // Pre-flight: the gateway's `LZ_ENDPOINT` must match env.json so a gateway deployed
        // against the wrong endpoint is caught here, before the OCG activator runs against it.
        _assertGatewayEndpointMatchesEnv(newGateway);

        // Activate the new LZBridgeGateway
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                newGateway
            )
        );

        // Activate the new LZEndpointDelegate policy so the OCG activator can set it as the
        // gateway's LZ endpoint delegate.
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                newDelegate
            )
        );

        // Activate the LZBridgeAndDelegateConfig policy.
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, newConfig)
        );

        _setPostBatchValidateSelector(this._validateActivateGateway.selector);

        proposeBatch();
    }

    /// @notice Ethereum Phase 2 (post-OCG): set initial bridged supply.
    ///         LZ config and peers are set by the OCG proposal.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (must contain "initBridgedSupply.initialBridgedSupply").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function initBridgedSupply(
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
            "initBridgedSupply",
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
            abi.encodeWithSelector(
                LZBridgeGateway.initializeBridgedSupply.selector,
                initialBridgedSupply
            )
        );

        _setPostBatchValidateSelector(this._validateInitBridgedSupply.selector);

        proposeBatch();
    }

    // =========== VALIDATION =========== //

    /// @notice Validate activateGateway state after batch execution.
    /// @dev Checks that the gateway, the delegate, and the config policy are active in the Kernel.
    function _validateActivateGateway() external view {
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        address delegateAddr = _envAddressNotZero("olympus.policies.LZEndpointDelegate");
        address configAddr = _envAddressNotZero("olympus.policies.LZBridgeAndDelegateConfig");
        LZBridgeGateway gateway = LZBridgeGateway(gatewayAddr);

        console2.log("\nValidating activateGateway post-batch state");

        if (!gateway.isActive()) {
            revert("LZBridgeGateway is not active in the Kernel");
        }
        console2.log("  LZBridgeGateway is active in the Kernel");

        if (!Policy(delegateAddr).isActive()) {
            revert("LZEndpointDelegate is not active in the Kernel");
        }
        console2.log("  LZEndpointDelegate is active in the Kernel");

        if (!Policy(configAddr).isActive()) {
            revert("LZBridgeAndDelegateConfig is not active in the Kernel");
        }
        console2.log("  LZBridgeAndDelegateConfig is active in the Kernel");

        // Re-check the gateway's LZ_ENDPOINT against env.json so the post-batch validator is
        // independently checkable (the same gate also runs in the pre-flight).
        _assertGatewayEndpointMatchesEnv(gatewayAddr);
        console2.log("  Gateway LZ_ENDPOINT matches the expected endpoint for this chain");

        console2.log("activateGateway post-batch validation passed");
    }

    /// @notice Validate initBridgedSupply state after batch execution.
    /// @dev Checks that bridgedSupply was set correctly and that the MINTR
    ///      mint approval matches (invariant: mintApproval == bridgedSupply).
    function _validateInitBridgedSupply() external view {
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        LZBridgeGateway gateway = LZBridgeGateway(gatewayAddr);

        console2.log("\nValidating initBridgedSupply post-batch state");

        // 1. Validate the bootstrap flag was set so future calls cannot re-initialise.
        if (!gateway.bridgedSupplyInitialized()) {
            revert("bridgedSupplyInitialized flag should be true after initBridgedSupply");
        }

        // 2. Validate bridgedSupply is non-zero and matches expected value
        uint256 actualSupply = gateway.bridgedSupply();
        if (actualSupply == 0) {
            revert("bridgedSupply is 0 after initBridgedSupply");
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

        console2.log("initBridgedSupply post-batch validation passed");
    }

    // =========== INTERNAL HELPERS =========== //

    /// @notice Reverts if called on a non-canonical chain (L2).
    /// @dev This batch script is only for canonical chains (mainnet/sepolia).
    function _requireCanonical() internal view {
        if (!ChainUtils._isCanonicalChain(chain)) revert LZBridgeGatewayBatch_NonCanonicalChain();
    }

    /// @notice Asserts the gateway's `LZ_ENDPOINT` immutable matches env.json for this chain.
    /// @dev Cross-checks the gateway's immutable against an independent source so a deploy
    ///      against the wrong endpoint cannot pass through this batch silently.
    /// @param gatewayAddr_ The gateway whose `LZ_ENDPOINT` immutable to compare.
    function _assertGatewayEndpointMatchesEnv(address gatewayAddr_) internal view {
        address expectedEndpoint = _envAddressNotZero("external.layerzero-v2.endpoint");
        address gatewayEndpoint = LZBridgeGateway(gatewayAddr_).LZ_ENDPOINT();
        if (gatewayEndpoint != expectedEndpoint) {
            revert LZBridgeGatewayBatch_EndpointMismatch(expectedEndpoint, gatewayEndpoint);
        }
    }
}
