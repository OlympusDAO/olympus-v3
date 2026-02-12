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
import {V1Migrator} from "src/policies/V1Migrator.sol";
import {Burner} from "src/policies/Burner.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @notice Proposal to enable V1Migrator for OHM v1 migration and execute gOHM burn
contract MigrationProposal is GovernorBravoProposal {
    // Kernel will be used in most proposals
    address internal _kernel;
    // V1Migrator and MigrationProposalHelper deployed separately, retrieved from addresses
    V1Migrator internal _v1Migrator;
    MigrationProposalHelper internal _migrationProposalHelper;

    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant BURNER_ADMIN_ROLE = bytes32("burner_admin");

    /// @notice Initial migration cap for V1Migrator (in OHM v1, 9 decimals)
    /// @dev    TODO: Update migration cap before mainnet deployment
    uint256 public constant INITIAL_MIGRATION_CAP = 1000e9;

    error InvalidV1Migrator();
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
        return "Defund OHM v1 TokenMigrator and Enable V1Migrator";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Defund OHM v1 TokenMigrator and Enable V1Migrator\n\n",
                "This proposal defunds the old OHM v1 TokenMigrator and enables the V1Migrator policy to allow OHM v1 holders to migrate to OHM v2.\n\n",
                "## Summary\n\n",
                "This proposal has two main steps:\n\n",
                "1. Enable V1Migrator policy for OHM v1 to OHM v2 migration\n",
                "2. Execute MigrationProposalHelper.activate() to perform defunding of the old TokenMigrator\n\n",
                "## Background\n\n",
                "The OHM v1 TokenMigrator was used to migrate OHM v1 to gOHM.\n"
                "This migrator contains a surplus of gOHM (which inflates supply), and serves as technical debt.\n",
                "This proposal extracts all gOHM from the TokenMigrator, unstakes it to OHM v2 and burns it.\n",
                "The proposed V1Migrator policy replaces the old TokenMigrator.\n",
                "It uses a merkle tree to verify eligible OHM v1 holders, and allows them to migrate their tokens to OHM v2.\n\n",
                "## Steps\n\n",
                "1. Enable V1Migrator policy (allows users to migrate OHM v1 to OHM v2) with an initial migration cap of XXX OHM v1\n", // TODO add initial migration cap
                "2. Grant `burner_admin` role to MigrationProposalHelper\n",
                "3. Grant MigrationProposalHelper permission to spend tempOHM\n",
                "4. Call MigrationProposalHelper.activate() which:\n",
                '   - Adds burner category "migration"\n',
                "   - Deposits a dummy asset (tempOHM) into the legacy treasury, in order to mint the maximum amount of OHM v1 that can be migrated\n",
                "   - Migrates OHM v1 to gOHM\n",
                "   - Burns gOHM to receive OHM v2\n",
                "5. Revoke `burner_admin` role from MigrationProposalHelper\n\n",
                "## Additional Steps\n\n",
                "1. DAO MS to update the merkle root for the V1Migrator policy\n",
                "2. DAO MS to remove tempOHM as a reserve token from the legacy treasury\n",
                "3. DAO MS to remove MigrationProposalHelper as a reserve depositor from the legacy treasury\n\n",
                "## Note\n\n",
                "Treasury permissions for tempOHM and MigrationProposalHelper should be set up separately by the DAO MS before this proposal is executed.\n"
            );
    }

    function _deploy(Addresses addresses, address) internal override {
        // Store the kernel address in state
        _kernel = addresses.getAddress("olympus-kernel");

        // Retrieve V1Migrator and MigrationProposalHelper from addresses
        address v1MigratorAddr = addresses.getAddress("olympus-policy-v1-migrator");
        if (v1MigratorAddr == address(0)) revert InvalidV1Migrator();
        _v1Migrator = V1Migrator(v1MigratorAddr);

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
        address tempOHM = addresses.getAddress("external-tokens-tempohm");
        address timelock = addresses.getAddress("olympus-timelock");

        // STEP 1: Enable V1Migrator policy
        _pushAction(
            address(_v1Migrator),
            abi.encodeWithSelector(IEnabler.enable.selector, abi.encode(INITIAL_MIGRATION_CAP)),
            "Enable V1Migrator policy"
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

        // STEP 3: Grant MigrationProposalHelper permission to spend all tempOHM
        // Approve max uint256 to handle any balance changes between proposal submission and execution
        _pushAction(
            address(tempOHM),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(_migrationProposalHelper),
                type(uint256).max
            ),
            "Grant MigrationProposalHelper permission to spend tempOHM"
        );

        // STEP 4: Call MigrationProposalHelper.activate()
        _pushAction(
            address(_migrationProposalHelper),
            abi.encodeWithSelector(MigrationProposalHelper.activate.selector),
            "Execute gOHM burn via MigrationProposalHelper"
        );

        // STEP 5: Revoke "burner_admin" role from MigrationProposalHelper
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

        // STEP 6. Revoke any spending approval for tempOHM
        _pushAction(
            address(tempOHM),
            abi.encodeWithSelector(IERC20.approve.selector, address(_migrationProposalHelper), 0),
            "Revoke any spending approval for tempOHM"
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
        address OHMv1 = addresses.getAddress("olympus-legacy-ohm-v1");
        address OHMv2 = addresses.getAddress("olympus-legacy-ohm-v2");
        address GOHM = addresses.getAddress("olympus-legacy-gohm");
        address tempOHM = addresses.getAddress("external-tokens-tempohm");

        // solhint-disable custom-errors

        // 1. Validate that V1Migrator is enabled
        require(_v1Migrator.isEnabled() == true, "V1Migrator should be enabled");

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
            roles.hasRole(address(_migrationProposalHelper), BURNER_ADMIN_ROLE) == false,
            "MigrationProposalHelper should not have burner_admin role"
        );

        // 5. Validate that there is no gOHM, OHMv2, or OHMv1 left in the MigrationProposalHelper contract
        // Note: Timelock balance checks are intentionally omitted to prevent griefing. An attacker could
        // donate 1 wei of these tokens to the timelock address while the proposal is queued, causing
        // validation to fail when the proposal executes. These tokens could also legitimately exist
        // in the timelock for unrelated reasons (they're not migration-specific). The helper contract
        // is responsible for burning all migration-related tokens it receives during activation.
        require(
            IERC20(GOHM).balanceOf(address(_migrationProposalHelper)) == 0,
            "There should be no gOHM left in the MigrationProposalHelper contract"
        );
        require(
            IERC20(OHMv2).balanceOf(address(_migrationProposalHelper)) == 0,
            "There should be no OHMv2 left in the MigrationProposalHelper contract"
        );
        require(
            IERC20(OHMv1).balanceOf(address(_migrationProposalHelper)) == 0,
            "There should be no OHMv1 left in the MigrationProposalHelper contract"
        );

        // 6. Validate that there is no tempOHM left in the Timelock or the MigrationProposalHelper contract
        // tempOHM is migration-specific and should be zero in both places
        address timelock = addresses.getAddress("olympus-timelock");
        require(
            IERC20(tempOHM).balanceOf(timelock) == 0,
            "There should be no tempOHM left in the Timelock"
        );
        require(
            IERC20(tempOHM).balanceOf(address(_migrationProposalHelper)) == 0,
            "There should be no tempOHM left in the MigrationProposalHelper contract"
        );

        // 7. Validate that there is no dangling approval for tempOHM to be spent by the MigrationProposalHelper
        require(
            IERC20(tempOHM).allowance(address(timelock), address(_migrationProposalHelper)) == 0,
            "There should be no dangling approval for tempOHM to be spent by the MigrationProposalHelper"
        );
    }
}

contract MigrationProposalScript is ProposalScript {
    constructor() ProposalScript(new MigrationProposal()) {}
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
