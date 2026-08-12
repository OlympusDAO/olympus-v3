// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC20} from "src/interfaces/IERC20.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigConstructorTest is BurnerLoansTest {
    // constructor
    // given OHM is zero
    //  when BurnerLoansConfig is deployed
    //   then it reverts
    function test_givenOhmIsZero_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        new BurnerLoansConfig(kernel, IERC20(address(0)));
    }

    // constructor
    // given OHM is valid
    //  when BurnerLoansConfig is deployed
    //   then it leaves facility linkage for the active-policy setter
    function test_givenValidOhm_leavesFacilityUnlinked() public {
        BurnerLoansConfig config = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        assertEq(config.facility(), address(0), "facility");
    }
}
