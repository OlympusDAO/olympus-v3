// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansOhmTest is BurnerLoansTest {
    // ohm
    // given policy deployed
    //  when ohm is called
    //   then it returns immutable token
    function test_givenPolicyDeployed_ohm_returnsImmutableToken() public view {
        assertEq(address(burnerLoans.context().ohm), address(ohm), "OHM");
    }
}
