// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {OperatorAuthTest} from "../OperatorAuth.t.sol";

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.
// forge-lint: disable-start(unsafe-typecast)

contract OperatorAuthRequireSenderAuthorizedTest is OperatorAuthTest {
    uint48 internal constant _AUTHORIZATION_VALIDITY = 1 days;

    function test_requireSenderAuthorized_checksAuthorization() public {
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        auth.requireSenderAuthorized(operator, owner);

        _setAuthorizationAndExpectEvent(
            owner,
            operator,
            uint48(block.timestamp + _AUTHORIZATION_VALIDITY)
        );

        auth.requireSenderAuthorized(operator, owner);
    }

    function test_requireSenderAuthorized_givenUnauthorizedCaller_reverts(address sender_) public {
        vm.assume(sender_ != owner);
        vm.assume(sender_ != operator);

        _setAuthorizationAndExpectEvent(
            owner,
            operator,
            uint48(block.timestamp + _AUTHORIZATION_VALIDITY)
        );

        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        auth.requireSenderAuthorized(sender_, owner);
    }
}

// forge-lint: disable-end(unsafe-typecast)
