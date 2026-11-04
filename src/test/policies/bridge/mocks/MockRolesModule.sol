// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";

/// @notice Installable module carrying the "ROLES" keycode with an unsupported major version.
/// @dev    The kernel accepts it through InstallModule or UpgradeModule; a policy that requires
///         a ROLES major version of one then rejects it inside `configureDependencies`.
contract MockRolesModule is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("ROLES");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (2, 0);
    }
}
