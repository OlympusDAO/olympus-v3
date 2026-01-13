// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorSetMerkleRootTest is LegacyMigratorTest {
    event MerkleRootUpdated(bytes32 indexed newRoot, address indexed updater);

    // ========== SET MERKLE ROOT TESTS ========== //

    // Given non-legacy-migration-admin sets merkle root
    //  [X] it reverts

    function test_givenNonLegacyMigrationAdmin_setsMerkleRoot_reverts() public {
        bytes32 newRoot = bytes32(uint256(1));

        // casting to 'bytes32' is safe because "legacy_migration_admin" is a fixed 23-byte string that fits in bytes32
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("legacy_migration_admin")
        );
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.setMerkleRoot(newRoot);
    }

    // Given legacy migration admin sets merkle root
    //  [X] it updates the merkle root
    //  [X] it resets hasMigrated for all users

    function test_givenLegacyMigrationAdmin_setsMerkleRoot_succeeds() public {
        // First, do a migration to mark alice as migrated
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);

        // Check user has migrated
        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");

        // Update merkle root
        bytes32 newRoot = bytes32(uint256(2));

        vm.expectEmit(false, false, false, true);
        emit MerkleRootUpdated(newRoot, legacyMigrationAdmin);

        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(newRoot);

        // Check that merkle root is updated
        assertEq(migrator.merkleRoot(), newRoot, "Merkle root should be updated");

        // Check that hasMigrated is reset
        assertFalse(migrator.hasMigrated(alice), "Alice should be reset after root change");
    }
}
