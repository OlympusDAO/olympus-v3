// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

import {Kernel} from "src/Kernel.sol";

import {IMockPolicyAdmin} from "./IMockPolicyAdmin.sol";
import {MockPolicyAdmin} from "./MockPolicyAdmin.sol";
import {PolicyAdminOnlyEmergencyRoleTests} from "./PolicyAdminOnlyEmergencyRoleTests.sol";

/// @notice Runs the shared `onlyEmergencyRole` tests against the `PolicyAdmin` mix-in.
contract PolicyAdmin_OnlyEmergencyRoleTest is PolicyAdminOnlyEmergencyRoleTests {
    function _deployPolicyAdmin(Kernel kernel_) internal override returns (IMockPolicyAdmin) {
        return new MockPolicyAdmin(kernel_);
    }
}
