// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyAdminOptimized} from "src/policies/utils/PolicyAdminOptimized.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

import {IMockPolicyAdmin} from "../PolicyAdmin/IMockPolicyAdmin.sol";

/// @notice Test harness that exposes the `PolicyAdminOptimized` mix-in modifiers as gated functions.
contract MockPolicyAdminOptimized is Policy, PolicyAdminOptimized, IMockPolicyAdmin {
    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        return dependencies;
    }

    /// @inheritdoc IMockPolicyAdmin
    function gatedToAdminRole() external view override onlyAdminRole returns (bool) {
        return true;
    }

    /// @inheritdoc IMockPolicyAdmin
    function gatedToEmergencyRole() external view override onlyEmergencyRole returns (bool) {
        return true;
    }

    /// @inheritdoc IMockPolicyAdmin
    function gatedToManagerRole() external view override onlyManagerRole returns (bool) {
        return true;
    }

    /// @inheritdoc IMockPolicyAdmin
    function gatedToEmergencyOrAdminRole()
        external
        view
        override
        onlyEmergencyOrAdminRole
        returns (bool)
    {
        return true;
    }

    /// @inheritdoc IMockPolicyAdmin
    function gatedToManagerOrAdminRole()
        external
        view
        override
        onlyManagerOrAdminRole
        returns (bool)
    {
        return true;
    }
}
