// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Kernel, Policy} from "../../Kernel.sol";

contract LarpPolicy is Policy {
    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureReads() external override onlyKernel {}

    function requestRoles()
        external
        view
        override
        onlyKernel
        returns (Role[] memory roles)
    {
        roles = new Role[](1);
        permissions[0] = "LARPR";
    }
}
