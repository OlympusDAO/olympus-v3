// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {OperatorAuthTest} from "../OperatorAuth.t.sol";

contract OperatorAuthIsSenderAuthorizedTest is OperatorAuthTest {
    function test_isSenderAuthorized_givenSelf_returnsTrue() public view {
        assertEq(auth.isSenderAuthorized(owner, owner), true, "owner authorized");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "operator unauthorized");
    }
}
