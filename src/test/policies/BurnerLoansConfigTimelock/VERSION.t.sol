// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockVersionTest is BurnerLoansConfigTimelockTest {
    function test_givenTimelockDeployed_VERSION_returnsInitialVersion() public view {
        (uint8 major, uint8 minor) = configTimelock.VERSION();
        assertEq(major, 1, "major");
        assertEq(minor, 0, "minor");
    }
}
