// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
// solhint-disable contract-name-camelcase
pragma solidity ^0.8.15;
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";
// Olympus Kernel, Modules, and Policies
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

/// @notice OIP-168 migrates the reserve used in the Olympus protocol from DAI to USDS.
// solhint-disable-next-line contract-name-camelcase
contract OIP_168 is GovernorBravoProposal {
    Kernel internal _kernel;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 3;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "OIP-168: Migration of Reserves from DAI to USDS";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# OIP-168: Migrate the reserve token from DAI to USDS\n",
                "\n",
                "## Summary\n",
                "\n",
                "As Maker continues to reduce the DSR in favor of USDS, there is a tactical need to migrate a majority of Treasury Reserves from sDAI to sUSDS. Doing so will immediately create an additional 1% APY (sUSDS is currently 6.5% to sDAI's 5.5%) and failing to do so creates substantial missed opportunity cost.\n",
                "\n",
                "This OCG proposal will result in the following:\n",
                "- Activation of a new ReserveMigrator policy that will periodically migrate any DAI/sDAI in the Treasury to USDS/sUSDS\n",
                "- Activation of updated Clearinghouse, Heart, Operator and YieldRepurchaseFacility policies to support the new reserve token\n",
                "\n",
                "## Resources\n",
                "\n",
                "- Read the [forum proposal](https://forum.olympusdao.finance/d/4633-oip-168-olympus-treasury-migration-from-daisdai-to-usdssusds) for more context.\n",
                "- The new ReserveMigrator policy has also been audited. [Read the audit report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2024_11_EmissionManager_ReserveMigrator.pdf)\n",
                "- The code changes can be found in pull request [#18](https://github.com/OlympusDAO/olympus-v3/pull/18)\n",
                "\n",
                "## Roles to Assign\n",
                "\n",
                "1. `heart` to the new Heart policy (renamed from `operator_operate`)\n",
                "2. `reserve_migrator_admin` to the Timelock and DAO MS\n",
                "3. `callback_whitelist` to the new Operator policy\n",
                "4. `emergency_shutdown` to the DAO MS\n",
                "\n",
                "## Roles to Revoke\n",
                "\n",
                "1. `heart` from the old Heart policy\n",
                "2. `operator_operate` from the old Heart policy\n",
                "3. `callback_whitelist` from the old Operator policy\n",
                "\n",
                "## Follow-on Actions by DAO MS\n",
                "\n",
                "1. Deactivate old Operator, Clearinghouse, YRF, and Heart locally (i.e. on the contracts themselves)\n",
                "2. Deactivate old Operator, Clearinghouse, YRF, and Heart on the Kernel\n",
                "3. Activate new Operator, Clearinghouse, YRF, and Heart on the Kernel\n",
                "4. Configure BondCallback with new Operator and USDS/sUSDS\n",
                "5. Initialize new Operator, Clearinghouse, and YRF"
            );
    }

    // No deploy actions needed
    function _deploy(Addresses addresses, address) internal override {
        // Cache the kernel address in state
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // NOTE: In its current form, OCG is limited to admin roles when it refers to interactions with
    //       exsting policies and modules. Nevertheless, the DAO MS is still the Kernel executor.
    //       Because of that, OCG can't interact (un/install policies/modules) with the Kernel, yet.

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        // Load the roles admin contract
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");

        // Load variables
        address operator_1_4 = addresses.getAddress("olympus-policy-operator-1_4");
        address operator_1_5 = addresses.getAddress("olympus-policy-operator-1_5");
        address heart_1_5 = addresses.getAddress("olympus-policy-heart-1_5");
        address heart_1_6 = addresses.getAddress("olympus-policy-heart-1_6");
        address timelock = addresses.getAddress("olympus-timelock");
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        // STEP 1: Assign roles
        // 1a. Grant "heart" to the new Heart policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart"), heart_1_6),
            "Grant heart to new Heart policy"
        );

        // 1b. Grant "reserve_migrator_admin" to the Timelock and DAO MS
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("reserve_migrator_admin"),
                timelock
            ),
            "Grant reserve_migrator_admin to Timelock"
        );
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("reserve_migrator_admin"),
                daoMS
            ),
            "Grant reserve_migrator_admin to DAO MS"
        );

        // 1c. Grant "callback_whitelist" to the new Operator policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("callback_whitelist"),
                operator_1_5
            ),
            "Grant callback_whitelist to new Operator policy"
        );

        // 1d. Grant "emergency_shutdown" to the DAO MS
        // Missing from its permissions and needed to sunset existing Clearinghouse
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("emergency_shutdown"),
                daoMS
            ),
            "Grant emergency_shutdown to DAO MS"
        );

        // STEP 2: Revoke roles
        // 2a. Revoke "heart" from the old Heart policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.revokeRole.selector, bytes32("heart"), heart_1_5),
            "Revoke heart from old Heart policy"
        );

        // 2b. Revoke "operator_operate" from the old Heart policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("operator_operate"),
                heart_1_5
            ),
            "Revoke operator_operate from old Heart policy"
        );

        // 2c. Revoke "callback_whitelist" from the old Operator policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("callback_whitelist"),
                operator_1_4
            ),
            "Revoke callback_whitelist from old Operator policy"
        );
    }

    // Executes the proposal actions.
    function _run(Addresses addresses, address) internal override {
        // Simulates actions on TimelockController
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    // Validates the post-execution state.
    function _validate(Addresses addresses, address) internal view override {
        // Load the contract addresses
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address operator_1_4 = addresses.getAddress("olympus-policy-operator-1_4");
        address operator_1_5 = addresses.getAddress("olympus-policy-operator-1_5");
        address heart_1_5 = addresses.getAddress("olympus-policy-heart-1_5");
        address heart_1_6 = addresses.getAddress("olympus-policy-heart-1_6");
        // address clearinghouse = addresses.getAddress("olympus-policy-clearinghouse-1_2");

        // Validate the new Heart policy has the "heart" role
        require(
            roles.hasRole(heart_1_6, bytes32("heart")),
            "New Heart policy does not have the heart role"
        );

        // Validate the new Operator policy has the "callback_whitelist" role
        require(
            roles.hasRole(operator_1_5, bytes32("callback_whitelist")),
            "New Operator policy does not have the callback_whitelist role"
        );

        // Validate the old Heart policy does not have the "heart" role
        require(
            !roles.hasRole(heart_1_5, bytes32("heart")),
            "Old Heart policy still has the heart role"
        );

        // Validate the old Heart policy does not have the "operator_operate" role
        require(
            !roles.hasRole(heart_1_5, bytes32("operator_operate")),
            "Old Heart policy still has the operator_operate role"
        );

        // Validate the old Operator policy does not have the "callback_whitelist" role
        require(
            !roles.hasRole(operator_1_4, bytes32("callback_whitelist")),
            "Old Operator policy still has the callback_whitelist role"
        );
    }
}

// solhint-disable-next-line contract-name-camelcase
contract OIP_168ProposalScript is ProposalScript {
    constructor() ProposalScript(new OIP_168()) {}
}
