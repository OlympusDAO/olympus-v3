// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Kernel, Module, Policy} from "../../Kernel.sol";

contract MockInvalidModule is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Kernel.Keycode) {
        return Kernel.Keycode.wrap("inval");
    }

    function ROLES() public pure override returns (Kernel.Role[] memory roles) {
        roles = new Kernel.Role[](0);
    }
}
