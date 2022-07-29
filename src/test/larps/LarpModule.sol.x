// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Kernel, Module} from "../../Kernel.sol";

contract LarpModule is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (bytes5) {
        return "LARPR";
    }
}
