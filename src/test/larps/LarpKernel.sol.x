// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "../../Kernel.sol";

// Kernel for testing purposes
contract LarpKernel is Kernel {
    function installModule(address module_) external {
        bytes5 keycode = Module(module_).KEYCODE();
        getModuleForKeycode[keycode] = module_;
        getKeycodeForModule[module_] = keycode;
    }

    function grantWritePermissions(bytes5 keycode_, address policy_) external {
        getWritePermissions[keycode_][policy_] = true;
        approvedPolicies[policy_] = true;
    }
}
