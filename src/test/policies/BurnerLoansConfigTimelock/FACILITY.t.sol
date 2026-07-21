// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockFacilityTest is BurnerLoansConfigTimelockTest {
    // FACILITY
    // given timelock deployed
    //  when FACILITY is called
    //   then it returns lifecycle policy
    function test_givenTimelockDeployed_FACILITY_returnsLifecyclePolicy() public view {
        assertEq(configTimelock.FACILITY(), address(burnerLoans), "facility");
    }
}
