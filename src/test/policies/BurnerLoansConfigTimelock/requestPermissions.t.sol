// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Permissions} from "src/Kernel.sol";
import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockRequestPermissionsTest is BurnerLoansConfigTimelockTest {
    // requestPermissions
    // given timelock policy
    //  when requestPermissions is called
    //   then it returns empty array
    function test_givenTimelockPolicy_requestPermissions_returnsEmptyArray() public view {
        Permissions[] memory permissions = configTimelock.requestPermissions();
        assertEq(permissions.length, 0, "permission count");
    }
}
