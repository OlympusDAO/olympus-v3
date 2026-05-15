// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Allows enabling/disabling the protocol/policies in an emergency
bytes32 constant EMERGENCY_ROLE = "emergency";
/// @dev Administrative access, e.g. configuration parameters. Typically assigned to on-chain governance.
bytes32 constant ADMIN_ROLE = "admin";
/// @dev Managerial access, e.g. managing specific protocol parameters. Typically assigned to a multisig/council.
bytes32 constant MANAGER_ROLE = "manager";
/// @dev Heart role, e.g. performing periodic tasks.
bytes32 constant HEART_ROLE = "heart";

/// @dev LZ bridge configurator role. Held by the LZBridgeAndDelegateConfig policy so that
///      timelocked LayerZero bridge configuration goes through the timelock queue.
///      Direct holders bypass the timelock and should only be granted temporarily for
///      bootstrap.
bytes32 constant BRIDGE_CONFIGURATOR_ROLE = "bridge_configurator";
/// @dev LZ bridge administrator role. After the timelock migration the role is a queue
///      proposer on LZBridgeAndDelegateConfig and the caller of LZBridgeGateway's
///      one-shot initializeBridgedSupply.
bytes32 constant BRIDGE_ADMIN_ROLE = "bridge_admin";
/// @dev LZ bridge facilitator role. Held by the periphery LZCrossChainBridge contract so
///      that it can call LZBridgeGateway.burnAndSend on behalf of users.
bytes32 constant BRIDGE_FACILITATOR_ROLE = "bridge_facilitator";
/// @dev LZ bridge rate-limit proposer role. After the timelock migration it is a queue
///      proposer on LZBridgeAndDelegateConfig for rate-limit and in-flight clear
///      operations.
bytes32 constant BRIDGE_RATE_LIMITER_ROLE = "bridge_rate_limiter";
