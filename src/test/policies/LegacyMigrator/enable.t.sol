// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorEnableTest is LegacyMigratorTest {
    // ========== ENABLE TESTS ========== //
    // Given contract disabled + admin role
    //  [X] it enables the contract

    function test_givenContractDisabled_adminEnables_succeeds() public givenContractDisabled {
        assertEq(migrator.isEnabled(), false, "Contract should be disabled");

        vm.prank(adminUser);
        migrator.enable("");

        assertEq(migrator.isEnabled(), true, "Contract should be enabled");
    }

    // Given contract enabled + admin role
    //  [X] it reverts (already enabled)

    function test_givenContractEnabled_adminTriesToEnable_reverts() public {
        assertEq(migrator.isEnabled(), true, "Contract should be enabled");

        bytes memory err = abi.encodeWithSignature("NotDisabled()");
        vm.expectRevert(err);

        vm.prank(adminUser);
        migrator.enable("");
    }

    // Given contract disabled + non-admin
    //  [X] it reverts (not authorised)

    function test_givenContractDisabled_nonAdminTriesToEnable_reverts() public givenContractDisabled {
        assertEq(migrator.isEnabled(), false, "Contract should be disabled");

        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("admin")
        );
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.enable("");
    }

    // Given contract disabled + emergency role (not admin)
    //  [X] it reverts (emergency is not admin)

    function test_givenContractDisabled_emergencyTriesToEnable_reverts() public givenContractDisabled {
        assertEq(migrator.isEnabled(), false, "Contract should be disabled");

        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("admin")
        );
        vm.expectRevert(err);

        vm.prank(emergencyUser);
        migrator.enable("");
    }

    // Given contract disabled + legacy migration admin (not admin)
    //  [X] it reverts (legacy migration admin is not admin)

    function test_givenContractDisabled_legacyMigrationAdminTriesToEnable_reverts()
        public
        givenContractDisabled
    {
        assertEq(migrator.isEnabled(), false, "Contract should be disabled");

        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("admin")
        );
        vm.expectRevert(err);

        vm.prank(legacyMigrationAdmin);
        migrator.enable("");
    }
}
