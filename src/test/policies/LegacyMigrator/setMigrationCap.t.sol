// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorSetMigrationCapTest is LegacyMigratorTest {
    event MigrationCapUpdated(uint256 indexed newCap, uint256 indexed oldCap);

    // ========== SET MIGRATION CAP TESTS ========== //
    // Given non-admin
    //  [X] it reverts when setting migration cap

    function test_givenNonAdmin_setsMigrationCap_reverts() public {
        uint256 newCap = 20000e9;

        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("admin")
        );
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.setMigrationCap(newCap);
    }

    // Given admin
    //  [X] it can set higher cap
    //  [X] it can set lower cap

    function test_givenAdmin_setsHigherCap_increasesApproval() public {
        uint256 newCap = INITIAL_CAP + 1000e9;

        vm.expectEmit(false, false, false, true);
        emit MigrationCapUpdated(newCap, INITIAL_CAP);

        vm.prank(adminUser);
        migrator.setMigrationCap(newCap);

        assertEq(migrator.migrationCap(), newCap, "Migration cap should be updated");
    }

    function test_givenAdmin_setsLowerCap_decreasesApproval() public {
        uint256 newCap = INITIAL_CAP - 1000e9;

        vm.expectEmit(false, false, false, true);
        emit MigrationCapUpdated(newCap, INITIAL_CAP);

        vm.prank(adminUser);
        migrator.setMigrationCap(newCap);

        assertEq(migrator.migrationCap(), newCap, "Migration cap should be updated");
    }

    // Given legacy migration admin
    //  [X] it reverts when setting migration cap

    function test_givenLegacyMigrationAdmin_setsMigrationCap_reverts() public {
        uint256 newCap = 20000e9;

        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("admin")
        );
        vm.expectRevert(err);

        vm.prank(legacyMigrationAdmin);
        migrator.setMigrationCap(newCap);
    }

    // ========== DISABLED STATE TESTS ========== //
    // Given contract is disabled
    //  [X] admin can still set migration cap

    function test_givenContractDisabled_setsMigrationCap_succeeds() public givenContractDisabled {
        uint256 newCap = INITIAL_CAP + 1000e9;

        vm.prank(adminUser);
        migrator.setMigrationCap(newCap);

        assertEq(migrator.migrationCap(), newCap, "Migration cap should be updated when disabled");
    }

    // ========== FUZZ TESTS ========== //
    // Given any uint256 cap value
    //  [X] admin can set it as migration cap

    function test_fuzz_setMigrationCap_acceptsAnyUint(uint256 newCap) public {
        vm.prank(adminUser);
        migrator.setMigrationCap(newCap);

        assertEq(migrator.migrationCap(), newCap, "Migration cap should match input");
    }
}
