// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

import {Kernel} from "src/Kernel.sol";

import {IMockPolicyAdmin} from "../PolicyAdmin/IMockPolicyAdmin.sol";
import {PolicyAdminOnlyManagerOrAdminRoleTests} from "../PolicyAdmin/PolicyAdminOnlyManagerOrAdminRoleTests.sol";
import {MockPolicyAdminOptimized} from "./MockPolicyAdminOptimized.sol";

/// @notice Runs the shared `onlyManagerOrAdminRole` tests against the `PolicyAdminOptimized` mix-in.
contract PolicyAdminOptimized_OnlyManagerOrAdminRoleTest is PolicyAdminOnlyManagerOrAdminRoleTests {
    function _deployPolicyAdmin(Kernel kernel_) internal override returns (IMockPolicyAdmin) {
        return new MockPolicyAdminOptimized(kernel_);
    }
}
