// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorSetMigrationCapTest is LegacyMigratorTest {
    event MigrationCapUpdated(uint256 indexed newCap, uint256 indexed oldCap);

    // ========== SET MIGRATION CAP TESTS ========== //

    // Given non-admin sets migration cap
    //  [X] it reverts

    function test_givenNonAdmin_setsMigrationCap_reverts() public {
        uint256 newCap = 20000e9;

        // casting to 'bytes32' is safe because "admin" is a fixed 5-byte string that fits in bytes32
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("admin")
        );
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.setMigrationCap(newCap);
    }

    // Given admin sets higher migration cap
    //  [X] it calls MINTR.increaseMintApproval()
    //  [X] it emits MigrationCapUpdated event

    function test_givenAdmin_setsHigherCap_increasesApproval() public {
        uint256 newCap = INITIAL_CAP + 1000e9;

        vm.expectEmit(false, false, false, true);
        emit MigrationCapUpdated(newCap, INITIAL_CAP);

        vm.prank(adminUser);
        migrator.setMigrationCap(newCap);

        // Check cap updated
        assertEq(migrator.migrationCap(), newCap, "Migration cap should be updated");
    }

    // Given admin sets lower migration cap
    //  [X] it calls MINTR.decreaseMintApproval()
    //  [X] it emits MigrationCapUpdated event

    function test_givenAdmin_setsLowerCap_decreasesApproval() public {
        uint256 newCap = INITIAL_CAP - 1000e9;

        vm.expectEmit(false, false, false, true);
        emit MigrationCapUpdated(newCap, INITIAL_CAP);

        vm.prank(adminUser);
        migrator.setMigrationCap(newCap);

        // Check cap updated
        assertEq(migrator.migrationCap(), newCap, "Migration cap should be updated");
    }

    // Given legacy migration admin tries to set migration cap
    //  [X] it reverts (only admin can set cap)

    function test_givenLegacyMigrationAdmin_setsMigrationCap_reverts() public {
        uint256 newCap = 20000e9;

        // casting to 'bytes32' is safe because "admin" is a fixed 5-byte string that fits in bytes32
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("admin")
        );
        vm.expectRevert(err);

        vm.prank(legacyMigrationAdmin);
        migrator.setMigrationCap(newCap);
    }
}
