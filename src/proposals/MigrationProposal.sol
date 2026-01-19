// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.20;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "./ProposalScript.sol";

// Contracts
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {MigrationProposalHelper} from "src/proposals/MigrationProposalHelper.sol";
import {LegacyMigrator} from "src/policies/LegacyMigrator.sol";
import {Burner} from "src/policies/Burner.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @notice Proposal to enable LegacyMigrator for OHM v1 migration and execute gOHM burn
contract MigrationProposal is GovernorBravoProposal {
    // Kernel will be used in most proposals
    address internal _kernel;
    // LegacyMigrator and MigrationProposalHelper deployed separately, retrieved from addresses
    LegacyMigrator internal _legacyMigrator;
    MigrationProposalHelper internal _migrationProposalHelper;

    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant BURNER_ADMIN_ROLE = bytes32("burner_admin");

    /// @notice Initial migration cap for LegacyMigrator (in OHM v1, 9 decimals)
    /// @dev    TODO: Update migration cap before mainnet deployment
    uint256 public constant INITIAL_MIGRATION_CAP = 1000e9;

    error InvalidLegacyMigrator();
    error InvalidMigrationProposalHelper();

    constructor() {
        // Addresses will be retrieved from Addresses in _deploy()
    }

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 13;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "Defund OHM v1 TokenMigrator and Enable LegacyMigrator";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Defund OHM v1 TokenMigrator and Enable LegacyMigrator\n\n",
                "This proposal defunds the old OHM v1 TokenMigrator and enables the LegacyMigrator policy to allow OHM v1 holders to migrate to OHM v2.\n\n",
                "## Summary\n\n",
                "This proposal has two main steps:\n\n",
                "1. Enable LegacyMigrator policy for OHM v1 to OHM v2 migration\n",
                "2. Execute MigrationProposalHelper.activate() to perform defunding of the old TokenMigrator\n\n",
                "## Background\n\n",
                "The OHM v1 TokenMigrator was used to migrate OHM v1 to gOHM.\n"
                "This migrator contains a surplus of gOHM (which inflates supply), and serves as technical debt.\n",
                "This proposal extracts all gOHM from the TokenMigrator, unstakes it to OHM v2 and burns it.\n",
                "The proposed LegacyMigrator policy replaces the old TokenMigrator.\n",
                "It uses a merkle tree to verify eligible OHM v1 holders, and allows them to migrate their tokens to OHM v2.\n",
                "## Steps\n\n",
                "1. Enable LegacyMigrator policy (allows users to migrate OHM v1 to OHM v2) with an initial migration cap of XXX OHM v1\n", // TODO add initial migration cap
                "2. Grant `burner_admin` role to MigrationProposalHelper\n",
                "3. Call MigrationProposalHelper.activate() which:\n",
                '   - Adds burner category "migration"\n',
                "   - Deposits a dummy asset (tempOHM) into the legacy treasury, in order to mint the maximum amount of OHM v1 that can be migrated\n",
                "   - Migrates OHM v1 to gOHM\n",
                "   - Burns gOHM to receive OHM v2\n",
                "4. Revoke `burner_admin` role from MigrationProposalHelper\n\n",
                "## Additional Steps\n\n",
                "1. DAO MS to update the merkle root for the LegacyMigrator policy\n",
                "2. DAO MS to remove tempOHM as a reserve token from the legacy treasury\n",
                "3. DAO MS to remove MigrationProposalHelper as a reserve depositor from the legacy treasury\n",
                "## Note\n\n",
                "Treasury permissions for tempOHM and MigrationProposalHelper should be set up separately by the DAO MS before this proposal is executed.\n"
            );
    }

    function _deploy(Addresses addresses, address) internal override {
        // Store the kernel address in state
        _kernel = addresses.getAddress("olympus-kernel");

        // Retrieve LegacyMigrator and MigrationProposalHelper from addresses
        address legacyMigratorAddr = addresses.getAddress("olympus-policy-legacy-migrator");
        if (legacyMigratorAddr == address(0)) revert InvalidLegacyMigrator();
        _legacyMigrator = LegacyMigrator(legacyMigratorAddr);

        address migrationProposalHelperAddr = addresses.getAddress(
            "olympus-periphery-migration-proposal-helper"
        );
        if (migrationProposalHelperAddr == address(0)) revert InvalidMigrationProposalHelper();
        _migrationProposalHelper = MigrationProposalHelper(migrationProposalHelperAddr);
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");

        // STEP 1: Enable LegacyMigrator policy
        _pushAction(
            address(_legacyMigrator),
            abi.encodeWithSelector(IEnabler.enable.selector, abi.encode(INITIAL_MIGRATION_CAP)),
            "Enable LegacyMigrator policy"
        );

        // STEP 2: Grant "burner_admin" role to MigrationProposalHelper
        _pushAction(
            rolesAdmin,
            /// forge-lint: disable-next-line(unsafe-typecast)
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                BURNER_ADMIN_ROLE,
                address(_migrationProposalHelper)
            ),
            "Grant burner_admin role to MigrationProposalHelper"
        );

        // STEP 3: Call MigrationProposalHelper.activate()
        _pushAction(
            address(_migrationProposalHelper),
            abi.encodeWithSelector(MigrationProposalHelper.activate.selector),
            "Execute gOHM burn via MigrationProposalHelper"
        );

        // STEP 4: Revoke "burner_admin" role from MigrationProposalHelper
        _pushAction(
            rolesAdmin,
            /// forge-lint: disable-next-line(unsafe-typecast)
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                BURNER_ADMIN_ROLE,
                address(_migrationProposalHelper)
            ),
            "Revoke burner_admin role from MigrationProposalHelper"
        );
    }

    // Executes the proposal actions.
    function _run(Addresses addresses, address) internal override {
        // Simulates actions on TimelockController
        _simulateActions(
            _kernel,
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    // Validates the post-execution state.
    function _validate(Addresses addresses, address) internal view override {
        // Load the contract addresses
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address burner = addresses.getAddress("olympus-policy-burner");
        address OHMv1 = _migrationProposalHelper.OHMV1();
        address OHMv2 = _migrationProposalHelper.OHMV2();
        address GOHM = _migrationProposalHelper.GOHM();

        // solhint-disable custom-errors

        // 1. Validate that LegacyMigrator is enabled
        require(_legacyMigrator.isEnabled() == true, "LegacyMigrator should be enabled");

        // 2. Validate that MigrationProposalHelper is marked as activated
        require(
            _migrationProposalHelper.isActivated() == true,
            "MigrationProposalHelper should be activated"
        );

        // 3. Validate that "migration" category exists in Burner
        bytes32 migrationCategory = _migrationProposalHelper.MIGRATION_CATEGORY();
        require(
            Burner(burner).categoryApproved(migrationCategory) == true,
            "Migration category should be approved in Burner"
        );

        // 4. Validate that burner_admin role was revoked from MigrationProposalHelper
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(address(_migrationProposalHelper), bytes32("burner_admin")) == false,
            "MigrationProposalHelper should not have burner_admin role"
        );

        // 5. Validate that there is no gOHM left in the Timelock or the MigrationProposalHelper contract
        address timelock = addresses.getAddress("olympus-timelock");
        require(
            IERC20(GOHM).balanceOf(timelock) == 0,
            "There should be no gOHM left in the Timelock"
        );
        require(
            IERC20(GOHM).balanceOf(address(_migrationProposalHelper)) == 0,
            "There should be no gOHM left in the MigrationProposalHelper contract"
        );

        // 6. Validate that there is no OHMv2 left in the Timelock or the MigrationProposalHelper contract
        require(
            IERC20(OHMv2).balanceOf(timelock) == 0,
            "There should be no OHMv2 left in the Timelock"
        );
        require(
            IERC20(OHMv2).balanceOf(address(_migrationProposalHelper)) == 0,
            "There should be no OHMv2 left in the MigrationProposalHelper contract"
        );

        // 7. Validate that there is no OHMv1 left in the Timelock or the MigrationProposalHelper contract
        require(
            IERC20(OHMv1).balanceOf(timelock) == 0,
            "There should be no OHMv1 left in the Timelock"
        );
        require(
            IERC20(OHMv1).balanceOf(address(_migrationProposalHelper)) == 0,
            "There should be no OHMv1 left in the MigrationProposalHelper contract"
        );
    }
}

contract MigrationProposalScript is ProposalScript {
    constructor() ProposalScript(new MigrationProposal()) {}
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
