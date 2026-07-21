// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

import {Keycode, Module, toKeycode} from "src/Kernel.sol";
import {ISubmodule} from "src/interfaces/ISubmodule.sol";
import {Submodule, SubKeycode, toSubKeycode} from "src/Submodules.sol";

/// @notice Mock submodule that does not implement ISubmodule correctly
/// @dev    This contract does NOT implement supportsInterface properly, so it should fail validation
contract MockInvalidSubmodule is Submodule {
    constructor(Module parent_) Submodule(parent_) {}

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.INVALID");
    }

    function PARENT() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    /// @notice This implementation returns false for ISubmodule interface ID
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        // Always return false for ISubmodule interface ID, making this contract fail validation
        return interfaceId != type(ISubmodule).interfaceId;
    }
}
/// forge-lint: disable-end(mixed-case-function)
