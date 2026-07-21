// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockConfigureDependenciesTest is BurnerLoansConfigTimelockTest {
    // configureDependencies
    // given policy activated
    //  when configureDependencies is called
    //   then it sets roles module
    function test_givenPolicyActivated_configureDependencies_setsRolesModule() public view {
        assertEq(address(configTimelock.ROLES()), address(roles), "ROLES");
    }
}
