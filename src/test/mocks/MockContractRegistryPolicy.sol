// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Kernel, Policy, Keycode, toKeycode, Permissions} from "src/Kernel.sol";
import {RGSTYv1} from "src/modules/RGSTY/RGSTY.v1.sol";

contract MockContractRegistryPolicy is Policy {
    address public dai;

    RGSTYv1 public RGSTY;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("RGSTY");

        // Populate module dependencies
        RGSTY = RGSTYv1(getModuleAddress(dependencies[0]));

        // Populate variables
        // This function will be called whenever a contract is registered or deregistered, which enables caching of the values
        dai = RGSTY.getContract("dai");

        return dependencies;
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);

        return requests;
    }
}

contract MockImmutableContractRegistryPolicy is Policy {
    address public dai;

    RGSTYv1 public RGSTY;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("RGSTY");

        // Populate module dependencies
        RGSTY = RGSTYv1(getModuleAddress(dependencies[0]));

        // Populate variables
        // This function will be called whenever a contract is registered or deregistered, which enables caching of the values
        dai = RGSTY.getImmutableContract("dai");

        return dependencies;
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);

        return requests;
    }
}
