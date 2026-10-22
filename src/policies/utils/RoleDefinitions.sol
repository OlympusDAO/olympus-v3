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
/// @dev Bridge administrator role, shared by the LZ and CCIP bridge policies. Typically assigned
///      to the DAO multisig. On the LZ bridge: queue proposer on LZBridgeAndDelegateConfig for the
///      gateway / delegate / periphery configuration helpers, and the caller of
///      LZBridgeGateway's one-shot `initializeBridgedSupply` bootstrap. On the CCIP bridge: queue
///      proposer on CCIPTokenPoolConfigTimelock, the caller of the grace-period `reEnable()` on
///      CCIPTokenPoolConfig and CCIPTokenPoolConfigTimelock, and a caller of the route-containment
///      functions `disableChain` and `disableAllChains` on CCIPTokenPoolConfig.
bytes32 constant BRIDGE_ADMIN_ROLE = "bridge_admin";
/// @dev LZ bridge facilitator role. Typically assigned to the periphery LZCrossChainBridge
///      contract so that it can call LZBridgeGateway.burnAndSend on behalf of users.
bytes32 constant BRIDGE_FACILITATOR_ROLE = "bridge_facilitator";
/// @dev Bridge rate-limit role, shared by the LZ and CCIP bridge policies. On the LZ bridge:
///      queue proposer on LZBridgeAndDelegateConfig for the rate-limit and in-flight-clear
///      helpers. On the CCIP bridge: direct, non-timelocked caller of
///      CCIPTokenPoolConfig.setChainRateLimits, which changes only the rate limits of routes that
///      the pool already serves, and a caller of the route-containment functions `disableChain`
///      and `disableAllChains`. Expected to be unassigned unless governance appoints a dedicated
///      rate-limit operator.
bytes32 constant BRIDGE_RATE_LIMITER_ROLE = "bridge_rate_limiter";
/// @dev LZ bridge channel manager role. Optional dedicated role for the LZEndpointDelegate
///      inbound-channel management primitives (skip, nilify, burn, clear), accepted alongside
///      bridge_admin and admin so that channel management can be delegated without granting
///      the broader bridge_admin role.
bytes32 constant BRIDGE_CHANNEL_MANAGER_ROLE = "bridge_channel_manager";

/// @dev Oracle manager role, e.g. managing oracle deployments.
bytes32 constant ORACLE_MANAGER_ROLE = "oracle_manager";
