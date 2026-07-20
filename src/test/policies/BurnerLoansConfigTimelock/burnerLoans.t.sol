// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockBurnerLoansTest is BurnerLoansConfigTimelockTest {
    function test_givenTimelockDeployed_burnerLoans_returnsConfigPolicy() public view {
        assertEq(address(configTimelock.burnerLoans()), address(burnerLoansConfig), "config");
    }
}
