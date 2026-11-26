// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {OperatorAuth} from "src/policies/utils/OperatorAuth.sol";

contract DefaultOperatorAuthHarness is OperatorAuth {
    error PermissionsTooLong();

    constructor(uint8 actions_) OperatorAuth(actions_) {}

    function _validatePermissions(IOperatorAuth.Grant calldata g) internal pure override {
        if (g.permissions.length > 320) revert PermissionsTooLong();
    }
}
