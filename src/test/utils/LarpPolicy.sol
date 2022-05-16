// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {IKernel, Policy} from "../../Kernel.sol";

contract LarpPolicy is Policy {
    bytes5[] reads;
    bytes5[] writes;

    constructor(IKernel kernel_) Policy(kernel_) {}

    //function configureReads() external override onlyKernel {
    //    for(uint i=0; i < reads.length; ++i) {
    //    }
    //}
}
