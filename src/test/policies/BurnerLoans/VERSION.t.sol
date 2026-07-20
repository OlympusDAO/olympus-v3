// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansVersionTest is BurnerLoansTest {
    function test_givenPolicyDeployed_VERSION_returnsInitialVersion() public view {
        (uint8 major, uint8 minor) = burnerLoans.VERSION();
        assertEq(major, 1, "major");
        assertEq(minor, 0, "minor");
    }
}
