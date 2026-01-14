// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorMigrateTest is LegacyMigratorTest {
    event Migrated(address indexed user, uint256 ohmV1Amount, uint256 ohmV2Amount);
    event MerkleRootUpdated(bytes32 indexed newRoot, address indexed updater);

    // ========== MIGRATE TESTS ========== //
    // Given the contract is disabled
    //  [X] it reverts when migrating

    function test_givenContractIsDisabled_reverts() public givenContractDisabled {
        bytes memory err = abi.encodeWithSignature("NotEnabled()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);
    }

    // ========== INVALID PROOF TESTS ========== //
    // Given invalid merkle proof
    //  [X] it reverts when migrating

    function test_givenInvalidMerkleProof_reverts() public {
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

    function test_givenValidProof_fullAmount_succeeds() public givenAliceApproved {
        vm.expectEmit(true, true, false, true);
        emit Migrated(alice, ALICE_ALLOWANCE, ALICE_ALLOWANCE);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);

        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");
        assertEq(migrator.totalMigrated(), ALICE_ALLOWANCE, "Total migrated should equal ALICE_ALLOWANCE");
        assertEq(ohmV2.balanceOf(alice), ALICE_ALLOWANCE, "Alice should receive ALICE_ALLOWANCE OHM v2");
    }

    // ========== ALL-OR-NOTHING MIGRATION TESTS ========== //
    // Given user migrates full amount
    //  [X] it succeeds
    //  [X] second migration attempt reverts

    function test_givenUserMigratesFullAmount_secondAttemptReverts() public givenAliceMigrated {
        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");
        assertEq(migrator.totalMigrated(), ALICE_ALLOWANCE, "Total migrated should equal ALICE_ALLOWANCE");

        bytes memory err = abi.encodeWithSignature("AmountExceedsAllowance()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);
    }

    // ========== PARTIAL AMOUNT TESTS ========== //
    // Given user attempts partial migration
    //  [X] it reverts (all-or-nothing)

    function test_givenPartialAmount_reverts() public givenAliceApproved {
        uint256 partialAmount = 500e9;

        bytes memory err = abi.encodeWithSignature("InvalidProof()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(partialAmount, aliceProof);
    }

    // ========== CAP TESTS ========== //
    // Given migration cap reached
    //  [X] it reverts when migrating

    function test_givenCapReached_reverts() public givenCapReached givenBobApproved {
        bytes memory err = abi.encodeWithSignature("CapExceeded()");
        vm.expectRevert(err);

        vm.prank(bob);
        migrator.migrate(BOB_ALLOWANCE, bobProof);
    }

    // ========== APPROVAL TESTS ========== //
    // Given user has not approved OHM v1
    //  [X] it reverts when migrating

    function test_givenNoApproval_reverts() public {
        // MockOhm uses a string error for insufficient allowance
        vm.expectRevert("ERC20: burn amount exceeds allowance");

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);
    }

    // ========== USER MIGRATION ON BEHALF TESTS ========== //
    // Given alice attempts to migrate for bob
    //  [X] it uses alice's address for verification (not bob's)

    function test_givenUserMigratesForAnother_usesOwnAddress() public givenAliceApproved {
        // Alice approves and attempts to migrate with her proof
        // The migration verifies against msg.sender (alice), not a recipient
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);

        // Alice should be marked as migrated (not bob)
        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");
        assertFalse(migrator.hasMigrated(bob), "Bob should not be marked as migrated");

        // Alice receives the OHM v2 (not bob)
        assertEq(ohmV2.balanceOf(alice), ALICE_ALLOWANCE, "Alice should receive OHM v2");
        assertEq(ohmV2.balanceOf(bob), 0, "Bob should not receive OHM v2");
    }

    // ========== MERKLE ROOT UPDATE TESTS ========== //
    // Given user migrated
    //  When merkle root is updated
    //    [X] it resets hasMigrated
    //    [X] it prevents re-migration with old proof

    function test_givenMigrated_whenRootUpdated_preventsRemigration() public givenAliceMigrated {
        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");
        assertEq(migrator.totalMigrated(), ALICE_ALLOWANCE, "Total migrated should equal ALICE_ALLOWANCE");

        bytes32 newRoot = bytes32(uint256(1));
        vm.expectEmit(false, false, false, true);
        emit MerkleRootUpdated(newRoot, legacyMigrationAdmin);

        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(newRoot);

        assertEq(migrator.merkleRoot(), newRoot, "Merkle root should be updated to newRoot");
        assertFalse(migrator.hasMigrated(alice), "Alice should be reset after root change");

        bytes memory err = abi.encodeWithSignature("InvalidProof()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);
    }

    // ========== FUZZ TESTS ========== //
    // Given any amount that is not the user's allowance
    //  [X] it reverts with InvalidProof (all-or-nothing)

    function test_fuzz_migrate_unacceptableAmount_reverts(uint256 amount) public givenAliceApproved {
        // Skip zero (has its own error) and the exact allowance amount (valid case)
        vm.assume(amount != 0);
        vm.assume(amount != ALICE_ALLOWANCE);

        bytes memory err = abi.encodeWithSignature("InvalidProof()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(amount, aliceProof);
    }

    // Given any amount including zero
    //  [X] zero amount reverts with ZeroAmount

    function test_fuzz_migrate_zeroAmount_reverts() public {
        bytes memory err = abi.encodeWithSignature("ZeroAmount()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(0, aliceProof);
    }
}
