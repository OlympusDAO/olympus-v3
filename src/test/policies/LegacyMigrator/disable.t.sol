// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

contract LegacyMigratorDisableTest is LegacyMigratorTest {
    // ========== DISABLE TESTS ========== //
    // given contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public givenContractDisabled {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));

        // Call function
        vm.prank(emergencyUser);
        migrator.disable("");
    }

    // given contract is enabled
    //  given caller has emergency role
    //   [X] it disables the contract

    function test_givenEnabled_givenCallerHasEmergencyRole() public {
        // Call function
        vm.prank(emergencyUser);
        migrator.disable("");

        // Assert state
        assertEq(migrator.isEnabled(), false, "Contract should be disabled");
    }

    //  given caller has admin role
    //   [X] it disables the contract

    function test_givenEnabled_givenCallerHasAdminRole() public {
        // Call function
        vm.prank(adminUser);
        migrator.disable("");

        // Assert state
        assertEq(migrator.isEnabled(), false, "Contract should be disabled");
    }

    //  given caller does not have emergency or admin role
    //   [X] it reverts

    function test_givenEnabled_givenCallerDoesNotHaveEmergencyOrAdminRole_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != emergencyUser && caller_ != adminUser);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));

        // Call function
        vm.prank(caller_);
        migrator.disable("");
    }
}
