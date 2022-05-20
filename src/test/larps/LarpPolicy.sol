// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Kernel, Policy} from "../../Kernel.sol";

contract LarpPolicy is Policy {
    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureReads() external override onlyKernel {}

    function requestWrites()
        external
        view
        override
        onlyKernel
        returns (bytes5[] memory permissions)
    {
        permissions = new bytes5[](1);
        permissions[0] = "LARPR";
    }
}
