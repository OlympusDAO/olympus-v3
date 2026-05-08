// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnabler} from "src/bases/ReEnabler.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @title PolicyReEnabler
/// @notice An abstract policy mix-in that combines `PolicyEnablerV2` with the
///         parameterless re-enable extension `ReEnabler` and restricts the
///         re-enable entry point to the manager role.
/// @dev The mix-in is intended for policies that should allow a manager to
///      return the contract to the enabled state after a disable
///      without supplying the calldata payload that the original `enable`
///      would require. The admin role is deliberately not granted access to
///      `reEnable`, since an admin caller can always invoke the standard
///      `enable` entry point with the appropriate payload.
///
///      The mix-in does not bound the number of times that `reEnable` may be
///      invoked across the lifetime of the contract, and does not bound the
///      re-enable to a window that follows a `disable`.
abstract contract PolicyReEnabler is ReEnabler, PolicyEnablerV2 {
    // ========== INITIALIZATION ========== //

    constructor() {}

    // ========== HOOKS ========== //

    /// @inheritdoc ReEnabler
    /// @dev Reverts if:
    ///      - The caller does not hold the manager role.
    function _authorizeReEnable() internal view override onlyManagerRole {}

    // ========== ERC-165 ========== //

    /// @inheritdoc EnablerV2
    /// @dev The override resolves the diamond between `ReEnabler` and
    ///      `PolicyEnablerV2` and forwards the lookup through the linearized
    ///      base chain, which advertises `IEnablerV2`, `IReEnabler`,
    ///      and the legacy `IEnabler`.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, ReEnabler) returns (bool) {
        return super.supportsInterface(interfaceId_);
    }
}
