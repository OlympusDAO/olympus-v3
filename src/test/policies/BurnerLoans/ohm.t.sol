// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansOhmTest is BurnerLoansTest {
    function test_givenPolicyDeployed_ohm_returnsImmutableToken() public view {
        assertEq(burnerLoans.ohm(), address(ohm), "OHM");
    }
}
