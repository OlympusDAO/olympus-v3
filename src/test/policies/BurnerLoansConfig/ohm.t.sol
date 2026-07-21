// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigOhmTest is BurnerLoansTest {
    // ohm
    // given config deployed
    //  when ohm is called
    //   then it returns immutable token
    function test_givenConfigDeployed_ohm_returnsImmutableToken() public view {
        assertEq(burnerLoansConfig.ohm(), address(ohm), "OHM");
    }
}
