// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";

// This fixture reports all interfaces as supported to isolate version validation.
// forge-lint: disable-next-line(missing-inheritance)
contract MockConfigUnsupportedPrice is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 1);
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}
