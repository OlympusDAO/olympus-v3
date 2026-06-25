// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {V1Migrator} from "src/policies/V1Migrator.sol";
import {V1MigratorAdminProposal} from "src/proposals/V1MigratorAdminProposal.sol";

contract V1MigratorAdminProposalTest is ProposalTest {
    uint256 public constant BLOCK = 25395851 + 1;

    // Casting is safe because this fixed role label is shorter than 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant LEGACY_MIGRATION_ADMIN_ROLE = bytes32("legacy_migration_admin");
    bytes32 public constant TEST_MERKLE_ROOT =
        0x4f02394ace62d235ea2896d0a0cc2ecdd57b0f5bb7f4739daab260f90ddd7bdb;

    ROLESv1 public roles;
    V1Migrator public v1Migrator;
    address public daoMS;

    function setUp() public virtual {
        vm.createSelectFork(_RPC_ALIAS, BLOCK);

        V1MigratorAdminProposal proposal = new V1MigratorAdminProposal();

        hasBeenSubmitted = true;

        _setupSuite(address(proposal));

        roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        v1Migrator = V1Migrator(addresses.getAddress("olympus-policy-v1-migrator"));
        daoMS = addresses.getAddress("olympus-multisig-dao");

        assertFalse(
            roles.hasRole(daoMS, LEGACY_MIGRATION_ADMIN_ROLE),
            "DAO MS should not already have the legacy_migration_admin role"
        );

        _simulateProposal();
    }

    function test_proposalEndState() public view {
        assertTrue(
            roles.hasRole(daoMS, LEGACY_MIGRATION_ADMIN_ROLE),
            "DAO MS should have the legacy_migration_admin role"
        );
    }

    function test_daoMSCanSetMerkleRoot() public {
        bytes32 newRoot = v1Migrator.merkleRoot() == TEST_MERKLE_ROOT
            ? bytes32(uint256(TEST_MERKLE_ROOT) + 1)
            : TEST_MERKLE_ROOT;

        vm.prank(daoMS);
        v1Migrator.setMerkleRoot(newRoot);

        assertEq(v1Migrator.merkleRoot(), newRoot, "DAO MS should be able to set the merkle root");
    }
}
