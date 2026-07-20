// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigVersionTest is BurnerLoansTest {
    function test_givenConfigDeployed_VERSION_returnsInitialVersion() public view {
        (uint8 major, uint8 minor) = burnerLoansConfig.VERSION();
        assertEq(major, 1, "major");
        assertEq(minor, 0, "minor");
    }
}
