// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

/**
 * @notice Mock policy to allow testing gated module functions
 */
contract MockModuleWriter is Policy {
    Module internal _module;
    Permissions[] internal _requests;

    constructor(Kernel kernel_, Module module_, Permissions[] memory requests_) Policy(kernel_) {
        _module = module_;
        uint256 len = requests_.length;
        for (uint256 i; i < len; i++) {
            _requests.push(requests_[i]);
        }
    }

    /* ========== FRAMEWORK CONFIFURATION ========== */
    function configureDependencies() external override returns (Keycode[] memory dependencies) {}

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory requests)
    {
        uint256 len = _requests.length;
        requests = new Permissions[](len);
        for (uint256 i; i < len; i++) {
            requests[i] = _requests[i];
        }
    }

    /* ========== DELEGATE TO MODULE ========== */
    // solhint-disable-next-line no-complex-fallback, payable-fallback
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