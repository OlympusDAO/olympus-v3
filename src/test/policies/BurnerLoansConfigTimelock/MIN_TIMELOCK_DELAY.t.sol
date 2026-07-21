// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockMinDelayTest is BurnerLoansConfigTimelockTest {
    // MIN_TIMELOCK_DELAY
    // given timelock deployed
    //  when MIN_TIMELOCK_DELAY is called
    //   then it returns one day
    function test_givenTimelockDeployed_MIN_TIMELOCK_DELAY_returnsOneDay() public view {
        assertEq(configTimelock.MIN_TIMELOCK_DELAY(), 1 days, "minimum delay");
    }
}
