// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";

contract MockConfigUnsupportedFloan is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("FLOAN");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (2, 0);
    }
}
