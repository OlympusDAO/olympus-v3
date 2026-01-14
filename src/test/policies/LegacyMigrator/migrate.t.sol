// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ILegacyMigrator} from "src/interfaces/ILegacyMigrator.sol";

contract LegacyMigratorMigrateTest is LegacyMigratorTest {
    event Migrated(address indexed user, uint256 ohmV1Amount, uint256 ohmV2Amount);
    event MerkleRootUpdated(bytes32 indexed newRoot, address indexed updater);

    // ========== MIGRATE TESTS ========== //

    // given contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public givenContractDisabled {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IEnabler.NotEnabled.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof, ALICE_ALLOWANCE);
    }

    // when the amount is zero
    //  [X] it reverts

    function test_whenAmountIsZero_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(ILegacyMigrator.ZeroAmount.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(alice);
        migrator.migrate(0, aliceProof, ALICE_ALLOWANCE);
    }

    // given invalid merkle proof
    //  [X] it reverts

    function test_givenInvalidMerkleProof_reverts() public {
        bytes32[] memory invalidProof = new bytes32[](0);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(ILegacyMigrator.InvalidProof.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, invalidProof, ALICE_ALLOWANCE);
    }

    // given user has not approved OHM v1
    //  [X] it reverts

    function test_givenNoApproval_reverts() public {
        // Expect revert
        // MockOhm uses a string error for insufficient allowance
        vm.expectRevert("ERC20: burn amount exceeds allowance");

        // Call function
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof, ALICE_ALLOWANCE);
    }

    // given the user does not have the balance of OHM v1
    //  [X] it reverts

    function test_givenInsufficientBalance_reverts() public givenAliceApproved {
        // Transfer the balance of OHM v1 to bob (so that alice has insufficient balance)
        vm.prank(alice);
        ohmV1.transfer(bob, ALICE_ALLOWANCE);

        // Expect revert
        // MockOhm uses a string error for insufficient balance
        vm.expectRevert("ERC20: burn amount exceeds balance");

        // Call function
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof, ALICE_ALLOWANCE);
    }

    // given amount exceeds allocation
    //  [X] it reverts

    // TODO amountExceedsAllowance should mention the allowance

    function test_givenAmountExceedsAllocation_reverts() public givenAliceApproved {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(ILegacyMigrator.AmountExceedsAllowance.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE + 1, aliceProof, ALICE_ALLOWANCE);
    }

    // given valid proof and approval
    //  given partial migration
    //   when the user attempts to migrate more than their allocation
    //    [X] it reverts

    function test_givenPartialMigration_exceedsAllowance_reverts(
        uint256 amount_
    ) public givenAlicePartiallyMigrated(500e9) {
        amount_ = bound(amount_, ALICE_ALLOWANCE - 500e9 + 1, ALICE_ALLOWANCE);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(ILegacyMigrator.AmountExceedsAllowance.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(alice);
        migrator.migrate(amount_, aliceProof, ALICE_ALLOWANCE);
    }

    //   when the user attempts to do multiple partial migrations
    //    [X] it succeeds
    //    [X] it updates migratedAmounts
    //    [X] it updates totalMigrated

    function test_givenMultiplePartialMigrations_succeeds() public givenAliceApproved {
        // Do multiple small migrations instead of one large one
        uint256 firstAmount = 200e9;
        uint256 secondAmount = 300e9;
        uint256 thirdAmount = 500e9;
        uint256 total = firstAmount + secondAmount + thirdAmount; // = 1000e9 = ALICE_ALLOWANCE

        // First migration
        vm.prank(alice);
        migrator.migrate(firstAmount, aliceProof, ALICE_ALLOWANCE);
        assertEq(
            migrator.migratedAmounts(alice),
            firstAmount,
            "Alice should have migrated first amount"
        );
        assertEq(ohmV2.balanceOf(alice), firstAmount, "Alice should receive first OHM v2");

        // Second migration
        vm.prank(alice);
        migrator.migrate(secondAmount, aliceProof, ALICE_ALLOWANCE);
        assertEq(
            migrator.migratedAmounts(alice),
            firstAmount + secondAmount,
            "Alice should have migrated second amount"
        );
        assertEq(
            ohmV2.balanceOf(alice),
            firstAmount + secondAmount,
            "Alice should receive second OHM v2"
        );

        // Third migration
        vm.prank(alice);
        migrator.migrate(thirdAmount, aliceProof, ALICE_ALLOWANCE);
        assertEq(migrator.migratedAmounts(alice), total, "Alice should have migrated total amount");
        assertEq(migrator.totalMigrated(), total, "Total migrated should equal total");
        assertEq(ohmV2.balanceOf(alice), total, "Alice should receive total OHM v2");
    }

    //   [X] it succeeds
    //   [X] it updates migratedAmounts
    //   [X] it updates totalMigrated
    //   [X] user can migrate remaining amount later

    function test_givenPartialMigration_secondMigration(
        uint256 amount_
    ) public givenAlicePartiallyMigrated(500e9) {
        amount_ = bound(amount_, 1, ALICE_ALLOWANCE - 500e9);

        // Call function
        vm.prank(alice);
        migrator.migrate(amount_, aliceProof, ALICE_ALLOWANCE);

        // Assert state
        assertEq(
            migrator.migratedAmounts(alice),
            500e9 + amount_,
            "Alice should have migrated partial amount"
        );
        assertEq(
            migrator.totalMigrated(),
            500e9 + amount_,
            "Total migrated should equal partial amount"
        );
        assertEq(ohmV2.balanceOf(alice), 500e9 + amount_, "Alice should receive partial OHM v2");
    }

    //  when the user attempts to migrate their entire allocation
    //   [X] it succeeds
    //   [X] it updates migratedAmounts
    //   [X] it updates totalMigrated
    //   [X] it emits Migrated event

    function test_fullAmount_succeeds() public givenAliceApproved {
        // Expect event
        vm.expectEmit(true, true, false, true);
        emit Migrated(alice, ALICE_ALLOWANCE, ALICE_ALLOWANCE);

        // Call function
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof, ALICE_ALLOWANCE);

        // Assert state
        assertEq(
            migrator.migratedAmounts(alice),
            ALICE_ALLOWANCE,
            "Alice should have migrated full amount"
        );
        assertEq(
            migrator.totalMigrated(),
            ALICE_ALLOWANCE,
            "Total migrated should equal ALICE_ALLOWANCE"
        );
        assertEq(
            ohmV2.balanceOf(alice),
            ALICE_ALLOWANCE,
            "Alice should receive ALICE_ALLOWANCE OHM v2"
        );
    }

    //  given the user has fully migrated
    //   [X] it reverts

    function test_givenFullyMigrated(
        uint256 amount_
    ) public givenAliceFullyMigrated givenAliceApproved {
        amount_ = bound(amount_, 1, ALICE_ALLOWANCE);

        // Assert previous state
        assertEq(
            migrator.migratedAmounts(alice),
            ALICE_ALLOWANCE,
            "Alice should have migrated full amount"
        );

        // Mint OHM v1 to alice
        ohmV1.mint(alice, amount_);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(ILegacyMigrator.AmountExceedsAllowance.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(alice);
        migrator.migrate(amount_, aliceProof, ALICE_ALLOWANCE);
    }

    // when the migration cap is reached
    //  [X] it reverts

    function test_givenCapReached_reverts() public givenCapReached givenBobApproved {
        // Assert that the cap is lower than the bob allowance
        assertLt(
            migrator.migrationCap(),
            BOB_ALLOWANCE,
            "Migration cap should be lower than bob allowance"
        );

        // Expect revert
        bytes memory err = abi.encodeWithSelector(ILegacyMigrator.CapExceeded.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(bob);
        migrator.migrate(BOB_ALLOWANCE, bobProof, BOB_ALLOWANCE);
    }

    // given alice attempts to migrate for bob
    //  [X] it reverts

    function test_givenCallerNotProofOwner_reverts() public givenAliceApproved givenBobApproved {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(ILegacyMigrator.InvalidProof.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, bobProof, BOB_ALLOWANCE);
    }

    // given both alice and bob migrate
    //  [X] their migratedAmountss are tracked independently
    //  [X] alice's migration doesn't affect bob's state
    //  [X] bob's migration doesn't affect alice's state

    function test_givenBothMigrated_trackedIndependently()
        public
        givenAliceApproved
        givenBobApproved
    {
        // Alice migrates first
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof, ALICE_ALLOWANCE);

        assertEq(migrator.migratedAmounts(alice), ALICE_ALLOWANCE, "Alice should have migrated");
        assertEq(migrator.migratedAmounts(bob), 0, "Bob should not have migrated yet");

        // Bob migrates second
        vm.prank(bob);
        migrator.migrate(BOB_ALLOWANCE, bobProof, BOB_ALLOWANCE);

        // Both should have independent migrated amounts
        assertEq(
            migrator.migratedAmounts(alice),
            ALICE_ALLOWANCE,
            "Alice should still have full amount"
        );
        assertEq(migrator.migratedAmounts(bob), BOB_ALLOWANCE, "Bob should have migrated");

        // Verify total migrated is sum of both
        assertEq(
            migrator.totalMigrated(),
            ALICE_ALLOWANCE + BOB_ALLOWANCE,
            "Total should be sum of both"
        );

        // Verify balances
        assertEq(ohmV2.balanceOf(alice), ALICE_ALLOWANCE, "Alice should have her OHM v2");
        assertEq(ohmV2.balanceOf(bob), BOB_ALLOWANCE, "Bob should have his OHM v2");
    }

    function test_givenMultipleUsers_partialMigrationsTrackedIndependently()
        public
        givenAliceApproved
        givenBobApproved
    {
        uint256 alicePartial = 300e9;
        uint256 bobPartial = 1000e9;

        // Alice does partial migration
        vm.prank(alice);
        migrator.migrate(alicePartial, aliceProof, ALICE_ALLOWANCE);

        assertEq(migrator.migratedAmounts(alice), alicePartial, "Alice should have partial amount");
        assertEq(migrator.migratedAmounts(bob), 0, "Bob should not have migrated yet");

        // Bob does partial migration
        vm.prank(bob);
        migrator.migrate(bobPartial, bobProof, BOB_ALLOWANCE);

        // Verify independent tracking
        assertEq(migrator.migratedAmounts(alice), alicePartial, "Alice should still have partial");
        assertEq(migrator.migratedAmounts(bob), bobPartial, "Bob should have partial");

        // Verify total
        assertEq(migrator.totalMigrated(), alicePartial + bobPartial, "Total should be sum");

        // Alice can migrate remaining
        uint256 aliceRemaining = ALICE_ALLOWANCE - alicePartial;
        vm.prank(alice);
        migrator.migrate(aliceRemaining, aliceProof, ALICE_ALLOWANCE);
        assertEq(migrator.migratedAmounts(alice), ALICE_ALLOWANCE, "Alice should have full");
        assertEq(migrator.migratedAmounts(bob), bobPartial, "Bob should still have partial");

        // Bob can migrate remaining
        uint256 bobRemaining = BOB_ALLOWANCE - bobPartial;
        vm.prank(bob);
        migrator.migrate(bobRemaining, bobProof, BOB_ALLOWANCE);
        assertEq(migrator.migratedAmounts(alice), ALICE_ALLOWANCE, "Alice should still have full");
        assertEq(migrator.migratedAmounts(bob), BOB_ALLOWANCE, "Bob should have full");
    }

    // given user has migrated and merkle root is updated to different value
    //  when the user attempts to migrate again with the old proof
    //   [X] it reverts

    function test_givenRootUpdated_whenProofIsOld_reverts()
        public
        givenAlicePartiallyMigrated(500e9)
    {
        // Assert previous state
        assertEq(
            migrator.migratedAmounts(alice),
            500e9,
            "Alice should have migrated partial amount"
        );

        // Set new merkle root
        bytes32 newRoot = bytes32(uint256(1));
        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(newRoot);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(ILegacyMigrator.InvalidProof.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof, ALICE_ALLOWANCE);
    }

    //  [X] the user can migrate up to their new allocation

    function test_givenRootRefreshed_canMigrateAgain(
        uint256 amount_
    ) public givenAlicePartiallyMigrated(500e9) givenAliceApproved {
        amount_ = bound(amount_, 1, ALICE_ALLOWANCE);

        // Ensure that alice has enough OHM v1 to migrate a second time
        ohmV1.mint(alice, amount_);

        // Assert previous state
        assertEq(
            migrator.migratedAmounts(alice),
            500e9,
            "Alice should have migrated partial amount"
        );

        // Refresh the merkle tree (same allocations, new root/proofs)
        _refreshMerkleTree();

        // Verify reset
        assertEq(migrator.migratedAmounts(alice), 0, "Alice should be reset after root change");

        // Call function
        vm.prank(alice);
        migrator.migrate(amount_, aliceProof, ALICE_ALLOWANCE);

        // Assert state
        assertEq(migrator.migratedAmounts(alice), amount_, "Alice should have migrated amount");
        assertEq(
            ohmV2.balanceOf(alice),
            500e9 + amount_,
            "Alice should receive previously migrated amount + new amount of OHM v2"
        );
    }

    function test_fuzz_migrate_exceedsAllowance_reverts(uint256 amount) public givenAliceApproved {
        // Only test amounts that exceed the allowance
        vm.assume(amount > ALICE_ALLOWANCE);

        bytes memory err = abi.encodeWithSignature("AmountExceedsAllowance()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(amount, aliceProof, ALICE_ALLOWANCE);
    }

    function test_fuzz(uint256 amount_) public givenAliceApproved {
        amount_ = bound(amount_, 1, ALICE_ALLOWANCE);

        // Call function
        vm.prank(alice);
        migrator.migrate(amount_, aliceProof, ALICE_ALLOWANCE);

        // Assert state
        assertEq(migrator.migratedAmounts(alice), amount_, "Migrated amount should match input");
    }
}
