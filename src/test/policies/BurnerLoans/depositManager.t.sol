// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansDepositManagerTest is BurnerLoansTest {
    function test_givenPolicyDeployed_depositManager_returnsImmutablePolicy() public view {
        assertEq(burnerLoans.depositManager(), address(depositManager), "deposit manager");
    }
}
