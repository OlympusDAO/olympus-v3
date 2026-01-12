// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Contracts
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {MigrationHelper} from "src/proposals/MigrationHelper.sol";
import {Burner} from "src/policies/Burner.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @notice Proposal to execute OHM v1 migration to OHM v2 and burn
contract MigrationProposal is GovernorBravoProposal {
    // Kernel will be used in most proposals
    address internal _kernel;
    // MigrationHelper deployed separately, passed during construction
    MigrationHelper internal _migrationHelper;
    // tempOHM address passed during construction
    address internal _tempOHM;

    error InvalidTempOHM();
    error InvalidMigrationHelper();

    constructor(address tempOHM_, address migrationHelper_) {
        if (tempOHM_ == address(0)) revert InvalidTempOHM();
        if (migrationHelper_ == address(0)) revert InvalidMigrationHelper();
        _tempOHM = tempOHM_;
        _migrationHelper = MigrationHelper(migrationHelper_);
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
                "# OHM v1 Migration\n\n",
                "This proposal executes the migration of OHM v1 to OHM v2 and burns the migrated tokens.\n\n",
                "## Summary\n\n",
                "This proposal has three main steps:\n\n",
                "1. Grant `burner_admin` role to MigrationHelper\n",
                "2. Execute MigrationHelper.activate() to perform the migration\n",
                "3. Revoke `burner_admin` role from MigrationHelper\n\n",
                "## Steps\n\n",
                "1. Grant `burner_admin` role to MigrationHelper contract\n",
                "2. Approve tempOHM to MigrationHelper (from Timelock)\n",
                "3. Call MigrationHelper.activate() which:\n",
                '   - Adds burner category "migration"\n',
                "   - Deposits tempOHM to treasury to receive OHM v1\n",
                "   - Migrates OHM v1 to gOHM\n",
                "   - Unstakes gOHM to OHM v2\n",
                '   - Burns OHM v2 with category "migration"\n',
                "4. Revoke `burner_admin` role from MigrationHelper contract\n"
            );
    }

    function _deploy(Addresses addresses, address) internal override {
        // Store the kernel address in state
        _kernel = addresses.getAddress("olympus-kernel");
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");

        // STEP 1: Grant "burner_admin" role to MigrationHelper
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

        // STEP 2: Approve tempOHM to MigrationHelper (from Timelock)
        _pushAction(
            _tempOHM,
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(_migrationHelper),
                type(uint256).max
            ),
            "Approve tempOHM to MigrationHelper"
        );

        // STEP 3: Call MigrationHelper.activate()
        _pushAction(
            address(_migrationHelper),
            abi.encodeWithSelector(MigrationHelper.activate.selector),
            "Execute migration via MigrationHelper"
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

        // 1. Validate that MigrationHelper is marked as activated
        require(_migrationHelper.isActivated() == true, "MigrationHelper should be activated");

        // 2. Validate that "migration" category exists in Burner
        bytes32 migrationCategory = _migrationHelper.MIGRATION_CATEGORY();
        require(
            Burner(burner).categoryApproved(migrationCategory) == true,
            "Migration category should be approved in Burner"
        );

        // 3. Validate that burner_admin role was revoked from MigrationHelper
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(address(_migrationHelper), bytes32("burner_admin")) == false,
            "MigrationHelper should not have burner_admin role"
        );

        // 4. Validate that there is no OHMv1 left in the Timelock or the MigrationHelper contract
        address timelock = addresses.getAddress("olympus-timelock");
        require(
            IERC20(OHMv1).balanceOf(timelock) == 0,
            "There should be no OHMv1 left in the Timelock"
        );
        require(
            IERC20(OHMv1).balanceOf(address(_migrationHelper)) == 0,
            "There should be no OHMv1 left in the MigrationHelper contract"
        );

        // 5. Validate that there is no tempOHM left in the Timelock or the MigrationHelper contract
        require(
            IERC20(_tempOHM).balanceOf(timelock) == 0,
            "There should be no tempOHM left in the Timelock"
        );
        require(
            IERC20(_tempOHM).balanceOf(address(_migrationHelper)) == 0,
            "There should be no tempOHM left in the MigrationHelper contract"
        );

        // 6. Validate that there is no gOHM left in the Timelock or the MigrationHelper contract
        require(
            IERC20(GOHM).balanceOf(timelock) == 0,
            "There should be no gOHM left in the Timelock"
        );
        require(
            IERC20(GOHM).balanceOf(address(_migrationHelper)) == 0,
            "There should be no gOHM left in the MigrationHelper contract"
        );

        // 7. Validate that there is no OHMv2 left in the Timelock or the MigrationHelper contract
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
