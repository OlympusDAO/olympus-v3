// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

import {Keycode, Module, toKeycode} from "src/Kernel.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {SubKeycode, toSubKeycode} from "src/Submodules.sol";

/// @notice Mock submodule that has the required functions but no supportsInterface
/// @dev    This contract does NOT inherit from Submodule, so it lacks supportsInterface entirely
/// @dev    It should fail validation since it doesn't implement ERC-165
contract MockSubmoduleNoERC165 is IVersioned {
    error Submodule_OnlyParent(address caller_);

    /// @notice The parent module for this submodule.
    Module public parent;

    constructor(Module parent_) {
        parent = parent_;
    }

    function SUBKEYCODE() external pure returns (SubKeycode) {
        return toSubKeycode("PRICE.NOERC165");
    }

    function PARENT() external pure returns (Keycode) {
        return toKeycode("PRICE");
    }

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    function INIT() external view {
        if (msg.sender != address(parent)) revert Submodule_OnlyParent(msg.sender);
    }

    /// @notice This contract intentionally does NOT implement supportsInterface
    /// The validation staticcall will fail, and installation should be rejected
}
/// forge-lint: disable-end(mixed-case-function)
