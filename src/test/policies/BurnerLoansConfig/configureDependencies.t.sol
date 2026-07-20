// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigConfigureDependenciesTest is BurnerLoansTest {
    function test_givenConfigActivated_configureDependencies_setsRolesModule() public view {
        assertEq(address(burnerLoansConfig.ROLES()), address(roles), "ROLES");
    }
}
