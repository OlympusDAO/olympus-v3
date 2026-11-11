// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";

contract Auth1271Wallet {
    BurnerLoansAuth public immutable auth;
    address public immutable operator;
    bool public valid = true;

    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    constructor(BurnerLoansAuth auth_, address operator_) {
        auth = auth_;
        operator = operator_;
    }

    // forge-lint: disable-end(missing-zero-check)

    function setValid(bool valid_) external {
        valid = valid_;
    }

    // This controlled Auth mock probes mutation during ERC-1271 STATICCALL; revert data is unused.
    // forge-lint: disable-start(return-bomb)
    function isValidSignature(bytes32, bytes calldata) external returns (bytes4) {
        if (!valid || auth.pairEpochs(address(this), operator) != 0) return bytes4(0);
        // SignatureChecker's STATICCALL propagates static execution to this attempted mutation.
        (bool changed, ) = address(auth).call{gas: 50_000}(
            abi.encodeCall(auth.cancelAllGrants, ())
        );
        if (changed || auth.accountEpochs(address(this)) != 0) return bytes4(0);
        return 0x1626ba7e;
    }
    // forge-lint: disable-end(return-bomb)
}
