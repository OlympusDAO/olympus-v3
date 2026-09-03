// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {OperatorAuthTest} from "../OperatorAuth.t.sol";

contract OperatorAuthAuthorizationNoncesTest is OperatorAuthTest {
    function test_authorizationNonces_returnsNextSignatureNonce() public {
        assertEq(auth.authorizationNonces(owner), 0, "initial nonce");

        _submitValidAuthorization(uint48(block.timestamp + 1 days));
        assertEq(auth.authorizationNonces(owner), 1, "nonce after first authorization");

        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                otherOperator,
                uint48(block.timestamp + 2 days),
                auth.authorizationNonces(owner),
                uint48(block.timestamp + 1 hours)
            );

        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(auth.authorizationNonces(owner), 2, "nonce after second authorization");
    }
}
