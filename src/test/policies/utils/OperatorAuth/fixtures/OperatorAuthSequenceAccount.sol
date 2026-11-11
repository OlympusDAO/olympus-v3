// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

contract OperatorAuthSequenceAccount {
    IOperatorAuth internal immutable _auth;

    constructor(IOperatorAuth auth_) {
        _auth = auth_;
    }

    function approve(IOperatorAuth.Grant calldata grant_) external {
        _auth.approveGrant(grant_);
    }

    function approveTemporary(IOperatorAuth.Grant calldata grant_) external {
        _auth.approveGrant(grant_);
        bytes32 stamp = _auth.captureAuthorization(grant_.account, grant_.operator, 1);
        // Success proves temporary authority remains usable for a second selected action.
        // forge-lint: disable-next-line(unused-return)
        _auth.validateAuthorization(grant_.account, grant_.operator, 2, stamp);
    }

    function cancelPair(address operator_) external {
        _auth.cancelGrant(operator_);
    }

    function cancelAll() external {
        _auth.cancelAllGrants();
    }
}
