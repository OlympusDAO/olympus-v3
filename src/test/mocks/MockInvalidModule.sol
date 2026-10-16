// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

import "src/Kernel.sol";

contract MockInvalidModule is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("inval");
    }
}
