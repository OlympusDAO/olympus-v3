// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {BasePeriodicTaskManager} from "src/bases/BasePeriodicTaskManager.sol";

import {Kernel, Policy, Keycode, toKeycode, Permissions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract MockPeriodicTaskManager is Policy, BasePeriodicTaskManager {
    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(toKeycode("ROLES")));
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {}
}
