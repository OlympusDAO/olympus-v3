// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigDepositManagerTest is BurnerLoansTest {
    // depositManager
    // given config deployed
    //  when depositManager is called
    //   then it returns immutable custody
    function test_givenConfigDeployed_depositManager_returnsImmutableCustody() public view {
        assertEq(burnerLoansConfig.depositManager(), address(depositManager), "deposit manager");
    }
}
