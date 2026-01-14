// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorSetMerkleRootTest is LegacyMigratorTest {
    event MerkleRootUpdated(bytes32 indexed newRoot, address indexed updater);

    // ========== SET MERKLE ROOT TESTS ========== //
    // Given non-legacy migration admin
    //  [X] it reverts when setting merkle root

    function test_givenNonLegacyMigrationAdmin_setsMerkleRoot_reverts() public {
        bytes32 newRoot = bytes32(uint256(1));

        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("legacy_migration_admin")
        );
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.setMerkleRoot(newRoot);
    }

    // Given legacy migration admin
    //  [X] it can set merkle root
    //  [X] it resets hasMigrated for all users

    function test_givenLegacyMigrationAdmin_setsMerkleRoot_succeeds() public givenAliceMigrated {
        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");

        bytes32 newRoot = bytes32(uint256(2));

        vm.expectEmit(false, false, false, true);
        emit MerkleRootUpdated(newRoot, legacyMigrationAdmin);

        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(newRoot);

        assertEq(migrator.merkleRoot(), newRoot, "Merkle root should be updated");
        assertFalse(migrator.hasMigrated(alice), "Alice should be reset after root change");
    }

    // ========== DISABLED STATE TESTS ========== //
    // Given contract is disabled
    //  [X] legacy migration admin can still set merkle root

    function test_givenContractDisabled_setsMerkleRoot_succeeds() public givenContractDisabled {
        bytes32 newRoot = bytes32(uint256(3));

        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(newRoot);

        assertEq(migrator.merkleRoot(), newRoot, "Merkle root should be updated when disabled");
    }

    // ========== FUZZ TESTS ========== //
    // Given any bytes32 value
    //  [X] legacy migration admin can set it as merkle root

    function test_fuzz_setMerkleRoot_acceptsAnyBytes32(bytes32 newRoot) public {
        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(newRoot);

        assertEq(migrator.merkleRoot(), newRoot, "Merkle root should match input");
    }
}
