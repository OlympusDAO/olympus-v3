// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Permissions} from "src/Kernel.sol";
import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockRequestPermissionsTest is BurnerLoansConfigTimelockTest {
    function test_givenTimelockPolicy_requestPermissions_returnsEmptyArray() public view {
        Permissions[] memory permissions = configTimelock.requestPermissions();
        assertEq(permissions.length, 0, "permission count");
    }
}
