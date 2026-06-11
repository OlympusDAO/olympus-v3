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

/// @dev LZ bridge configurator role. Gates the privileged configuration mutators on
///      LZBridgeGateway and LZEndpointDelegate. Expected to be granted exclusively to the
///      LZBridgeAndDelegateConfig policy, in which case calls are dispatched through that
///      policy's timelock queue. Any holder that does not itself enforce a timelock on
///      these mutators should only be granted the role temporarily for bootstrap.
bytes32 constant BRIDGE_CONFIGURATOR_ROLE = "bridge_configurator";
/// @dev LZ bridge administrator role. Queue proposer on LZBridgeAndDelegateConfig for the
///      gateway / delegate / periphery configuration helpers, and the caller of
///      LZBridgeGateway's one-shot `initializeBridgedSupply` bootstrap.
bytes32 constant BRIDGE_ADMIN_ROLE = "bridge_admin";
/// @dev LZ bridge facilitator role. Typically assigned to the periphery LZCrossChainBridge
///      contract so that it can call LZBridgeGateway.burnAndSend on behalf of users.
bytes32 constant BRIDGE_FACILITATOR_ROLE = "bridge_facilitator";
/// @dev LZ bridge rate-limit proposer role. Queue proposer on LZBridgeAndDelegateConfig
///      for the rate-limit and in-flight-clear helpers.
bytes32 constant BRIDGE_RATE_LIMITER_ROLE = "bridge_rate_limiter";
/// @dev LZ bridge channel manager role. Optional dedicated role for the LZEndpointDelegate
///      inbound-channel management primitives (skip, nilify, burn, clear), accepted alongside
///      bridge_admin and admin so that channel management can be delegated without granting
///      the broader bridge_admin role.
bytes32 constant BRIDGE_CHANNEL_MANAGER_ROLE = "bridge_channel_manager";
