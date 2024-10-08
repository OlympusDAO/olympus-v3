// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Kernel, Policy, Keycode, toKeycode, Permissions} from "src/Kernel.sol";
import {EXREGv1} from "src/modules/EXREG/EXREG.v1.sol";

contract MockExternalRegistryPolicy is Policy {
    address public dai;

    EXREGv1 public exreg;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("EXREG");

        // Populate module dependencies
        exreg = EXREGv1(getModuleAddress(dependencies[0]));

        // Populate variables
        // This function will be called whenever a contract is registered or deregistered, which enables caching of the values
        dai = exreg.getContract("dai");

        return dependencies;
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);

        return requests;
    }
}
