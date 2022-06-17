// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Kernel, Module, Policy} from "../../Kernel.sol";

/**
 * @notice Larp policy to allow testing gated module functions
 */
contract LarpModuleWriter is Policy {
    Module internal module;

    constructor(Kernel kernel_, Module module_) Policy(kernel_) {
        module = module_;
    }

    /* ========== FRAMEWORK CONFIFURATION ========== */
    function configureReads() external override onlyKernel {}

    function requestRoles()
        external
        view
        override
        onlyKernel
        returns (Kernel.Role[] memory roles)
    {
        roles = new Kernel.Role[](1);
        permissions[0] = module.KEYCODE();
    }

    /* ========== DELEGATE TO MODULE ========== */
    fallback(bytes calldata input) external returns (bytes memory) {
        (bool success, bytes memory output) = address(module).call(input);
        if (!success) {
            if (output.length == 0) revert();
            assembly {
                revert(add(32, output), mload(output))
            }
        }
        return output;
    }
}
