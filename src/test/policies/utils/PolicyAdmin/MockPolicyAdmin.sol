// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract MockPolicyAdmin is Policy, PolicyAdmin {
    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        return dependencies;
    }

    function gatedToAdminRole() external view onlyAdminRole returns (bool) {
        return true;
    }

    function gatedToEmergencyRole() external view onlyEmergencyRole returns (bool) {
        return true;
    }

    function gatedToEmergencyOrAdminRole() external view onlyEmergencyOrAdminRole returns (bool) {
        return true;
    }
}
