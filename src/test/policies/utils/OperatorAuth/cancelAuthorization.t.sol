// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {OperatorAuthTest} from "../OperatorAuth.t.sol";

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.
// forge-lint: disable-start(unsafe-typecast)

contract OperatorAuthCancelAuthorizationTest is OperatorAuthTest {
    uint48 internal constant _AUTHORIZATION_VALIDITY = 1 days;
    uint48 internal constant _EXTENDED_AUTHORIZATION_VALIDITY = 2 days;

    function test_cancelAuthorization_givenNoAuthorizationExists_clearsWithoutRevert() public {
        vm.expectEmit(address(auth));
        emit AuthorizationSet(owner, owner, operator, 0);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationDeadlines(owner, operator), 0, "stored deadline");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "authorized after cancel");
    }

    function test_cancelAuthorization_givenDirectAuthorizationExists_clearsAuthorization() public {
        _setAuthorizationAndExpectEvent(
            owner,
            operator,
            uint48(block.timestamp + _AUTHORIZATION_VALIDITY)
        );
        assertEq(auth.isSenderAuthorized(operator, owner), true, "authorized before cancel");

        vm.expectEmit(address(auth));
        emit AuthorizationSet(owner, owner, operator, 0);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationDeadlines(owner, operator), 0, "stored deadline");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "authorized after cancel");
    }

    function test_cancelAuthorization_givenSignedAuthorizationExists_clearsAuthorization() public {
        _submitValidAuthorization(uint48(block.timestamp + _AUTHORIZATION_VALIDITY));
        assertEq(auth.isSenderAuthorized(operator, owner), true, "authorized before cancel");

        vm.expectEmit(address(auth));
        emit AuthorizationSet(owner, owner, operator, 0);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationDeadlines(owner, operator), 0, "stored deadline");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "authorized after cancel");
    }

    function test_cancelAuthorization_givenExistingNonce() public {
        _setAuthorizationAndExpectEvent(
            owner,
            operator,
            uint48(block.timestamp + _AUTHORIZATION_VALIDITY)
        );
        uint256 nonceBefore = auth.authorizationNonces(owner);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationNonces(owner), nonceBefore + 1, "nonce after cancellation");
    }

    function test_cancelAuthorization_givenPendingSignature_invalidatesSignature() public {
        _setAuthorizationAndExpectEvent(
            owner,
            operator,
            uint48(block.timestamp + _AUTHORIZATION_VALIDITY)
        );
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                uint48(block.timestamp + _EXTENDED_AUTHORIZATION_VALIDITY),
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
        uint48 ownerDeadline = uint48(block.timestamp + _AUTHORIZATION_VALIDITY);
        _setAuthorizationAndExpectEvent(owner, operator, ownerDeadline);

        vm.prank(caller);
        auth.setAuthorization(operator, uint48(block.timestamp + _EXTENDED_AUTHORIZATION_VALIDITY));

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

// forge-lint: disable-end(unsafe-typecast)
