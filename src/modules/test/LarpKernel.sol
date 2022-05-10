// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {BaseKernel, Actions} from "../../Kernel.sol";

// Kernel for testing purposes
contract LarpKernel is BaseKernel {
    mapping(bytes5 => address) public getModuleForKeycode; // get address for module keycode
    mapping(address => bytes5) public getKeycodeForModule; // get module keycode for contract
    mapping(bytes5 => mapping(address => bool)) public getWritePermissions;

    function installModule(bytes5 keycode_, address module_) external {
        getModuleForKeycode[keycode_] = module_;
        getKeycodeForModule[module_] = keycode_;
    }

    function grantWritePermissions(bytes5 keycode_, address policy_) external {
        getWritePermissions[keycode_][policy_] = true;
    }

    function executeAction(Actions action_, address target_) external {}
}
