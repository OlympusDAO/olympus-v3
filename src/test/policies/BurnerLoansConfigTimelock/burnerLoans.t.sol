// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockBurnerLoansTest is BurnerLoansConfigTimelockTest {
    // burnerLoans
    // given timelock deployed
    //  when burnerLoans is called
    //   then it returns config policy
    function test_givenTimelockDeployed_burnerLoans_returnsConfigPolicy() public view {
        assertEq(address(configTimelock.burnerLoans()), address(burnerLoansConfig), "config");
    }
}
