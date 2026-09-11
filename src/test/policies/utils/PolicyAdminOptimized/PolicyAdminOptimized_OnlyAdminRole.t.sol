// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Kernel} from "src/Kernel.sol";

import {IMockPolicyAdmin} from "../PolicyAdmin/IMockPolicyAdmin.sol";
import {PolicyAdminOnlyAdminRoleTests} from "../PolicyAdmin/PolicyAdminOnlyAdminRoleTests.sol";
import {MockPolicyAdminOptimized} from "./MockPolicyAdminOptimized.sol";

/// @notice Runs the shared `onlyAdminRole` tests against the `PolicyAdminOptimized` mix-in.
contract PolicyAdminOptimized_OnlyAdminRoleTest is PolicyAdminOnlyAdminRoleTests {
    function _deployPolicyAdmin(Kernel kernel_) internal override returns (IMockPolicyAdmin) {
        return new MockPolicyAdminOptimized(kernel_);
    }
}
