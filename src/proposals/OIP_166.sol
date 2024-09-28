// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import {console2} from "forge-std/console2.sol";

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";
// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
// Olympus Kernel, Modules, and Policies
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {GovernorBravoDelegate} from "src/external/governance/GovernorBravoDelegate.sol";

// OIP_166 is the first step in activating Olympus Onchain Governance.
contract OIP_166 is GovernorBravoProposal {
    Kernel internal _kernel;

    // Returns the id of the proposal.
    function id() public view override returns (uint256) {
        return 0; // TODO: ?
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "OIP-166";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return "OIP-166: Transition to OCG, Step 1";
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
        address timelock = addresses.getAddress("olympus-timelock");
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address governor = addresses.getAddress("olympus-governor");

        // STEP 1: Set the DAO MS as the veto guardian on the Governor
        _pushAction(
            governor,
            abi.encodeWithSelector(GovernorBravoDelegate._setVetoGuardian.selector, daoMS),
            "Set the DAO MS as the veto guardian on the Governor"
        );

        // STEP 2: Pull the admin role on the RolesAdmin contract
        _pushAction(
            rolesAdmin,
            abi.encodeWithSignature("pullNewAdmin()"),
            "Accept admin role on RolesAdmin"
        );

        // STEP 3: Grant roles to the Timelock (itself) for administration of the protocol
        // "cooler_overseer", (already has)
        // "emergency_shutdown", (already has)
        // "emergency_admin", (already has)
        // "operator_admin",
        // "callback_admin",
        // "price_admin",
        // "custodian",
        // "emergency_restart",
        // "bridge_admin",
        // "heart_admin",
        // "operator_policy",
        // "loop_daddy"

        // 3.a. Grant "operator_admin" to Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("operator_admin"),
                timelock
            ),
            "Grant operator_admin to Timelock"
        );

        // 3.b. Grant "callback_admin" to Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("callback_admin"),
                timelock
            ),
            "Grant callback_admin to Timelock"
        );

        // 3.c. Grant "price_admin" to Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("price_admin"), timelock),
            "Grant price_admin to Timelock"
        );

        // 3.d. Grant "custodian" to Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("custodian"), timelock),
            "Grant custodian to Timelock"
        );

        // 3.e. Grant "emergency_restart" to Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("emergency_restart"),
                timelock
            ),
            "Grant emergency_restart to Timelock"
        );

        // 3.f. Grant "bridge_admin" to Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("bridge_admin"),
                timelock
            ),
            "Grant bridge_admin to Timelock"
        );

        // 3.g. Grant "heart_admin" to Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart_admin"), timelock),
            "Grant heart_admin to Timelock"
        );

        // 3.h. Grant "operator_policy" to Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("operator_policy"),
                timelock
            ),
            "Grant operator_policy to Timelock"
        );

        // 3.i. Grant "loop_daddy" to Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("loop_daddy"), timelock),
            "Grant loop_daddy to Timelock"
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
    function _validate(Addresses addresses, address) internal override {
        // Load the contract addresses
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        RolesAdmin rolesAdmin = RolesAdmin(addresses.getAddress("olympus-policy-roles-admin"));
        address timelock = addresses.getAddress("olympus-timelock");
        GovernorBravoDelegate governor = GovernorBravoDelegate(
            addresses.getAddress("olympus-governor")
        );
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        // Validate DAO MS is the veto guardian on the Governor
        require(
            governor.vetoGuardian() == daoMS,
            "DAO MS is not the veto guardian on the Governor"
        );

        // Validate Timelock is the admin on the RolesAdmin contract
        require(
            rolesAdmin.admin() == timelock,
            "Timelock is not the admin on the RolesAdmin contract"
        );

        // Validate Timelock has the "operator_admin" role
        require(
            roles.hasRole(timelock, bytes32("operator_admin")),
            "Timelock does not have the operator_admin role"
        );

        // Validate Timelock has the "callback_admin" role
        require(
            roles.hasRole(timelock, bytes32("callback_admin")),
            "Timelock does not have the callback_admin role"
        );

        // Validate Timelock has the "price_admin" role
        require(
            roles.hasRole(timelock, bytes32("price_admin")),
            "Timelock does not have the price_admin role"
        );

        // Validate Timelock has the "custodian" role
        require(
            roles.hasRole(timelock, bytes32("custodian")),
            "Timelock does not have the custodian role"
        );

        // Validate Timelock has the "emergency_restart" role
        require(
            roles.hasRole(timelock, bytes32("emergency_restart")),
            "Timelock does not have the emergency_restart role"
        );

        // Validate Timelock has the "bridge_admin" role
        require(
            roles.hasRole(timelock, bytes32("bridge_admin")),
            "Timelock does not have the bridge_admin role"
        );

        // Validate Timelock has the "heart_admin" role
        require(
            roles.hasRole(timelock, bytes32("heart_admin")),
            "Timelock does not have the heart_admin role"
        );

        // Validate Timelock has the "operator_policy" role
        require(
            roles.hasRole(timelock, bytes32("operator_policy")),
            "Timelock does not have the operator_policy role"
        );

        // Validate Timelock has the "loop_daddy" role
        require(
            roles.hasRole(timelock, bytes32("loop_daddy")),
            "Timelock does not have the loop_daddy role"
        );
    }
}
