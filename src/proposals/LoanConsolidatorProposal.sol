// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

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
import {LoanConsolidator} from "src/policies/LoanConsolidator.sol";

// Script
import {ProposalScript} from "./ProposalScript.sol";

/// @notice Activates an updated LoanConsolidator policy.
contract LoanConsolidatorProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 4;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "LoanConsolidator and Contract Registry Activation";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# LoanConsolidator and Contract Registry Activation\n\n",
                "This proposal activates the LoanConsolidator policy and installs the Contract Registry module (and associated ContractRegistryAdmin configuration policy).\n\n",
                "The Contract Registry module is used to register commonly-used addresses that can be referenced by other contracts. These addresses are marked as either mutable or immutable.\n\n",
                "The previous version of LoanConsolidator contained logic that, combined with infinite approvals, enabled an attacker to steal funds from users of the CoolerUtils contract (as it was known at the time).\n\n",
                "This version introduces the following:\n\n",
                "- Strict checks on callers, ownership and Clearinghouse validity\n",
                "- Allows for migration of loans from one Clearinghouse to another (in preparation for a USDS Clearinghouse)\n",
                "- Allows for migration of loans from one owner to another\n\n",
                "[View the audit report here](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2024_10_LoanConsolidator_Audit.pdf)\n\n",
                "## Assumptions\n\n",
                "- The Contract Registry module has been deployed and activated as a module by the DAO MS.\n",
                "- The ContractRegistryAdmin policy has been deployed and activated as a policy by the DAO MS.\n",
                "- The mutable and immutable contract addresses required by LoanConsolidator have been registered in the Contract Registry.\n",
                "- The LoanConsolidator contract has been deployed and activated as a policy by the DAO MS.\n\n",
                "## Proposal Steps\n\n",
                "1. Grant the `loan_consolidator_admin` role to the OCG Timelock.\n",
                "2. Activate the LoanConsolidator."
            );
    }

    // No deploy actions needed
    function _deploy(Addresses addresses, address) internal override {
        // Cache the kernel address in state
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address timelock = addresses.getAddress("olympus-timelock");
        address loanConsolidator = addresses.getAddress("olympus-policy-loan-consolidator");

        // STEP 1: Grant the `loan_consolidator_admin` role to the OCG Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("loan_consolidator_admin"),
                timelock
            ),
            "Grant loan_consolidator_admin to Timelock"
        );

        // STEP 2: Activate the LoanConsolidator
        _pushAction(
            loanConsolidator,
            abi.encodeWithSelector(LoanConsolidator.activate.selector),
            "Activate LoanConsolidator"
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
        address timelock = addresses.getAddress("olympus-timelock");
        LoanConsolidator loanConsolidator = LoanConsolidator(
            addresses.getAddress("olympus-policy-loan-consolidator")
        );
        address emergencyMS = addresses.getAddress("olympus-multisig-emergency");

        // Validate that the emergency MS has the emergency shutdown role
        require(
            roles.hasRole(emergencyMS, bytes32("emergency_shutdown")),
            "Emergency MS does not have the emergency_shutdown role"
        );

        // Validate that the OCG timelock has the emergency shutdown role
        require(
            roles.hasRole(timelock, bytes32("emergency_shutdown")),
            "Timelock does not have the emergency_shutdown role"
        );

        // Validate that the OCG timelock has the loan_consolidator_admin role
        require(
            roles.hasRole(timelock, bytes32("loan_consolidator_admin")),
            "Timelock does not have the loan_consolidator_admin role"
        );

        // Validate that the OCG timelock has the contract_registry_admin role
        require(
            roles.hasRole(timelock, bytes32("contract_registry_admin")),
            "Timelock does not have the contract_registry_admin role"
        );

        // Validate that the LoanConsolidator is active
        require(loanConsolidator.consolidatorActive(), "LoanConsolidator is not active");
    }
}

contract LoanConsolidatorProposalScript is ProposalScript {
    constructor() ProposalScript(new LoanConsolidatorProposal()) {}
}
