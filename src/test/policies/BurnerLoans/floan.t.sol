// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansFloanTest is BurnerLoansTest {
    function test_givenPolicyActivated_floan_returnsInstalledModule() public view {
        assertEq(burnerLoans.floan(), address(floan), "FLOAN");
    }
}
