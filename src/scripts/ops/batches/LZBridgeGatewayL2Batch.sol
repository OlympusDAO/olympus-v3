// SPDX-License-Identifier: Unlicensed
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {LZBridgeL2BatchScript} from "./lib/LZBridgeL2BatchScript.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title LZBridgeGatewayL2Batch
/// @notice L2 MS batch scripts for the LZBridgeGateway policy.
///         The periphery LZCrossChainBridge is configured via LZCrossChainBridgeL2Batch.
///
///         Entry points:
///         - `setupL2`: full gateway setup (kernel ops + roles + LZ config + enable)
contract LZBridgeGatewayL2Batch is LZBridgeL2BatchScript {
    // =========== ENTRY POINTS =========== //

    /// @notice Full L2 gateway setup (Arbitrum, Optimism, Base).
    ///         Auto-detects chain from block.chainid.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function setupL2(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address kernel = _envAddressNotZero("olympus.Kernel");
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        address rolesAdminAddr = _envAddressNotZero("olympus.policies.RolesAdmin");
        address daoMS = _envAddressNotZero("olympus.multisig.dao");

        LZBridgeGateway gateway = LZBridgeGateway(gatewayAddr);

        console2.log("\n=== L2 Gateway Setup:", chain, "===");

        // 1. Deactivate old CrossChainBridge
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldBridge
            )
        );

        // 2. Activate new LZBridgeGateway
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                gatewayAddr
            )
        );

        // 3. Grant bridge_admin role to DAO MS
        ROLESv1 rolesModule = ROLESv1(_envAddressNotZero("olympus.modules.OlympusRoles"));
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(daoMS, bytes32("bridge_admin"))) {
            addToBatch(
                rolesAdminAddr,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    bytes32("bridge_admin"),
                    daoMS
                )
            );
        }

        // 4. Grant admin role to DAO MS
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(daoMS, bytes32("admin"))) {
            addToBatch(
                rolesAdminAddr,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    bytes32("admin"),
                    daoMS
                )
            );
        }

        // 5. Configure LZ versions and per-remote config
        _configureLZ(gateway);

        // 6. Set trusted remotes
        _setTrustedRemotes(gateway);

        // 7. Enable LZBridgeGateway
        addToBatch(gatewayAddr, abi.encodeWithSelector(PolicyEnabler.enable.selector, ""));

        // Use custom L2 batch proposal (no heart beat validation)
        _proposeL2Batch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
