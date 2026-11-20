// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

contract OperatorAuthWallet {
    IOperatorAuth internal immutable _auth;
    address internal immutable _operator;
    bytes32 internal _expected;
    bool internal _valid = true;

    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    constructor(IOperatorAuth auth_, address operator_) {
        _auth = auth_;
        _operator = operator_;
    }

    // forge-lint: disable-end(missing-zero-check)

    function setExpected(bytes32 hash_) external {
        _expected = hash_;
    }

    function setValid(bool valid_) external {
        _valid = valid_;
    }

    function isValidSignature(bytes32 hash_, bytes calldata) external view returns (bytes4) {
        if (!_valid || hash_ != _expected || _auth.pairEpochs(address(this), _operator) != 0)
            return 0xffffffff;
        return 0x1626ba7e;
    }
}
