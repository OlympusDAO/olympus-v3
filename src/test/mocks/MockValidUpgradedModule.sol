// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {Kernel, Module, Policy} from "../../Kernel.sol";

contract MockValidUpgradedModule is Module {
    Role public constant MOCKROLE = Role.wrap("MOCKY_Role");
    Role public constant NEWROLE = Role.wrap("MOCKY_NewRole");

    uint256 public counter; // counts the number of times roleCall() has been called

    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MOCKY");
    }

    function ROLES() public pure override returns (Role[] memory roles) {
        roles = new Role[](2);
        roles[0] = MOCKROLE;
        roles[1] = NEWROLE;
    }

    function roleCall() external onlyRole(MOCKROLE) {
        ++counter;
    }
}
