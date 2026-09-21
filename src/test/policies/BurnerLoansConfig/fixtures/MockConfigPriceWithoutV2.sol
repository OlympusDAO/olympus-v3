// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";

// This fixture rejects all interfaces to exercise missing PRICE v2 support.
// forge-lint: disable-next-line(missing-inheritance)
contract MockConfigPriceWithoutV2 is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (2, 0);
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}
