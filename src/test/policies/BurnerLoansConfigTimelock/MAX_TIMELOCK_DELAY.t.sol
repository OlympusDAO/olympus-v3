// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockMaxDelayTest is BurnerLoansConfigTimelockTest {
    // MAX_TIMELOCK_DELAY
    // given timelock deployed
    //  when MAX_TIMELOCK_DELAY is called
    //   then it returns thirty days
    function test_givenTimelockDeployed_MAX_TIMELOCK_DELAY_returnsThirtyDays() public view {
        assertEq(configTimelock.MAX_TIMELOCK_DELAY(), 30 days, "maximum delay");
    }
}
