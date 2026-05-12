// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {console2} from "@forge-std-1.9.6/console2.sol";
import {ExecutorConfig} from "@lz-evm-messagelib-v2-3.0.162/SendLibBase.sol";
import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";
import {ILayerZeroEndpointV2} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";

import {ADMIN_ROLE, MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {IEndpointV2State} from "src/interfaces/layerzero/IEndpointV2State.sol";
import {IUlnConfigState} from "src/interfaces/layerzero/IUlnConfigState.sol";
import {Kernel, Actions, Policy} from "src/Kernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {ILZEndpointDelegate} from "src/policies/interfaces/ILZEndpointDelegate.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZEndpointV2Authorized} from "src/policies/interfaces/ILZEndpointV2Authorized.sol";
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

/// @title LZBridgeGatewayL2Batch
/// @notice L2 MS batch scripts for the LZBridgeGateway policy.
///         The periphery LZCrossChainBridge is configured via LZCrossChainBridgeL2Batch.
///
///         On L2 chains the Kernel executor, RolesAdmin admin, and DAO MS may be
///         different addresses. The batch is split into entry points so each
///         can be run by the correct caller:
///
///         Entry points (run in order):
///         1. `activateGateway`    as Kernel executor               deactivates the old bridge and activates the new
///                                                                  gateway and delegate policies.
///         2. `grantRoles`         as RolesAdmin admin              grants bridge_admin & admin roles to DAO MS.
///         3. `configureAndEnable` as DAO MS (bridge_admin & admin) sets the LZEndpointDelegate policy as the gateway's
///                                                                  LZ endpoint delegate, configures LZ
///                                                                  libraries/config via the delegate, sets
///                                                                  peers/enforced options, and enables.
///         4. `revokeSetupRoles`   as RolesAdmin admin              (optional) revokes admin role granted in step 2.
contract LZBridgeGatewayL2Batch is BatchScriptV2 {
    // =========== ERRORS =========== //

    error LZBridgeGatewayL2Batch_CanonicalChain();
    error LZBridgeGatewayL2Batch_UnsupportedChain();

    // =========== CONSTANTS =========== //

    /// @dev Role constants.
    bytes32 internal constant _BRIDGE_ADMIN_ROLE = "bridge_admin";
    bytes32 internal constant _BRIDGE_FACILITATOR_ROLE = "bridge_facilitator";

    // =========== ENTRY POINTS =========== //

    /// @notice Step 1. Kernel executor actions: deactivate the old bridge, activate the new
    ///         gateway and LZEndpointDelegate policies.
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
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address kernel = _envAddressNotZero("olympus.Kernel");
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        address delegateAddr = _envAddressNotZero("olympus.policies.LZEndpointDelegate");

        console2.log(
            "\n=== [L2] [Step 1] Deactivate Old Gateway & Activate New Gateway + Delegate:",
            chain,
            "==="
        );

        // Pre-flight invariant: the LZEndpointDelegate policy must be deployed for this gateway.
        // Caught here so a misconfigured env.json fails before the multisig collects step 2 / 3
        // signatures; step 3 repeats the same check as defence in depth.
        // solhint-disable-next-line custom-errors,gas-custom-errors
        require(
            ILZEndpointDelegate(delegateAddr).GATEWAY() == gatewayAddr,
            "LZEndpointDelegate GATEWAY mismatch"
        );

        // 1.1. Deactivate the old CrossChainBridge
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldBridge
            )
        );

        // 1.2. Activate the new LZBridgeGateway
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                gatewayAddr
            )
        );

        // 1.3. Activate the new LZEndpointDelegate policy. The delegate policy is the steady-state
        //      LZ endpoint delegate for the gateway, set in step 3 via `setDelegate`.
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                delegateAddr
            )
        );

        _setPostBatchValidateSelector(this._validateActivateGateway.selector);

        proposeBatch();
    }

    /// @notice Step 2. RolesAdmin admin actions: grant bridge_admin, admin, and bridge_facilitator roles.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function grantRoles(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address rolesAdminAddr = _envAddressNotZero("olympus.policies.RolesAdmin");
        address daoMS = _envAddressNotZero("olympus.multisig.dao");
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");
        ROLESv1 rolesModule = ROLESv1(_envAddressNotZero("olympus.modules.OlympusRoles"));

        console2.log("\n=== [L2] [Step 2] Grant Roles:", chain, "===");

        // 2.1. Grant bridge_admin role to the DAO MS
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(daoMS, _BRIDGE_ADMIN_ROLE)) {
            addToBatch(
                rolesAdminAddr,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    _BRIDGE_ADMIN_ROLE,
                    daoMS
                )
            );
        }

        // 2.1b. Grant manager role to the DAO MS so it can re-enable the gateway after
        //       a disable, within the grace window.
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(daoMS, MANAGER_ROLE)) {
            addToBatch(
                rolesAdminAddr,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    MANAGER_ROLE,
                    daoMS
                )
            );
        }

        // 2.2. Grant admin role to the DAO MS (run revokeSetupRoles after migration if granted here)
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(daoMS, ADMIN_ROLE)) {
            addToBatch(
                rolesAdminAddr,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    ADMIN_ROLE,
                    daoMS
                )
            );
            console2.log("  admin role GRANTED to DAO MS, so run revokeSetupRoles after migration");
        } else {
            console2.log("  admin role already present on DAO MS, so revokeSetupRoles not needed");
        }

        // 2.3. Grant bridge_facilitator role to LZCrossChainBridge
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(bridgeAddr, _BRIDGE_FACILITATOR_ROLE)) {
            addToBatch(
                rolesAdminAddr,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    _BRIDGE_FACILITATOR_ROLE,
                    bridgeAddr
                )
            );
        }

        _setPostBatchValidateSelector(this._validateGrantRoles.selector);

        proposeBatch();
    }

    /// @notice Step 3. DAO MS actions (requires bridge_admin & admin roles):
    ///         LZ config, peers, enforced options, and enable.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function configureAndEnable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        address delegateAddr = _envAddressNotZero("olympus.policies.LZEndpointDelegate");
        LZBridgeGateway gateway = LZBridgeGateway(gatewayAddr);
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(gateway.LZ_ENDPOINT());

        console2.log("\n=== [L2] [Step 3] Configure & Enable:", chain, "===");

        // Pre-flight invariant: the LZEndpointDelegate policy must be deployed for this gateway.
        // solhint-disable-next-line custom-errors,gas-custom-errors
        require(
            ILZEndpointDelegate(delegateAddr).GATEWAY() == gatewayAddr,
            "LZEndpointDelegate GATEWAY mismatch"
        );

        // 3.1. Point the gateway's LZ endpoint delegate at the LZEndpointDelegate policy. This is
        //      the steady-state configuration; the subsequent OApp-authorized endpoint calls in
        //      step 3.2 are forwarded through the delegate contract. Skipped if the delegate is
        //      already pointed at the same address; reverts on a foreign delegate so the batch
        //      does not silently overwrite it.
        _setDelegateIfNeeded(endpoint, gatewayAddr, delegateAddr);

        // 3.2. Configure LZ libraries and ULN/Executor config via LZEndpointDelegate. Library
        //      pinning is skipped per EID when the gateway is already pinned to the expected
        //      library (otherwise `EndpointV2.setSendLibrary` / `setReceiveLibrary` reverts with
        //      `LZ_SameValue` on a repeat run).
        _configureLZ(delegateAddr, endpoint, gatewayAddr);

        // 3.3. Set peers on the gateway
        _setPeers(gateway);

        // 3.4. Set enforced options on the gateway
        _setEnforcedOptions(gateway);

        // 3.5. Enable LZBridgeGateway (skipped if already enabled; `EnablerV2.enable` reverts
        //      on a repeat call via the `givenDisabled` modifier).
        if (gateway.isEnabled()) {
            console2.log("  Gateway already enabled. Skipping enable.");
        } else {
            addToBatch(gatewayAddr, abi.encodeWithSelector(IEnabler.enable.selector, ""));
        }

        _setPostBatchValidateSelector(this._validateConfigureAndEnable.selector);

        proposeBatch();
    }

    /// @notice Conditional `setDelegate` for the gateway's LZ endpoint delegate.
    /// @dev Skips the call when the delegate is already pointed at `delegateAddr_`. Reverts in
    ///      preflight when some foreign delegate is configured so the batch does not silently
    ///      overwrite it.
    function _setDelegateIfNeeded(
        ILayerZeroEndpointV2 endpoint_,
        address gatewayAddr_,
        address delegateAddr_
    ) internal {
        address currentDelegate = IEndpointV2State(address(endpoint_)).delegates(gatewayAddr_);
        if (currentDelegate == delegateAddr_) {
            console2.log("  LZ endpoint delegate already set. Skipping setDelegate.");
            return;
        }
        if (currentDelegate != address(0)) {
            // solhint-disable-next-line custom-errors,gas-custom-errors
            revert(
                "LZ endpoint delegate is already set to a foreign address; refusing to overwrite"
            );
        }
        addToBatch(gatewayAddr_, abi.encodeCall(ILZBridgeGateway.setDelegate, (delegateAddr_)));
    }

    /// @notice Step 4 (optional). Revoke the admin role from the DAO MS.
    ///         Only run on chains where `grantRoles` (step 2) reported that the admin role
    ///         was granted. Skip on chains where the DAO MS already had the role.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function revokeSetupRoles(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address rolesAdminAddr = _envAddressNotZero("olympus.policies.RolesAdmin");
        address daoMS = _envAddressNotZero("olympus.multisig.dao");
        ROLESv1 rolesModule = ROLESv1(_envAddressNotZero("olympus.modules.OlympusRoles"));

        console2.log("\n=== [L2] [Step 4] Revoke Setup Roles:", chain, "===");

        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(daoMS, ADMIN_ROLE)) {
            revert("DAO MS does not have admin role - nothing to revoke");
        }

        addToBatch(
            rolesAdminAddr,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                ADMIN_ROLE,
                daoMS
            )
        );

        _setPostBatchValidateSelector(this._validateRevokeSetupRoles.selector);

        proposeBatch();
    }

    // =========== VALIDATION =========== //

    /// @notice Validate activateGateway state after batch execution.
    /// @dev Checks that the old bridge is deactivated and the new gateway and delegate are active.
    function _validateActivateGateway() external view {
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        address delegateAddr = _envAddressNotZero("olympus.policies.LZEndpointDelegate");

        console2.log("\nValidating activateGateway post-batch state");

        if (Policy(oldBridge).isActive()) {
            revert("Old CrossChainBridge is still active in the Kernel");
        }
        console2.log("  Old CrossChainBridge is deactivated");

        if (!LZBridgeGateway(gatewayAddr).isActive()) {
            revert("LZBridgeGateway is not active in the Kernel");
        }
        console2.log("  LZBridgeGateway is active in the Kernel");

        if (!Policy(delegateAddr).isActive()) {
            revert("LZEndpointDelegate is not active in the Kernel");
        }
        console2.log("  LZEndpointDelegate is active in the Kernel");

        console2.log("activateGateway post-batch validation passed");
    }

    /// @notice Validate grantRoles state after batch execution.
    /// @dev Checks that DAO MS has bridge_admin and admin roles, and bridge has facilitator role.
    function _validateGrantRoles() external view {
        address daoMS = _envAddressNotZero("olympus.multisig.dao");
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");
        ROLESv1 rolesModule = ROLESv1(_envAddressNotZero("olympus.modules.OlympusRoles"));

        console2.log("\nValidating grantRoles post-batch state");

        if (!rolesModule.hasRole(daoMS, _BRIDGE_ADMIN_ROLE)) {
            revert("DAO MS does not have bridge_admin role");
        }
        console2.log("  DAO MS has bridge_admin role");

        if (!rolesModule.hasRole(daoMS, MANAGER_ROLE)) {
            revert("DAO MS does not have manager role");
        }
        console2.log("  DAO MS has manager role");

        if (!rolesModule.hasRole(daoMS, ADMIN_ROLE)) {
            revert("DAO MS does not have admin role");
        }
        console2.log("  DAO MS has admin role");

        if (!rolesModule.hasRole(bridgeAddr, _BRIDGE_FACILITATOR_ROLE)) {
            revert("LZCrossChainBridge does not have bridge_facilitator role");
        }
        console2.log("  LZCrossChainBridge has bridge_facilitator role");

        console2.log("grantRoles post-batch validation passed");
    }

    /// @notice Validate configureAndEnable state after batch execution.
    /// @dev Mirrors LZBridgeSecurityUpgradeProposal._validateLZConfig for L2 chains.
    ///      Checks that the LZEndpointDelegate policy is the gateway's LZ endpoint delegate, the
    ///      gateway is enabled, peers are set, enforced options exist, libraries are pinned,
    ///      and ULN/Executor config is correct for every remote EID.
    function _validateConfigureAndEnable() external view {
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        address delegateAddr = _envAddressNotZero("olympus.policies.LZEndpointDelegate");
        LZBridgeGateway gateway = LZBridgeGateway(gatewayAddr);
        uint32 localEid = _getLocalEid();
        uint32[] memory remoteEids = _getRemoteEids();
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(gateway.LZ_ENDPOINT());

        console2.log("\nValidating configureAndEnable post-batch state");

        // 1a. The LZEndpointDelegate policy must be configured as the gateway's LZ endpoint delegate
        address currentDelegate = IEndpointV2State(address(endpoint)).delegates(gatewayAddr);
        if (currentDelegate != delegateAddr) {
            revert("LZEndpointDelegate is not the gateway's LZ endpoint delegate");
        }
        console2.log("  LZEndpointDelegate is the LZ endpoint delegate");

        // 1b. Gateway must be enabled
        if (!gateway.isEnabled()) {
            revert("LZBridgeGateway is not enabled");
        }
        console2.log("  LZBridgeGateway is enabled");

        // 2. Peers must be set for all remote EIDs
        for (uint256 i = 0; i < remoteEids.length; ++i) {
            bytes32 peer = gateway.peers(remoteEids[i]);
            if (peer == bytes32(0)) {
                revert(string.concat("Peer not set for EID ", vm.toString(uint256(remoteEids[i]))));
            }
            console2.log("  Peer set for EID:", remoteEids[i]);
        }

        // 3. Enforced options must be set for all remote EIDs
        uint8 msgType = gateway.MSG_BRIDGE_OHM();
        for (uint256 i = 0; i < remoteEids.length; ++i) {
            bytes memory opts = gateway.enforcedOptions(remoteEids[i], msgType);
            if (opts.length == 0) {
                revert(
                    string.concat(
                        "Enforced options not set for EID ",
                        vm.toString(uint256(remoteEids[i]))
                    )
                );
            }
            console2.log("  Enforced options set for EID:", remoteEids[i]);
        }

        // 4. Libraries + ULN/Executor config must match for all remote EIDs
        address sendLib = LZConfigLib.sendUln302ForEid(localEid);
        address recvLib = LZConfigLib.recvUln302ForEid(localEid);
        uint64 localConf = LZConfigLib.outboundConfirmationsForEid(localEid);
        for (uint256 i = 0; i < remoteEids.length; ++i) {
            uint32 remoteEid = remoteEids[i];
            _validateLibraries(endpoint, gatewayAddr, remoteEid, sendLib, recvLib);
            _validateSendConfig(endpoint, gatewayAddr, localEid, remoteEid, sendLib, localConf);
            _validateRecvConfig(endpoint, gatewayAddr, localEid, remoteEid, recvLib);
        }

        console2.log("configureAndEnable post-batch validation passed");
    }

    /// @notice Validate revokeSetupRoles state after batch execution.
    /// @dev Checks that DAO MS no longer has the admin role.
    function _validateRevokeSetupRoles() external view {
        address daoMS = _envAddressNotZero("olympus.multisig.dao");
        ROLESv1 rolesModule = ROLESv1(_envAddressNotZero("olympus.modules.OlympusRoles"));

        console2.log("\nValidating revokeSetupRoles post-batch state");

        /// forge-lint: disable-next-line(unsafe-typecast)
        if (rolesModule.hasRole(daoMS, ADMIN_ROLE)) {
            revert("DAO MS still has admin role");
        }
        console2.log("  DAO MS admin role revoked");

        console2.log("revokeSetupRoles post-batch validation passed");
    }

    // =========== LZ CONFIGURATION VALIDATION HELPERS =========== //

    /// @notice Verifies that send/receive libraries are pinned to the expected addresses.
    function _validateLibraries(
        ILayerZeroEndpointV2 endpoint_,
        address gateway_,
        uint32 remoteEid_,
        address sendLib_,
        address recvLib_
    ) internal view {
        if (endpoint_.getSendLibrary(gateway_, remoteEid_) != sendLib_) {
            revert(
                string.concat("Send library not pinned for EID ", vm.toString(uint256(remoteEid_)))
            );
        }
        if (endpoint_.isDefaultSendLibrary(gateway_, remoteEid_)) {
            revert(
                string.concat(
                    "Send library is still default for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        (address pinnedRecvLib, bool isDefault) = endpoint_.getReceiveLibrary(gateway_, remoteEid_);
        if (pinnedRecvLib != recvLib_) {
            revert(
                string.concat(
                    "Receive library not pinned for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        if (isDefault) {
            revert(
                string.concat(
                    "Receive library is still default for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        console2.log("  Libraries pinned for EID:", remoteEid_);
    }

    /// @notice Verifies the Send ULN config (DVNs + confirmations) and Executor config.
    /// @dev Reads app-level ULN config via IUlnConfigState to confirm optional DVNs are
    ///      pinned to the NIL sentinel.
    function _validateSendConfig(
        ILayerZeroEndpointV2 endpoint_,
        address gateway_,
        uint32 localEid_,
        uint32 remoteEid_,
        address sendLib_,
        uint64 expectedConf_
    ) internal view {
        bytes memory sendUlnCfg = endpoint_.getConfig(
            gateway_,
            sendLib_,
            remoteEid_,
            LZConfigLib.CONFIG_TYPE_ULN
        );
        if (sendUlnCfg.length == 0) {
            revert(
                string.concat("Send ULN config not set for EID ", vm.toString(uint256(remoteEid_)))
            );
        }
        UlnConfig memory sendUln = abi.decode(sendUlnCfg, (UlnConfig));
        if (sendUln.confirmations != expectedConf_) {
            revert(
                string.concat(
                    "Send ULN confirmations mismatch for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        address[] memory expectedDvns = LZConfigLib.dvnsForRoute(localEid_, remoteEid_);
        if (sendUln.requiredDVNCount != expectedDvns.length) {
            revert(
                string.concat(
                    "Send ULN required DVN count mismatch for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        if (sendUln.requiredDVNs.length != expectedDvns.length) {
            revert(
                string.concat(
                    "Send ULN required DVN array length mismatch for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        for (uint256 d = 0; d < expectedDvns.length; ++d) {
            if (sendUln.requiredDVNs[d] != expectedDvns[d]) {
                revert(
                    string.concat(
                        "Send ULN DVN mismatch for EID ",
                        vm.toString(uint256(remoteEid_))
                    )
                );
            }
        }

        // App-level NIL check: ep.getConfig returns resolved config; raw app config must be
        // explicit NIL so that future LZ default changes cannot drag in optional DVNs.
        UlnConfig memory sendAppUln = IUlnConfigState(sendLib_).getAppUlnConfig(
            gateway_,
            remoteEid_
        );
        if (sendAppUln.optionalDVNCount != type(uint8).max) {
            revert(
                string.concat(
                    "Send ULN optional DVNs must be explicit NIL for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        if (sendAppUln.optionalDVNs.length != 0) {
            revert(
                string.concat(
                    "Send ULN optional DVNs must be empty for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        if (sendAppUln.optionalDVNThreshold != 0) {
            revert(
                string.concat(
                    "Send ULN optional DVN threshold must be 0 for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }

        // Executor config
        bytes memory execCfg = endpoint_.getConfig(
            gateway_,
            sendLib_,
            remoteEid_,
            LZConfigLib.CONFIG_TYPE_EXECUTOR
        );
        if (execCfg.length == 0) {
            revert(
                string.concat("Executor config not set for EID ", vm.toString(uint256(remoteEid_)))
            );
        }
        ExecutorConfig memory exec = abi.decode(execCfg, (ExecutorConfig));
        if (exec.executor != LZConfigLib.executorForEid(localEid_)) {
            revert(
                string.concat(
                    "Executor address mismatch for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        if (exec.maxMessageSize != LZConfigLib.MAX_MESSAGE_SIZE) {
            revert(
                string.concat(
                    "Executor maxMessageSize mismatch for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        console2.log("  Send ULN + Executor config OK for EID:", remoteEid_);
    }

    /// @notice Verifies the Recv ULN config (DVNs + confirmations).
    /// @dev Inbound confirmations equal the remote chain's outbound confirmations.
    function _validateRecvConfig(
        ILayerZeroEndpointV2 endpoint_,
        address gateway_,
        uint32 localEid_,
        uint32 remoteEid_,
        address recvLib_
    ) internal view {
        bytes memory recvUlnCfg = endpoint_.getConfig(
            gateway_,
            recvLib_,
            remoteEid_,
            LZConfigLib.CONFIG_TYPE_ULN
        );
        if (recvUlnCfg.length == 0) {
            revert(
                string.concat("Recv ULN config not set for EID ", vm.toString(uint256(remoteEid_)))
            );
        }
        UlnConfig memory recvUln = abi.decode(recvUlnCfg, (UlnConfig));
        uint64 expectedConf = LZConfigLib.outboundConfirmationsForEid(remoteEid_);
        if (recvUln.confirmations != expectedConf) {
            revert(
                string.concat(
                    "Recv ULN confirmations mismatch for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        address[] memory expectedDvns = LZConfigLib.dvnsForRoute(localEid_, remoteEid_);
        if (recvUln.requiredDVNCount != expectedDvns.length) {
            revert(
                string.concat(
                    "Recv ULN required DVN count mismatch for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        if (recvUln.requiredDVNs.length != expectedDvns.length) {
            revert(
                string.concat(
                    "Recv ULN required DVN array length mismatch for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        for (uint256 d = 0; d < expectedDvns.length; ++d) {
            if (recvUln.requiredDVNs[d] != expectedDvns[d]) {
                revert(
                    string.concat(
                        "Recv ULN DVN mismatch for EID ",
                        vm.toString(uint256(remoteEid_))
                    )
                );
            }
        }

        // App-level NIL check
        UlnConfig memory recvAppUln = IUlnConfigState(recvLib_).getAppUlnConfig(
            gateway_,
            remoteEid_
        );
        if (recvAppUln.optionalDVNCount != type(uint8).max) {
            revert(
                string.concat(
                    "Recv ULN optional DVNs must be explicit NIL for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        if (recvAppUln.optionalDVNs.length != 0) {
            revert(
                string.concat(
                    "Recv ULN optional DVNs must be empty for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        if (recvAppUln.optionalDVNThreshold != 0) {
            revert(
                string.concat(
                    "Recv ULN optional DVN threshold must be 0 for EID ",
                    vm.toString(uint256(remoteEid_))
                )
            );
        }
        console2.log("  Recv ULN config OK for EID:", remoteEid_);
    }

    // =========== LZ CONFIGURATION HELPERS =========== //

    /// @notice Reverts if called on a canonical chain (mainnet/sepolia).
    /// @dev    On canonical chains, LZ config is done via the LZBridgeActivator OCG proposal.
    function _requireNonCanonical() internal view {
        if (ChainUtils._isCanonicalChain(chain)) revert LZBridgeGatewayL2Batch_CanonicalChain();
    }

    /// @notice Configures LZ libraries and ULN/Executor config for all remote chains via the
    ///         LZEndpointDelegate policy's ILZEndpointV2Authorized functions.
    /// @dev    Only for non-canonical (L2) chains. The LZEndpointDelegate policy must already be
    ///         set as the gateway's LZ endpoint delegate when the batch executes.
    ///
    ///         Library pins are skipped per EID when the gateway is already pinned to the same
    ///         library address. `EndpointV2.setSendLibrary` and `setReceiveLibrary` revert with
    ///         `LZ_SameValue` on a no-op re-pin, so unconditional re-application would break a
    ///         repeat run of the batch.
    ///
    ///         ULN/Executor `setConfig` is left unconditional. It is idempotent inside the
    ///         message library and the cost of a no-op repeat (a single SSTORE per slot, all to
    ///         their existing values) is small compared to the gas spent reading and comparing
    ///         the existing config.
    ///
    ///         The DVN set comes from `LZConfigLib.dvnsForRoute`: every route requires four DVNs
    ///         (LayerZero Labs, Canary, Nethermind, plus Google Cloud, or Horizen for routes that
    ///         touch Berachain where Google Cloud is unavailable).
    /// @param  delegateAddr_ The LZEndpointDelegate policy address to forward OApp-authorized
    ///                      endpoint calls through.
    /// @param  endpoint_ The LayerZero V2 endpoint used to read the currently pinned libraries.
    /// @param  gatewayAddr_ The gateway acting as the OApp on the endpoint.
    function _configureLZ(
        address delegateAddr_,
        ILayerZeroEndpointV2 endpoint_,
        address gatewayAddr_
    ) internal {
        uint32[] memory remoteEids = _getRemoteEids();
        uint32 localEid = _getLocalEid();
        address sendLib = _getSendUln302();
        address recvLib = _getRecvUln302();
        uint64 localConf = _outboundConfirmations();

        console2.log("\nConfiguring LZ - sendLib:", sendLib, "recvLib:", recvLib);

        for (uint256 i = 0; i < remoteEids.length; ++i) {
            uint32 remoteEid = remoteEids[i];
            // Four required DVNs per route; the fourth is Google Cloud (or Horizen for routes
            // touching Berachain). See LZConfigLib.dvnsForRoute for the selection rule.
            address[] memory dvns = LZConfigLib.dvnsForRoute(localEid, remoteEid);
            console2.log("  Configuring remote EID:", remoteEid);

            _pinSendLibraryIfNeeded(delegateAddr_, endpoint_, gatewayAddr_, remoteEid, sendLib);
            _pinReceiveLibraryIfNeeded(delegateAddr_, endpoint_, gatewayAddr_, remoteEid, recvLib);

            // Send ULN + Executor config (unconditional; setConfig is idempotent on the message lib).
            SetConfigParam[] memory sendParams = new SetConfigParam[](2);
            sendParams[0] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(localConf, dvns)
            });
            sendParams[1] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_EXECUTOR,
                config: LZConfigLib.encodeExecutorConfig(localEid)
            });
            addToBatch(
                delegateAddr_,
                abi.encodeCall(ILZEndpointV2Authorized.setEndpointConfig, (sendLib, sendParams))
            );

            // Receive ULN config (inbound confirmations = the remote chain's outbound confirmations).
            uint64 remoteConf = LZConfigLib.outboundConfirmationsForEid(remoteEid);
            SetConfigParam[] memory recvParams = new SetConfigParam[](1);
            recvParams[0] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(remoteConf, dvns)
            });
            addToBatch(
                delegateAddr_,
                abi.encodeCall(ILZEndpointV2Authorized.setEndpointConfig, (recvLib, recvParams))
            );
        }
    }

    /// @dev Pins the gateway's send library for `remoteEid_` to `sendLib_`. Skipped when the
    ///      library is already pinned (not falling back to the default) to the expected
    ///      address, otherwise `EndpointV2.setSendLibrary` reverts with `LZ_SameValue`.
    function _pinSendLibraryIfNeeded(
        address delegateAddr_,
        ILayerZeroEndpointV2 endpoint_,
        address gatewayAddr_,
        uint32 remoteEid_,
        address sendLib_
    ) private {
        if (
            !endpoint_.isDefaultSendLibrary(gatewayAddr_, remoteEid_) &&
            endpoint_.getSendLibrary(gatewayAddr_, remoteEid_) == sendLib_
        ) {
            console2.log("    Send library already pinned for EID:", remoteEid_);
            return;
        }
        addToBatch(
            delegateAddr_,
            abi.encodeCall(ILZEndpointV2Authorized.setSendLibrary, (remoteEid_, sendLib_))
        );
    }

    /// @dev Pins the gateway's receive library for `remoteEid_` to `recvLib_`. Skipped when the
    ///      library is already pinned (not falling back to the default) to the expected
    ///      address, otherwise `EndpointV2.setReceiveLibrary` reverts with `LZ_SameValue`.
    function _pinReceiveLibraryIfNeeded(
        address delegateAddr_,
        ILayerZeroEndpointV2 endpoint_,
        address gatewayAddr_,
        uint32 remoteEid_,
        address recvLib_
    ) private {
        (address currentRecvLib, bool isDefault) = endpoint_.getReceiveLibrary(
            gatewayAddr_,
            remoteEid_
        );
        if (!isDefault && currentRecvLib == recvLib_) {
            console2.log("    Receive library already pinned for EID:", remoteEid_);
            return;
        }
        addToBatch(
            delegateAddr_,
            abi.encodeCall(ILZEndpointV2Authorized.setReceiveLibrary, (remoteEid_, recvLib_, 0))
        );
    }

    /// @notice Sets peers for all remote chains from env.json addresses.
    function _setPeers(LZBridgeGateway gateway_) internal {
        address gatewayAddr = address(gateway_);
        string[] memory remoteChains = _getRemoteChainNames();
        uint32[] memory remoteEids = _getRemoteEids();

        console2.log("\nSetting peers");

        for (uint256 i = 0; i < remoteChains.length; ++i) {
            address remoteGateway = _envAddressNotZero(
                remoteChains[i],
                "olympus.policies.LZBridgeGateway"
            );
            bytes32 peer = LZConfigLib.addressToBytes32(remoteGateway);
            console2.log("  EID", remoteEids[i], "->", remoteGateway);

            addToBatch(
                gatewayAddr,
                abi.encodeCall(ILZBridgeGateway.setPeer, (remoteEids[i], peer))
            );
        }
    }

    /// @notice Sets enforced options for all remote chains.
    function _setEnforcedOptions(LZBridgeGateway gateway_) internal {
        address gatewayAddr = address(gateway_);
        uint32[] memory remoteEids = _getRemoteEids();
        uint8 msgBridgeOhm = gateway_.MSG_BRIDGE_OHM();

        console2.log("\nSetting enforced options");

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](remoteEids.length);

        for (uint256 i = 0; i < remoteEids.length; ++i) {
            // Type 3 options: WORKER_ID=1, size=17, OPTION_TYPE_LZRECEIVE=1, gas=200k
            bytes memory options = abi.encodePacked(
                uint16(3),
                uint8(1),
                uint16(17),
                uint8(1),
                uint128(200_000)
            );
            opts[i] = EnforcedOptionParam({
                eid: remoteEids[i],
                msgType: msgBridgeOhm,
                options: options
            });
        }

        addToBatch(gatewayAddr, abi.encodeCall(ILZBridgeGateway.setEnforcedOptions, (opts)));
    }

    // =========== CHAIN-SPECIFIC HELPERS =========== //

    /// @notice Returns the local EID for the current chain.
    function _getLocalEid() internal view returns (uint32) {
        if (_isChain("mainnet")) return LZConfigLib.ETH_EID;
        if (_isChain("arbitrum")) return LZConfigLib.ARB_EID;
        if (_isChain("optimism")) return LZConfigLib.OPT_EID;
        if (_isChain("base")) return LZConfigLib.BASE_EID;
        if (_isChain("berachain")) return LZConfigLib.BERA_EID;
        revert LZBridgeGatewayL2Batch_UnsupportedChain();
    }

    /// @notice Returns the remote EIDs for the current chain.
    /// @dev Topology: full mesh, every chain peers with all 4 others.
    function _getRemoteEids() internal view returns (uint32[] memory eids) {
        if (_isChain("mainnet")) {
            eids = new uint32[](4);
            eids[0] = LZConfigLib.ARB_EID;
            eids[1] = LZConfigLib.OPT_EID;
            eids[2] = LZConfigLib.BASE_EID;
            eids[3] = LZConfigLib.BERA_EID;
        } else if (_isChain("arbitrum")) {
            eids = new uint32[](4);
            eids[0] = LZConfigLib.ETH_EID;
            eids[1] = LZConfigLib.OPT_EID;
            eids[2] = LZConfigLib.BASE_EID;
            eids[3] = LZConfigLib.BERA_EID;
        } else if (_isChain("optimism")) {
            eids = new uint32[](4);
            eids[0] = LZConfigLib.ETH_EID;
            eids[1] = LZConfigLib.ARB_EID;
            eids[2] = LZConfigLib.BASE_EID;
            eids[3] = LZConfigLib.BERA_EID;
        } else if (_isChain("base")) {
            eids = new uint32[](4);
            eids[0] = LZConfigLib.ETH_EID;
            eids[1] = LZConfigLib.ARB_EID;
            eids[2] = LZConfigLib.OPT_EID;
            eids[3] = LZConfigLib.BERA_EID;
        } else if (_isChain("berachain")) {
            eids = new uint32[](4);
            eids[0] = LZConfigLib.ETH_EID;
            eids[1] = LZConfigLib.ARB_EID;
            eids[2] = LZConfigLib.OPT_EID;
            eids[3] = LZConfigLib.BASE_EID;
        } else {
            revert LZBridgeGatewayL2Batch_UnsupportedChain();
        }
    }

    /// @notice Returns the remote chain names (env.json keys) for the current chain.
    /// @dev Array length matches _getRemoteEids(). All chains have 4 remotes.
    function _getRemoteChainNames() internal view returns (string[] memory names) {
        if (_isChain("mainnet")) {
            names = new string[](4);
            names[0] = "arbitrum";
            names[1] = "optimism";
            names[2] = "base";
            names[3] = "berachain";
        } else if (_isChain("arbitrum")) {
            names = new string[](4);
            names[0] = "mainnet";
            names[1] = "optimism";
            names[2] = "base";
            names[3] = "berachain";
        } else if (_isChain("optimism")) {
            names = new string[](4);
            names[0] = "mainnet";
            names[1] = "arbitrum";
            names[2] = "base";
            names[3] = "berachain";
        } else if (_isChain("base")) {
            names = new string[](4);
            names[0] = "mainnet";
            names[1] = "arbitrum";
            names[2] = "optimism";
            names[3] = "berachain";
        } else if (_isChain("berachain")) {
            names = new string[](4);
            names[0] = "mainnet";
            names[1] = "arbitrum";
            names[2] = "optimism";
            names[3] = "base";
        } else {
            revert LZBridgeGatewayL2Batch_UnsupportedChain();
        }
    }

    /// @notice Returns the SendUln302 address for the current chain.
    function _getSendUln302() internal view returns (address) {
        return LZConfigLib.sendUln302ForEid(_getLocalEid());
    }

    /// @notice Returns the ReceiveUln302 address for the current chain.
    function _getRecvUln302() internal view returns (address) {
        return LZConfigLib.recvUln302ForEid(_getLocalEid());
    }

    /// @notice Returns the outbound confirmation count for the current chain.
    function _outboundConfirmations() internal view returns (uint64) {
        return LZConfigLib.outboundConfirmationsForEid(_getLocalEid());
    }

    /// @notice Checks if the current chain matches the given name.
    function _isChain(string memory name_) internal view returns (bool) {
        return keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked(name_));
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
