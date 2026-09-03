// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity ^0.8.20;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Scripts
import {ProposalScript} from "./ProposalScript.sol";

// Olympus Kernel, Modules, and Policies
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {V1Migrator} from "src/policies/V1Migrator.sol";

/// @notice Configures V1Migrator for the final OHM v1 migration.
contract V1MigratorAdminProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    // Casting is safe because this fixed role label is shorter than 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant LEGACY_MIGRATION_ADMIN_ROLE = bytes32("legacy_migration_admin");

    uint256 public constant MAX_MIGRATABLE_OHM_V1 = 102_397_596_876_863;

    error DaoMsMissingLegacyMigrationAdminRole();
    error InvalidRemainingMintApproval(uint256 actual, uint256 expected);

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 18;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "Configure V1Migrator Admin Role and Migration Cap";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Configure V1Migrator Admin Role and Migration Cap\n\n",
                "## Summary\n\n",
                "This proposal grants the `legacy_migration_admin` role to the DAO MS on Ethereum mainnet and sets the remaining V1Migrator mint approval to 102,397.596876863 OHM.\n\n",
                "## Context\n\n",
                // solhint-disable-next-line quotes
                'This builds off OCG proposal ID 13, "Defund OHM v1 TokenMigrator and Enable V1Migrator". Proposal ID 13 enabled the V1Migrator policy and noted that the DAO MS would update the V1Migrator merkle root as a follow-on action.\n\n',
                "The V1Migrator `setMerkleRoot(bytes32)` function is callable by either a policy admin or an address with the `legacy_migration_admin` role. Granting this role to the DAO MS enables the DAO MS to set the merkle root through a Safe transaction.\n\n",
                "The maximum OHM v1 that can be migrated has been determined to be 102,397.596876863 OHM v1. V1Migrator enforces this through its remaining MINTR mint approval, which is denominated in OHM v2 units. The full aggregate OHM v1 amount previews to 102,397.596876862 OHM v2 due to gOHM conversion rounding, so a 102,397.596876863 OHM remaining mint approval covers the full migration amount.\n\n",
                "## Actions\n\n",
                "1. Grant `legacy_migration_admin` to the DAO MS.\n",
                "2. Set V1Migrator remaining mint approval to 102,397.596876863 OHM.\n\n",
                "## Follow-on Actions\n\n",
                "1. DAO MS submits the V1Migrator `setMerkleRoot(bytes32)` transaction with the finalized merkle root.\n\n",
                "No additional OCG action is required for the DAO MS to set the V1Migrator merkle root after this role grant."
            );
    }

    // No deploy actions needed.
    function _deploy(Addresses addresses, address) internal override {
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal.
    function _build(Addresses addresses) internal override {
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address v1Migrator = addresses.getAddress("olympus-policy-v1-migrator");
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                LEGACY_MIGRATION_ADMIN_ROLE,
                daoMS
            ),
            "Grant legacy_migration_admin to DAO MS"
        );

        _pushAction(
            v1Migrator,
            abi.encodeWithSelector(
                V1Migrator.setRemainingMintApproval.selector,
                MAX_MIGRATABLE_OHM_V1
            ),
            "Set V1Migrator remaining mint approval"
        );
    }

    // Executes the proposal actions.
    function _run(Addresses addresses, address) internal override {
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    // Validates the post-execution state.
    function _validate(Addresses addresses, address) internal view override {
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        V1Migrator v1Migrator = V1Migrator(addresses.getAddress("olympus-policy-v1-migrator"));
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        if (!roles.hasRole(daoMS, LEGACY_MIGRATION_ADMIN_ROLE)) {
            revert DaoMsMissingLegacyMigrationAdminRole();
        }

        uint256 remainingMintApproval = v1Migrator.remainingMintApproval();
        if (remainingMintApproval != MAX_MIGRATABLE_OHM_V1) {
            revert InvalidRemainingMintApproval(remainingMintApproval, MAX_MIGRATABLE_OHM_V1);
        }
    }
}

contract V1MigratorAdminProposalScript is ProposalScript {
    constructor() ProposalScript(new V1MigratorAdminProposal()) {}
}
