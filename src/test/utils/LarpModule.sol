// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {IKernel, Module} from "../../Kernel.sol";

contract LarpModule is Module {
    constructor(IKernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (bytes5) {
        return "LARPR";
    }

    //function configureReads() external override onlyKernel {
    //    for(uint i=0; i < reads.length; ++i) {
    //    }
    //}
}
