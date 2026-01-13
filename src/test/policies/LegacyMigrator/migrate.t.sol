// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorMigrateTest is LegacyMigratorTest {
    event Migrated(address indexed user, uint256 ohmV1Amount, uint256 ohmV2Amount);
    event MerkleRootUpdated(bytes32 indexed newRoot, address indexed updater);

    // ========== MIGRATE TESTS ========== //

    // Given the contract is disabled
    //  [X] it reverts when migrating

    function test_givenContractIsDisabled_reverts() public {
        // Disable the contract
        vm.prank(emergencyUser);
        migrator.disable("");

        // Attempt migration should revert
        bytes memory err = abi.encodeWithSignature("NotEnabled()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);
    }

    // ========== INVALID PROOF TESTS ========== //
    // Given invalid merkle proof
    //  [X] it reverts when migrating

    function test_givenInvalidMerkleProof_reverts() public {
        // Create invalid proof (empty array)
        bytes32[] memory invalidProof = new bytes32[](0);

        bytes memory err = abi.encodeWithSignature("InvalidProof()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, invalidProof);
    }

    // ========== VALID MIGRATION TESTS ========== //
    // Given valid proof, full amount
    //  [X] it migrates successfully
    //  [X] it emits Migrated event
    //  [X] it updates hasMigrated
    //  [X] it updates totalMigrated

    function test_givenValidProof_fullAmount_succeeds() public {
        // Approve OHM v1 to migrator
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit Migrated(alice, ALICE_ALLOWANCE, ALICE_ALLOWANCE);

        // Migrate
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);

        // Check user has migrated
        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");

        // Check total migrated updated
        assertEq(
            migrator.totalMigrated(),
            ALICE_ALLOWANCE,
            "Total migrated should equal ALICE_ALLOWANCE"
        );

        // Check OHM v2 received
        assertEq(
            ohmV2.balanceOf(alice),
            ALICE_ALLOWANCE,
            "Alice should receive ALICE_ALLOWANCE OHM v2"
        );
    }

    // ========== ALL-OR-NOTHING MIGRATION TESTS ========== //
    // Given user migrates full amount
    //  [X] it succeeds
    //  [X] second migration attempt reverts

    function test_givenUserMigratesFullAmount_secondAttemptReverts() public {
        // Approve OHM v1 to migrator
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);

        // First migration with full amount
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);

        // Check user has migrated
        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");

        // Check total migrated
        assertEq(
            migrator.totalMigrated(),
            ALICE_ALLOWANCE,
            "Total migrated should equal ALICE_ALLOWANCE"
        );

        // Second migration should revert (already migrated)
        bytes memory err = abi.encodeWithSignature("AmountExceedsAllowance()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);
    }

    // ========== PARTIAL AMOUNT TESTS ========== //
    // Given user attempts partial migration
    //  [X] it reverts (all-or-nothing)

    function test_givenPartialAmount_reverts() public {
        uint256 partialAmount = 500e9; // 500 OHM (less than full allowance)

        // Approve OHM v1 to migrator
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);

        // Partial migration should revert (proof doesn't match partial amount)
        bytes memory err = abi.encodeWithSignature("InvalidProof()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(partialAmount, aliceProof);
    }

    // ========== CAP TESTS ========== //
    // Given migration cap reached
    //  [X] it reverts when migrating

    function test_givenCapReached_reverts() public {
        // Set cap to exactly alice's allowance
        uint256 newCap = ALICE_ALLOWANCE;
        vm.prank(adminUser);
        migrator.setMigrationCap(newCap);

        // Approve OHM v1 to migrator
        vm.prank(bob);
        ohmV1.approve(address(migrator), BOB_ALLOWANCE);

        // Bob should not be able to migrate (cap would be exceeded)
        bytes memory err = abi.encodeWithSignature("CapExceeded()");
        vm.expectRevert(err);

        vm.prank(bob);
        migrator.migrate(BOB_ALLOWANCE, bobProof);
    }

    // ========== MERKLE ROOT UPDATE TESTS ========== //
    // Given merkle root update
    //  [X] it updates the merkle root
    //  [X] it resets hasMigrated to false
    //  [X] old proof is invalid (cannot migrate with old proof)

    function test_givenMerkleRootUpdate_doesNotAllowRemigration() public {
        // First, do a full migration
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);

        // Check user has migrated
        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");
        assertEq(
            migrator.totalMigrated(),
            ALICE_ALLOWANCE,
            "Total migrated should equal ALICE_ALLOWANCE"
        );

        // Update merkle root
        bytes32 newRoot = bytes32(uint256(1));
        vm.prank(legacyMigrationAdmin);
        vm.expectEmit(false, false, false, true);
        emit MerkleRootUpdated(newRoot, legacyMigrationAdmin);

        migrator.setMerkleRoot(newRoot);

        // Check that merkle root is updated
        assertEq(migrator.merkleRoot(), newRoot, "Merkle root should be updated to newRoot");

        // Check that hasMigrated is reset
        assertFalse(migrator.hasMigrated(alice), "Alice should be reset after root change");

        // User should not be able to migrate again with the old proof (now invalid)
        bytes memory err = abi.encodeWithSignature("InvalidProof()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);
    }
}
