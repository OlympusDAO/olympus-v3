// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorEnableTest is LegacyMigratorTest {
    // ========== ENABLE TESTS ========== //

    // given the contract is enabled
    //  [X] it reverts

    function test_givenContractEnabled_reverts() public {
        // Assert prior state
        assertEq(migrator.isEnabled(), true, "Contract should be enabled");

        // Expect revert
        bytes memory err = abi.encodeWithSignature("NotDisabled()");
        vm.expectRevert(err);

        // Call function
        vm.prank(adminUser);
        migrator.enable("");
    }

    // given the contract is disabled
    //  given the caller does not have the admin role
    //   [X] it reverts

    function test_givenContractDisabled_givenCallerDoesNotHaveAdminRole_reverts(
        address caller_
    ) public givenContractDisabled {
        vm.assume(caller_ != adminUser);

        // Assert prior state
        assertEq(migrator.isEnabled(), false, "Contract should be disabled");

        // Expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("admin")
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(caller_);
        migrator.enable("");
    }

    //  given the caller has the admin role
    //   [X] it enables the contract

    function test_givenContractDisabled_givenCallerHasAdminRole() public givenContractDisabled {
        // Assert prior state
        assertEq(migrator.isEnabled(), false, "Contract should be disabled");

        // Call function
        vm.prank(adminUser);
        migrator.enable("");

        // Assert state
        assertEq(migrator.isEnabled(), true, "Contract should be enabled");
    }
}
