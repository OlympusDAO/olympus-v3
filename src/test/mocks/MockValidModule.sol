// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {Kernel, Module, Policy} from "../../Kernel.sol";

contract MockValidModule is Module {
    Role public constant MOCKROLE = Role.wrap("MOCKY_Role");

    uint256 public counter; // counts the number of times roleCall() has been called

    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MOCKY");
    }

    function ROLES() public pure override returns (Role[] memory roles) {
        roles = new Role[](1);
        roles[0] = MOCKROLE;
    }

    function roleCall() external onlyRole(MOCKROLE) {
        ++counter;
    }
}
