// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansSetConfiguratorTest is BurnerLoansTest {
    event ConfiguratorSet(address indexed configurator);

    // setConfigurator
    // given caller does not have the admin role
    //  when setConfigurator is called
    //   then it reverts
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoans.setConfigurator(makeAddr("newConfigurator"));
    }

    // setConfigurator
    // given the policy is disabled
    //  when setConfigurator is called by admin
    //   then it reverts
    function test_givenDisabled_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.setConfigurator(makeAddr("newConfigurator"));
    }

    // setConfigurator
    // given configurator address is zero
    //  when setConfigurator is called by admin
    //   then it reverts
    function test_givenZeroAddress_reverts() public {
        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoans.setConfigurator(address(0));
    }

    // setConfigurator
    // given configurator address is non-zero
    //  when setConfigurator is called by admin
    //   then it stores the configurator
    function test_givenAdminCaller_setsConfigurator() public {
        address newConfigurator = makeAddr("newConfigurator");

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit ConfiguratorSet(newConfigurator);
        burnerLoans.setConfigurator(newConfigurator);

        assertEq(burnerLoans.configurator(), newConfigurator, "configurator");
    }
}
