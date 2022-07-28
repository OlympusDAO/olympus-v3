// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import {Kernel, Module, Policy} from "src/Kernel.sol";

/**
 * @notice Mock policy to allow testing gated module functions
 */
contract MockModuleWriter is Policy {
    Module internal module;

    constructor(Kernel kernel_, Module module_) Policy(kernel_) {
        module = module_;
    }

    /* ========== FRAMEWORK CONFIFURATION ========== */
    function configureReads() external override {}

    function requestRoles()
        external
        view
        override
        returns (Role[] memory roles)
    {
        roles = module.ROLES();
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
