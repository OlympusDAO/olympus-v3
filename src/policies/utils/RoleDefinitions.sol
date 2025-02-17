// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Allows enabling/disabling the protocol/policies in an emergency
bytes32 constant EMERGENCY_ROLE = "emergency";
/// @dev Administrative access, e.g. configuration parameters. Typically assigned to on-chain governance.
bytes32 constant ADMIN_ROLE = "admin";
/// @dev Managerial access, e.g. managing specific protocol parameters. Typically assigned to a multisig/council.
bytes32 constant MANAGER_ROLE = "manager";
