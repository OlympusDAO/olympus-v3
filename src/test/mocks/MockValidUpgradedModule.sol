// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import {Kernel, Module, Policy} from "../../Kernel.sol";

contract MockValidUpgradedModule is Module {
    Kernel.Role public constant MOCKROLE = Kernel.Role.wrap("MOCKY_Role");
    Kernel.Role public constant NEWROLE = Kernel.Role.wrap("MOCKY_NewRole");

    uint256 public counter; // counts the number of times roleCall() has been called

    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Kernel.Keycode) {
        return Kernel.Keycode.wrap("MOCKY");
    }

    function ROLES() public pure override returns (Kernel.Role[] memory roles) {
        roles = new Kernel.Role[](2);
        roles[0] = MOCKROLE;
        roles[1] = NEWROLE;
    }

    function roleCall() external onlyRole(MOCKROLE) {
        ++counter;
    }
}
