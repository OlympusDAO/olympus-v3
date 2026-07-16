// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOlympusBackingOracle} from "src/test/mocks/MockOlympusBackingOracle.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansSetBackingOracleTest is BurnerLoansTest {
    event BackingOracleSet(address indexed backingOracle);

    // setBackingOracle
    // given caller does not have the admin role
    //  when setBackingOracle is called
    //   then it reverts
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoans.setBackingOracle(makeAddr("newBackingOracle"));
    }

    // setBackingOracle
    // given the policy is disabled
    //  when setBackingOracle is called by admin
    //   then it reverts
    function test_givenDisabled_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.setBackingOracle(makeAddr("newBackingOracle"));
    }

    // setBackingOracle
    // given backing oracle address is zero
    //  when setBackingOracle is called by admin
    //   then it reverts
    function test_givenZeroAddress_reverts() public {
        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoans.setBackingOracle(address(0));
    }

    // setBackingOracle
    // given backing oracle address is nonzero
    //  when setBackingOracle is called by admin
    //   then it stores the oracle and emits the configuration event
    function test_givenAdminCaller_setsBackingOracle() public {
        MockOlympusBackingOracle newBackingOracle = new MockOlympusBackingOracle(12e18);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit BackingOracleSet(address(newBackingOracle));
        burnerLoans.setBackingOracle(address(newBackingOracle));

        assertEq(burnerLoans.backingOracle(), address(newBackingOracle), "backing oracle");
    }
}
