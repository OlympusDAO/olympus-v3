// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {IKernel, Actions, Module} from "../../Kernel.sol";

// Kernel for testing purposes, in order to interact with modules without
// needing a policy to be created.
contract LarpKernel is IKernel {
    mapping(bytes5 => address) public getModuleForKeycode; // get address for module keycode
    mapping(address => bytes5) public getKeycodeForModule; // get module keycode for contract
    mapping(bytes5 => mapping(address => bool)) public getWritePermissions;
    mapping(address => bool) public approvedPolicies;

    function installModule(address module_) external {
        bytes5 keycode = Module(module_).KEYCODE();
        getModuleForKeycode[keycode] = module_;
        getKeycodeForModule[module_] = keycode;
    }

    function grantWritePermissions(bytes5 keycode_, address policy_) external {
        getWritePermissions[keycode_][policy_] = true;
        approvedPolicies[policy_] = true;
    }

    function executeAction(Actions action_, address target_) external {}
}
