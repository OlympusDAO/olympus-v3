// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.0;

import {Keycode} from "src/Kernel.sol";
import {SubKeycode} from "src/Submodules.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

/// @title ISubmodule
/// @notice Interface for Bophades submodules
/// @dev    Submodules are isolated components of a module that can be upgraded independently
interface ISubmodule is IVersioned {
    /// @notice 5 byte identifier for the parent module
    /// @return The keycode of the parent module
    function PARENT() external pure returns (Keycode);

    /// @notice 20 byte identifier for the submodule. First 5 bytes must match PARENT()
    /// @return The subkeycode of this submodule
    function SUBKEYCODE() external pure returns (SubKeycode);

    /// @notice Initialization function for the submodule
    /// @dev    This function is called when the submodule is installed or upgraded by the module
    /// @dev    MUST BE GATED BY onlyParent. Used to encompass any initialization or upgrade logic
    function INIT() external;
}
/// forge-lint: disable-end(mixed-case-function)
