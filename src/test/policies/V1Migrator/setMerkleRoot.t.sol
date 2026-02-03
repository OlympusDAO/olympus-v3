// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {V1MigratorTest} from "./V1MigratorTest.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IV1Migrator} from "src/policies/interfaces/IV1Migrator.sol";

contract V1MigratorSetMerkleRootTest is V1MigratorTest {
    event MerkleRootUpdated(bytes32 indexed newRoot, address indexed updater);

    // ========== SET MERKLE ROOT TESTS ========== //

    // given the contract is disabled
    //  [X] admin can still set merkle root

    function test_givenDisabled_succeeds() public givenContractDisabled {
        bytes32 newRoot = bytes32(uint256(1));

        // Call function - should succeed even when disabled
        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(newRoot);

        // Assert state
        assertEq(migrator.merkleRoot(), newRoot, "Merkle root should be updated");
    }

    // given caller does not have legacy_migration_admin or admin role
    //  [X] it reverts

    function test_givenNonAuthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != legacyMigrationAdmin && caller_ != adminUser);

        bytes32 newRoot = bytes32(uint256(1));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(caller_);
        migrator.setMerkleRoot(newRoot);
    }

    // given caller has legacy_migration_admin or admin role
    //  when the merkle root is any bytes32 value
    //   [X] it sets the merkle root

    function test_fuzz(bytes32 newRoot_) public {
        // Call function
        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(newRoot_);

        // Assert state
        assertEq(migrator.merkleRoot(), newRoot_, "Merkle root should match input");
    }

    //  [X] it sets the merkle root
    //  [X] it resets migratedAmounts for all users

    function test_succeeds(uint8 callerIndex_) public givenAlicePartiallyMigrated(500e9) {
        vm.assume(callerIndex_ < 2);

        // Set the caller
        address caller = callerIndex_ == 0 ? legacyMigrationAdmin : adminUser;

        // Assert previous state
        assertEq(
            migrator.migratedAmounts(alice),
            500e9,
            "Alice should have migrated partial amount"
        );

        bytes32 newRoot = bytes32(uint256(2));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit MerkleRootUpdated(newRoot, caller);

        // Call function
        vm.prank(caller);
        migrator.setMerkleRoot(newRoot);

        // Assert new state
        assertEq(migrator.merkleRoot(), newRoot, "Merkle root should be updated");
        assertEq(migrator.migratedAmounts(alice), 0, "Alice should be reset after root change");
    }

    // given the merkle root is set to the same value
    //  [X] it reverts

    function test_givenSameMerkleRoot_reverts() public {
        bytes32 currentRoot = migrator.merkleRoot();

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IV1Migrator.SameMerkleRoot.selector));

        // Call function with same root
        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(currentRoot);
    }
}
