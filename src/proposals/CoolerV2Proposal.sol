// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Olympus Kernel, Modules, and Policies
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";

// Script
import {ProposalScript} from "./ProposalScript.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Activates Cooler V2.
// solhint-disable gas-custom-errors
contract CoolerV2Proposal is GovernorBravoProposal {
    Kernel internal _kernel;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 8;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "Cooler V2 Activation";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return string.concat("TODO");
    }

    // No deploy actions needed
    function _deploy(Addresses addresses, address) internal override {
        // Cache the kernel address in state
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address timelock = addresses.getAddress("olympus-timelock");
        address emergencyMS = addresses.getAddress("olympus-multisig-emergency");
        address coolerV2 = addresses.getAddress("olympus-policy-cooler-v2");
        address coolerV2TreasuryBorrower = addresses.getAddress(
            "olympus-policy-cooler-v2-treasury-borrower"
        );

        // STEP 1: Grant the "admin" role to the OCG Timelock, if needed
        if (!roles.hasRole(timelock, bytes32("admin"))) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("admin"), timelock),
                "Grant admin to Timelock"
            );
        } else {
            console2.log("Timelock already has the admin role");
        }

        // STEP 2: Grant the "emergency" role, if needed
        if (!roles.hasRole(emergencyMS, bytes32("emergency"))) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("emergency"),
                    emergencyMS
                ),
                "Grant emergency to Emergency MS"
            );
        } else {
            console2.log("Emergency MS already has the emergency role");
        }

        if (!roles.hasRole(timelock, bytes32("emergency"))) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("emergency"),
                    timelock
                ),
                "Grant emergency to Timelock"
            );
        } else {
            console2.log("Timelock already has the emergency role");
        }

        // STEP 3: Grant the "treasuryborrower_cooler" role to the MonoCooler policy
        if (!roles.hasRole(coolerV2, bytes32("treasuryborrower_cooler"))) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("treasuryborrower_cooler"),
                    coolerV2
                ),
                "Grant treasuryborrower_cooler to MonoCooler"
            );
        } else {
            console2.log("MonoCooler already has the treasuryborrower_cooler role");
        }

        // Cooler V2 MonoCooler policy does not needed to be enabled
        // Will not function until the treasury borrower policy is enabled

        // STEP 4: Enable the Cooler V2 Treasury Borrower policy
        _pushAction(
            coolerV2TreasuryBorrower,
            abi.encodeWithSelector(PolicyEnabler.enable.selector, abi.encode("")),
            "Enable Cooler V2 Treasury Borrower"
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
        address emergencyMS = addresses.getAddress("olympus-multisig-emergency");
        address coolerV2 = addresses.getAddress("olympus-policy-cooler-v2");
        address coolerV2TreasuryBorrower = addresses.getAddress(
            "olympus-policy-cooler-v2-treasury-borrower"
        );

        // Validate that the emergency MS has the emergency role
        require(
            roles.hasRole(emergencyMS, bytes32("emergency")),
            "Emergency MS does not have the emergency role"
        );

        // Validate that the OCG timelock has the emergency role
        require(
            roles.hasRole(timelock, bytes32("emergency")),
            "Timelock does not have the emergency role"
        );

        // Validate that the OCG timelock has the admin role
        require(roles.hasRole(timelock, bytes32("admin")), "Timelock does not have the admin role");

        // Validate that the Cooler V2 policy is enabled
        require(IMonoCooler(coolerV2).liquidationsPaused() == false, "Cooler V2 is not enabled");
        require(IMonoCooler(coolerV2).borrowsPaused() == false, "Cooler V2 is not enabled");

        // Validate that the Cooler V2 Treasury Borrower policy is enabled
        require(
            PolicyEnabler(coolerV2TreasuryBorrower).isEnabled(),
            "Cooler V2 Treasury Borrower is not enabled"
        );
    }
}

contract CoolerV2ProposalScript is ProposalScript {
    constructor() ProposalScript(new CoolerV2Proposal()) {}
}
