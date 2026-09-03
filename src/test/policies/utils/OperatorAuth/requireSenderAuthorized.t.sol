// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {OperatorAuthTest} from "../OperatorAuth.t.sol";

contract OperatorAuthRequireSenderAuthorizedTest is OperatorAuthTest {
    function test_requireSenderAuthorized_checksAuthorization() public {
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        auth.requireSenderAuthorized(operator, owner);

        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));

        auth.requireSenderAuthorized(operator, owner);
    }

    function test_requireSenderAuthorized_givenUnauthorizedCaller_reverts(address sender_) public {
        vm.assume(sender_ != owner);
        vm.assume(sender_ != operator);

        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));

        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        auth.requireSenderAuthorized(sender_, owner);
    }
}
