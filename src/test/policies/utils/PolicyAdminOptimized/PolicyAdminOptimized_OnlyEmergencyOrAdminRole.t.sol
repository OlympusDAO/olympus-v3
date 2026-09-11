// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Kernel} from "src/Kernel.sol";

import {IMockPolicyAdmin} from "../PolicyAdmin/IMockPolicyAdmin.sol";
import {PolicyAdminOnlyEmergencyOrAdminRoleTests} from "../PolicyAdmin/PolicyAdminOnlyEmergencyOrAdminRoleTests.sol";
import {MockPolicyAdminOptimized} from "./MockPolicyAdminOptimized.sol";

/// @notice Runs the shared `onlyEmergencyOrAdminRole` tests against the `PolicyAdminOptimized` mix-in.
contract PolicyAdminOptimized_OnlyEmergencyOrAdminRoleTest is
    PolicyAdminOnlyEmergencyOrAdminRoleTests
{
    function _deployPolicyAdmin(Kernel kernel_) internal override returns (IMockPolicyAdmin) {
        return new MockPolicyAdminOptimized(kernel_);
    }
}
