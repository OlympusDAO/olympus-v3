// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

// TODO Index module

import {Kernel, Module} from "../Kernel.sol";

contract Index is Module {
    uint256 public index;
    uint256 public lastUpdated;

    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() external pure override returns (bytes3) {
        return "IDX";
    }

    function getLatestIndex() external view returns (uint256, uint256) {
        return (index, lastUpdated);
    }
}
