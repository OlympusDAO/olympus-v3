// SPDX-License-Identifier: AGPL-3.0-or-later
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
///         On L2 chains the Kernel executor, RolesAdmin admin, and DAO MS may be
///         different addresses. The batch is split into three entry points so each
///         can be run by the correct caller:
///
///         Entry points (run in order):
///         1. `activateGateway`    as Kernel executor               deactivates old bridge and activates new gateway
///         2. `grantRoles`         as RolesAdmin admin              grants bridge_admin & admin roles to DAO MS
///         3. `configureAndEnable` as DAO MS (bridge_admin & admin) configures LZ & trusted remotes and enables
contract LZBridgeGatewayL2Batch is LZBridgeL2BatchScript {
    // =========== ENTRY POINTS =========== //

    /// @notice Step 1. Kernel executor actions: deactivate old bridge, activate new gateway.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function activateGateway(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address kernel = _envAddressNotZero("olympus.Kernel");
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");

        console2.log(
            "\n=== [L2] [Step 1] Deactivate Old Gateway & Activate New Gateway:",
            chain,
            "==="
        );

        // 1.1. Deactivate old CrossChainBridge
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldBridge
            )
        );

        // 1.2. Activate new LZBridgeGateway
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                gatewayAddr
            )
        );

        _proposeL2Batch();
    }

    /// @notice Step 2. RolesAdmin admin actions: grant bridge_admin & admin roles to the DAO MS.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function grantRoles(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address rolesAdminAddr = _envAddressNotZero("olympus.policies.RolesAdmin");
        address daoMS = _envAddressNotZero("olympus.multisig.dao");
        ROLESv1 rolesModule = ROLESv1(_envAddressNotZero("olympus.modules.OlympusRoles"));

        console2.log("\n=== [L2] [Step 2] Grant Roles:", chain, "===");

        // 2.1. Grant bridge_admin role to the DAO MS
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

        // 2.2. Grant admin role to the DAO MS
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

        _proposeL2Batch();
    }

    /// @notice Step 3. DAO MS actions (requires bridge_admin & admin roles):
    ///         LZ config, trusted remotes, and enable.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    function configureAndEnable(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        LZBridgeGateway gateway = LZBridgeGateway(gatewayAddr);

        console2.log("\n=== [L2] [Step 3] Configure & Enable:", chain, "===");

        // 3.1. Configure LZ versions and per-remote config
        _configureLZ(gateway);

        // 3.2. Set trusted remotes
        _setTrustedRemotes(gateway);

        // 3.3. Enable LZBridgeGateway
        addToBatch(gatewayAddr, abi.encodeWithSelector(PolicyEnabler.enable.selector, ""));

        _proposeL2Batch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
