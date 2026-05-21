// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

import {Kernel} from "src/Kernel.sol";

import {IMockPolicyAdmin} from "../PolicyAdmin/IMockPolicyAdmin.sol";
import {PolicyAdminOnlyManagerRoleTests} from "../PolicyAdmin/PolicyAdminOnlyManagerRoleTests.sol";
import {MockPolicyAdminOptimized} from "./MockPolicyAdminOptimized.sol";

/// @notice Runs the shared `onlyManagerRole` tests against the `PolicyAdminOptimized` mix-in.
contract PolicyAdminOptimized_OnlyManagerRoleTest is PolicyAdminOnlyManagerRoleTests {
    function _deployPolicyAdmin(Kernel kernel_) internal override returns (IMockPolicyAdmin) {
        return new MockPolicyAdminOptimized(kernel_);
    }
}
