// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigDepositManagerTest is BurnerLoansTest {
    function test_givenConfigDeployed_depositManager_returnsImmutableCustody() public view {
        assertEq(burnerLoansConfig.depositManager(), address(depositManager), "deposit manager");
    }
}
