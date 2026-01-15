// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Contracts
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {MigrationHelper} from "src/proposals/MigrationHelper.sol";
import {LegacyMigrator} from "src/policies/LegacyMigrator.sol";
import {Burner} from "src/policies/Burner.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @notice Proposal to enable LegacyMigrator for OHM v1 migration and execute gOHM burn
contract MigrationProposal is GovernorBravoProposal {
    // Kernel will be used in most proposals
    address internal _kernel;
    // LegacyMigrator and MigrationHelper deployed separately, retrieved from addresses
    LegacyMigrator internal _legacyMigrator;
    MigrationHelper internal _migrationHelper;

    error InvalidLegacyMigrator();
    error InvalidMigrationHelper();

    constructor() {
        // Addresses will be retrieved from Addresses in _deploy()
    }

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 0;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "Migration Proposal";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# OHM v1 Migration via LegacyMigrator\n\n",
                "This proposal enables the LegacyMigrator policy and executes the gOHM burn.\n\n",
                "## Summary\n\n",
                "This proposal has two main steps:\n\n",
                "1. Enable LegacyMigrator policy for OHM v1 to OHM v2 migration\n",
                "2. Execute MigrationHelper.activate() to perform the gOHM burn\n\n",
                "## Background\n\n",
                "The LegacyMigrator policy uses a merkle tree to verify eligible OHM v1 holders ",
                "and allows them to migrate their tokens to OHM v2. This policy is pre-deployed ",
                "and only needs to be enabled via this proposal.\n\n",
                "The MigrationHelper contract performs the final gOHM burn after the migration period.\n\n",
                "## Steps\n\n",
                "1. Enable LegacyMigrator policy (allows users to migrate OHM v1 to OHM v2)\n",
                "2. Grant `burner_admin` role to MigrationHelper\n",
                "3. Call MigrationHelper.activate() which:\n",
                '   - Adds burner category "migration"\n',
                "   - Burns gOHM to receive OHM v2\n",
                '   - Burns OHM v2 with category "migration"\n',
                "4. Revoke `burner_admin` role from MigrationHelper\n\n",
                "## Note\n\n",
                "Treasury permissions for tempOHM and MigrationHelper should be set up separately ",
                "via the MigrationProposalSetup script before this proposal is executed."
            );
    }

    function _deploy(Addresses addresses, address) internal override {
        // Store the kernel address in state
        _kernel = addresses.getAddress("olympus-kernel");

        // Retrieve LegacyMigrator and MigrationHelper from addresses
        address legacyMigratorAddr = addresses.getAddress("olympus-policy-legacy-migrator");
        if (legacyMigratorAddr == address(0)) revert InvalidLegacyMigrator();
        _legacyMigrator = LegacyMigrator(legacyMigratorAddr);

        address migrationHelperAddr = addresses.getAddress("olympus-policy-migration-helper");
        if (migrationHelperAddr == address(0)) revert InvalidMigrationHelper();
        _migrationHelper = MigrationHelper(migrationHelperAddr);
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");

        // STEP 1: Enable LegacyMigrator policy
        _pushAction(
            address(_legacyMigrator),
            abi.encodeWithSelector(IEnabler.enable.selector, abi.encode("")),
            "Enable LegacyMigrator policy"
        );

        // STEP 2: Grant "burner_admin" role to MigrationHelper
        _pushAction(
            rolesAdmin,
            /// forge-lint: disable-next-line(unsafe-typecast)
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("burner_admin"),
                address(_migrationHelper)
            ),
            "Grant burner_admin role to MigrationHelper"
        );

        // STEP 3: Call MigrationHelper.activate()
        _pushAction(
            address(_migrationHelper),
            abi.encodeWithSelector(MigrationHelper.activate.selector),
            "Execute gOHM burn via MigrationHelper"
        );

        // STEP 4: Revoke "burner_admin" role from MigrationHelper
        _pushAction(
            rolesAdmin,
            /// forge-lint: disable-next-line(unsafe-typecast)
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("burner_admin"),
                address(_migrationHelper)
            ),
            "Revoke burner_admin role from MigrationHelper"
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
        address OHMv1 = _migrationHelper.OHMV1();
        address OHMv2 = _migrationHelper.OHMV2();
        address GOHM = _migrationHelper.GOHM();

        // solhint-disable custom-errors

        // 1. Validate that LegacyMigrator is enabled
        require(_legacyMigrator.isEnabled() == true, "LegacyMigrator should be enabled");

        // 2. Validate that MigrationHelper is marked as activated
        require(_migrationHelper.isActivated() == true, "MigrationHelper should be activated");

        // 3. Validate that "migration" category exists in Burner
        bytes32 migrationCategory = _migrationHelper.MIGRATION_CATEGORY();
        require(
            Burner(burner).categoryApproved(migrationCategory) == true,
            "Migration category should be approved in Burner"
        );

        // 4. Validate that burner_admin role was revoked from MigrationHelper
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(address(_migrationHelper), bytes32("burner_admin")) == false,
            "MigrationHelper should not have burner_admin role"
        );

        // 5. Validate that there is no gOHM left in the Timelock or the MigrationHelper contract
        address timelock = addresses.getAddress("olympus-timelock");
        require(
            IERC20(GOHM).balanceOf(timelock) == 0,
            "There should be no gOHM left in the Timelock"
        );
        require(
            IERC20(GOHM).balanceOf(address(_migrationHelper)) == 0,
            "There should be no gOHM left in the MigrationHelper contract"
        );

        // 6. Validate that there is no OHMv2 left in the Timelock or the MigrationHelper contract
        require(
            IERC20(OHMv2).balanceOf(timelock) == 0,
            "There should be no OHMv2 left in the Timelock"
        );
        require(
            IERC20(OHMv2).balanceOf(address(_migrationHelper)) == 0,
            "There should be no OHMv2 left in the MigrationHelper contract"
        );
    }
}
