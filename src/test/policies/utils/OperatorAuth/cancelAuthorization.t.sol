// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {OperatorAuthTest} from "../OperatorAuth.t.sol";

contract OperatorAuthCancelAuthorizationTest is OperatorAuthTest {
    function test_cancelAuthorization_givenNoAuthorizationExists_clearsWithoutRevert() public {
        vm.expectEmit(address(auth));
        emit AuthorizationSet(owner, owner, operator, 0);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationDeadlines(owner, operator), 0, "stored deadline");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "authorized after cancel");
    }

    function test_cancelAuthorization_givenDirectAuthorizationExists_clearsAuthorization() public {
        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));
        assertEq(auth.isSenderAuthorized(operator, owner), true, "authorized before cancel");

        vm.expectEmit(address(auth));
        emit AuthorizationSet(owner, owner, operator, 0);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationDeadlines(owner, operator), 0, "stored deadline");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "authorized after cancel");
    }

    function test_cancelAuthorization_givenSignedAuthorizationExists_clearsAuthorization() public {
        _submitValidAuthorization(uint48(block.timestamp + 1 days));
        assertEq(auth.isSenderAuthorized(operator, owner), true, "authorized before cancel");

        vm.expectEmit(address(auth));
        emit AuthorizationSet(owner, owner, operator, 0);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationDeadlines(owner, operator), 0, "stored deadline");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "authorized after cancel");
    }

    function test_cancelAuthorization_givenExistingNonce() public {
        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));
        uint256 nonceBefore = auth.authorizationNonces(owner);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationNonces(owner), nonceBefore + 1, "nonce after cancellation");
    }

    function test_cancelAuthorization_givenPendingSignature_invalidatesSignature() public {
        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                uint48(block.timestamp + 2 days),
                auth.authorizationNonces(owner),
                uint48(block.timestamp + 1 hours)
            );

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidNonce.selector,
                authorization.nonce
            )
        );
        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(
            auth.authorizationNonces(owner),
            authorization.nonce + 1,
            "nonce after cancellation"
        );
        assertEq(auth.authorizationDeadlines(owner, operator), 0, "cancelled authorization");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "operator after cancellation");
    }

    function test_cancelAuthorization_givenCallerIsNotOwner_clearsOnlyCallerAuthorization() public {
        uint48 ownerDeadline = uint48(block.timestamp + 1 days);
        _setAuthorizationAndExpectEvent(owner, operator, ownerDeadline);

        vm.prank(caller);
        auth.setAuthorization(operator, uint48(block.timestamp + 2 days));

        vm.prank(caller);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationDeadlines(caller, operator), 0, "caller authorization");
        assertEq(
            auth.authorizationDeadlines(owner, operator),
            ownerDeadline,
            "owner authorization"
        );
        assertEq(auth.isSenderAuthorized(operator, owner), true, "owner still authorized");
    }
}
