// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockExecutionWindowTest is BurnerLoansConfigTimelockTest {
    // EXECUTION_WINDOW
    // given timelock deployed
    //  when EXECUTION_WINDOW is called
    //   then it returns three days
    function test_givenTimelockDeployed_EXECUTION_WINDOW_returnsThreeDays() public view {
        assertEq(configTimelock.EXECUTION_WINDOW(), 3 days, "execution window");
    }
}
