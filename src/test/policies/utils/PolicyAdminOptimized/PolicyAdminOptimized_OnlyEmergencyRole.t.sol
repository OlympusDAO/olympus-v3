// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {Kernel} from "src/Kernel.sol";

import {IMockPolicyAdmin} from "../PolicyAdmin/IMockPolicyAdmin.sol";
import {PolicyAdminOnlyEmergencyRoleTests} from "../PolicyAdmin/PolicyAdminOnlyEmergencyRoleTests.sol";
import {MockPolicyAdminOptimized} from "./MockPolicyAdminOptimized.sol";

/// @notice Runs the shared `onlyEmergencyRole` tests against the `PolicyAdminOptimized` mix-in.
contract PolicyAdminOptimized_OnlyEmergencyRoleTest is PolicyAdminOnlyEmergencyRoleTests {
    function _deployPolicyAdmin(Kernel kernel_) internal override returns (IMockPolicyAdmin) {
        return new MockPolicyAdminOptimized(kernel_);
    }
}
