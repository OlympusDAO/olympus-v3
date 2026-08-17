// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {OperatorAuthTest} from "../OperatorAuth.t.sol";

contract OperatorAuthSetAuthorizationTest is OperatorAuthTest {
    function test_setAuthorization_givenBeforeDeadline_authorizesOperator() public {
        uint48 deadline = uint48(block.timestamp + 1 days);

        _setAuthorizationAndExpectEvent(owner, operator, deadline);

        assertEq(auth.isSenderAuthorized(operator, owner), true, "authorized before deadline");
    }

    function test_setAuthorization_givenTimestampUpToAndIncludingDeadline_authorizes(
        uint48 deadline_,
        uint48 checkTimestamp_
    ) public {
        uint48 deadline = uint48(bound(deadline_, block.timestamp, type(uint48).max));
        uint48 checkTimestamp = uint48(bound(checkTimestamp_, block.timestamp, deadline));

        _setAuthorizationAndExpectEvent(owner, operator, deadline);
        vm.warp(checkTimestamp);

        assertEq(auth.isSenderAuthorized(operator, owner), true, "authorized through deadline");
    }

    function test_setAuthorization_givenTimestampAfterDeadline_unauthorizes(
        uint48 deadline_,
        uint48 checkTimestamp_
    ) public {
        uint48 deadline = uint48(bound(deadline_, block.timestamp, type(uint48).max - 1));
        uint48 checkTimestamp = uint48(
            bound(checkTimestamp_, uint256(deadline) + 1, type(uint48).max)
        );

        _setAuthorizationAndExpectEvent(owner, operator, deadline);
        vm.warp(checkTimestamp);

        assertEq(auth.isSenderAuthorized(operator, owner), false, "unauthorized after deadline");
    }

    function test_setAuthorization_givenHistoricalDeadline_reverts(
        uint48 blockTimestamp_,
        uint48 deadline_
    ) public {
        uint48 blockTimestamp = uint48(bound(blockTimestamp_, 1, type(uint48).max));
        uint48 deadline = uint48(bound(deadline_, 0, uint256(blockTimestamp) - 1));
        vm.warp(blockTimestamp);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_ExpiredAuthorization.selector,
                deadline
            )
        );
        auth.setAuthorization(operator, deadline);
    }

    function test_setAuthorization_givenSelfAuthorization_reverts() public {
        vm.prank(owner);
        vm.expectRevert(IOperatorAuth.OperatorAuth_SelfAuthorization.selector);
        auth.setAuthorization(owner, uint48(block.timestamp + 1 days));
    }

    function test_setAuthorization_givenCallerIsNotOwner_authorizesOnlyCaller() public {
        uint48 deadline = uint48(block.timestamp + 1 days);

        vm.prank(caller);
        auth.setAuthorization(operator, deadline);

        assertEq(auth.authorizationDeadlines(caller, operator), deadline, "caller authorization");
        assertEq(auth.authorizationDeadlines(owner, operator), 0, "owner authorization");
    }

    function test_setAuthorization_givenExistingNonce() public {
        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));
        uint256 nonceBefore = auth.authorizationNonces(owner);

        _setAuthorizationAndExpectEvent(owner, otherOperator, uint48(block.timestamp + 2 days));

        assertEq(
            auth.authorizationNonces(owner),
            nonceBefore + 1,
            "nonce after direct authorization"
        );
    }

    function test_setAuthorization_givenPendingSignature_invalidatesSignature() public {
        uint48 directDeadline = uint48(block.timestamp + 1 days);
        uint48 signedDeadline = uint48(block.timestamp + 2 days);
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                signedDeadline,
                auth.authorizationNonces(owner),
                uint48(block.timestamp + 1 hours)
            );

        _setAuthorizationAndExpectEvent(owner, operator, directDeadline);

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
            "nonce after direct authorization"
        );
        assertEq(
            auth.authorizationDeadlines(owner, operator),
            directDeadline,
            "direct authorization deadline"
        );
    }
}
