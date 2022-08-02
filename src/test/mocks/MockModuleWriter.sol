// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

/**
 * @notice Mock policy to allow testing gated module functions
 */
contract MockModuleWriter is Policy {
    Module internal _module;
    Permissions[] internal _requests;

    constructor(Kernel kernel_, Module module_) Policy(kernel_) {
        _module = module_;
    }

    /* ========== FRAMEWORK CONFIFURATION ========== */
    function configureDependencies() external override returns (Keycode[] memory dependencies) {}

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory requests)
    {
        requests = _requests;
    }

    function setPermissionRequests(Permissions[] memory requests_)
        external
    {
        _requests = requests_;
    }

    /* ========== DELEGATE TO MODULE ========== */
    fallback(bytes calldata input) external returns (bytes memory) {
        (bool success, bytes memory output) = address(_module).call(input);
        if (!success) {
            if (output.length == 0) revert();
            assembly {
                revert(add(32, output), mload(output))
            }
        }
        return output;
    }
}
