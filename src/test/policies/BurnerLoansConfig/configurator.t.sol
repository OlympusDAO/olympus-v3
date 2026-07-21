// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigConfiguratorTest is BurnerLoansTest {
    // configurator
    // given configurator set
    //  when configurator is called
    //   then it returns configured address
    function test_givenConfiguratorSet_configurator_returnsConfiguredAddress() public {
        vm.prank(admin);
        burnerLoansConfig.setConfigurator(address(configTimelock));

        assertEq(burnerLoansConfig.configurator(), address(configTimelock), "configurator");
    }
}
