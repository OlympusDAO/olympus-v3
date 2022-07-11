// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Kernel, Module, Policy} from "../../Kernel.sol";

contract MockValidModule is Module {
    Kernel.Role public constant MOCKROLE = Kernel.Role.wrap("MOCKY_Role");

    uint256 public counter; // counts the number of times roleCall() has been called

    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Kernel.Keycode) {
        return Kernel.Keycode.wrap("MOCKY");
    }

    function ROLES() public pure override returns (Kernel.Role[] memory roles) {
        roles = new Kernel.Role[](1);
        roles[0] = MOCKROLE;
    }

    function roleCall() external onlyRole(MOCKROLE) {
        ++counter;
    }
}
