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
    uint256 public constant MAX_MIGRATABLE_OHM_V1 = 102_397_596_876_863;
    uint256 public constant EXPECTED_OHM_V2_PREVIEW = 102_397_596_876_862;

    ROLESv1 public roles;
    V1Migrator public v1Migrator;
    address public daoMS;

    function setUp() public virtual {
        vm.createSelectFork(_RPC_ALIAS, BLOCK);

        V1MigratorAdminProposal proposal = new V1MigratorAdminProposal();

        hasBeenSubmitted = false;

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
        assertEq(
            v1Migrator.remainingMintApproval(),
            MAX_MIGRATABLE_OHM_V1,
            "V1Migrator remaining mint approval should match max migratable OHM v1"
        );
    }

    function test_maxMigratableOhmV1FitsWithinRemainingMintApproval() public view {
        uint256 ohmV2Preview = v1Migrator.previewMigrate(MAX_MIGRATABLE_OHM_V1);

        // previewMigrate converts OHM v1 (9 decimals) to gOHM (18 decimals) and back.
        // At this fork block, gOHM index = 269_238_508_004 (9 decimals).
        // gOHM = floor(102_397_596_876_863 * 1e18 / 269_238_508_004)
        //      = 380_322_999_246_978_845_994
        // OHM v2 = floor(380_322_999_246_978_845_994 * 269_238_508_004 / 1e18)
        //        = 102_397_596_876_862
        // The two floor divisions round down by one 9-decimal OHM base unit:
        // 102,397.596876863 OHM v1 -> 102,397.596876862 OHM v2.
        assertEq(
            ohmV2Preview,
            EXPECTED_OHM_V2_PREVIEW,
            "Full max migratable OHM v1 amount should preview with one OHM base unit rounded down"
        );
        assertLe(
            ohmV2Preview,
            v1Migrator.remainingMintApproval(),
            "V1Migrator remaining mint approval should cover the full max migratable OHM v1 preview"
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
