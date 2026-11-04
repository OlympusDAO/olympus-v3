// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {Kernel} from "src/Kernel.sol";

import {IMockPolicyAdmin} from "./IMockPolicyAdmin.sol";
import {MockPolicyAdmin} from "./MockPolicyAdmin.sol";
import {PolicyAdminOnlyAdminRoleTests} from "./PolicyAdminOnlyAdminRoleTests.sol";

/// @notice Runs the shared `onlyAdminRole` tests against the `PolicyAdmin` mix-in.
contract PolicyAdmin_OnlyAdminRoleTest is PolicyAdminOnlyAdminRoleTests {
    function _deployPolicyAdmin(Kernel kernel_) internal override returns (IMockPolicyAdmin) {
        return new MockPolicyAdmin(kernel_);
    }
}
