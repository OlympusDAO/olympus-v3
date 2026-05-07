// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Contracts
import {EnablerV2} from "src/libraries/EnablerV2.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

/// @title PolicyEnablerV2
/// @notice An abstract policy mix-in that wires `EnablerV2` to the role-based
///         access control exposed by `PolicyAdmin`.
/// @dev The mix-in restricts `enable` to the admin role and `disable` to
///      either the admin or the emergency role, matching the access pattern
///      of the legacy `PolicyEnabler`. Inheriting policies are expected to
///      override `_beforeEnable` and `_beforeDisable` when implementation
///      specific state changes are required, and to assign the `ROLES`
///      module address inside `configureDependencies`.
///
///      The mix-in does not introduce any storage variables of its own and
///      does not modify the `IEnabler` wire-level surface, so legacy callers
///      that target the `IEnabler` interface continue to interoperate with
///      policies that derive from this contract.
abstract contract PolicyEnablerV2 is EnablerV2, PolicyAdmin {
    // ========== INITIALIZATION ========== //

    constructor() {}

    // ========== HOOKS ========== //

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - The caller does not hold the admin role.
    function _authorizeEnable(bytes calldata) internal override onlyAdminRole {}

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - The caller holds neither the admin role nor the emergency role.
    function _authorizeDisable(bytes calldata) internal override onlyEmergencyOrAdminRole {}
}
