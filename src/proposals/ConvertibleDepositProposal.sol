// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Contracts
import {Kernel, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {CDFacility} from "src/policies/CDFacility.sol";

/// @notice Activates the Convertible Deposit contracts
contract ConvertibleDepositProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    function id() public pure override returns (uint256) {
        return 8;
    }

    function name() public pure override returns (string memory) {
        return "Convertible Deposit Activation";
    }

    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Activation of Convertible Deposit Facility\n",
                "\n",
                "This proposal activates contracts related to enabling the Convertible Deposit system.\n",
                "\n",
                "## Summary\n",
                "\n",
                "The Convertible Deposit system provides a mechanism for the protocol to operate an auction that is infinite duration and infinite capacity. Bidders are required to deposit the configured reserve token into the auctioneer (`CDAuctioneer`), and in return they receive a convertible deposit token (`CDEPO`) that can be converted into the configured bid token (OHM) or redeemed for the deposited reserve token.\n",
                "\n",
                "## Affected Contracts\n",
                "\n",
                "- Heart policy (v1.7)\n",
                "- EmissionManager policy (v1.2)\n",
                "- CDFacility policy (v1.0)\n",
                "- CDAuctioneer policy (v1.0)\n",
                "\n",
                "## Resources\n",
                "\n",
                "- [View the audit report](TODO)\n", // TODO: Add audit report
                "- [View the pull request](https://github.com/OlympusDAO/olympus-v3/pull/29)\n",
                "\n",
                "## Pre-requisites\n",
                "\n",
                "- Old Heart policy has been deactivated in the kernel\n",
                "- Old EmissionManager policy has been deactivated in the kernel\n",
                "- Heart policy has been activated in the kernel\n",
                "- EmissionManager policy has been activated in the kernel\n",
                "- ConvertibleDepositFacility policy has been activated in the kernel\n",
                "- ConvertibleDepositAuctioneer policy has been activated in the kernel\n",
                "- CDEPO module has been installed in the kernel\n",
                "- CDPOS module has been installed in the kernel\n",
                "\n",
                "## Proposal Steps\n",
                "\n",
                "1. Revoke the `heart` role from the old Heart policy\n",
                "2. Grant the `cd_admin` role to the Timelock\n",
                "3. Grant the `cd_admin` role to the DAO MS\n",
                "4. Grant the `emissions_admin` role to the Timelock\n",
                "5. Grant the `emissions_admin` role to the DAO MS\n",
                "6. Grant the `heart` role to the new Heart policy\n",
                "7. Grant the `cd_emissionmanager` role to the new EmissionManager\n",
                "8. Grant the `cd_auctioneer` role to the CDAuctioneer\n",
                "9. Activate the ConvertibleDepositFacility contract functionality\n",
                "\n",
                "## Subsequent Steps\n",
                "\n",
                "The functionality of the EmissionManager and CDAuctioneer policies will be initialized by the DAO MS, since the inputs are time-sensitive.\n",
                "\n",
                "1. Initialize the new EmissionManager policy\n",
                "2. Initialize the CDAuctioneer policy\n"
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
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        address heartOld = addresses.getAddress("olympus-policy-heart-1_6");
        address heart = addresses.getAddress("olympus-policy-heart-1_7");
        address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");
        address cdAuctioneer = addresses.getAddress(
            "olympus-policy-convertible-deposit-auctioneer"
        );
        address cdFacility = addresses.getAddress("olympus-policy-convertible-deposit-facility");

        // Pre-requisites
        // - Old Heart policy has been deactivated in the kernel
        // - Old EmissionManager policy has been deactivated in the kernel
        // - Heart policy has been activated in the kernel
        // - EmissionManager policy has been activated in the kernel
        // - ConvertibleDepositFacility policy has been activated in the kernel
        // - ConvertibleDepositAuctioneer policy has been activated in the kernel
        // - CDEPO module has been installed in the kernel
        // - CDPOS module has been installed in the kernel

        // Revoke the "heart" role from the old Heart policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.revokeRole.selector, bytes32("heart"), heartOld),
            "Revoke heart role from old Heart policy"
        );

        // Grant the "cd_admin" role to the Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("cd_admin"), timelock),
            "Grant cd_admin to Timelock"
        );

        // Grant the "cd_admin" role to the DAO MS
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("cd_admin"), daoMS),
            "Grant cd_admin to DAO MS"
        );

        // Grant the "emissions_admin" role to the Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("emissions_admin"),
                timelock
            ),
            "Grant emissions_admin to Timelock"
        );

        // Grant the "emissions_admin" role to the DAO MS
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("emissions_admin"),
                daoMS
            ),
            "Grant emissions_admin to DAO MS"
        );

        // Grant the "heart" role to the Heart policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart"), heart),
            "Grant heart role to new Heart policy"
        );

        // Grant the "cd_emissionmanager" role to the EmissionManager to call CDAuctioneer
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("cd_emissionmanager"),
                emissionManager
            ),
            "Grant cd_emissionmanager role to EmissionManager"
        );

        // Grant the "cd_auctioneer" role to the CDAuctioneer policy to call CDFacility
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("cd_auctioneer"),
                cdAuctioneer
            ),
            "Grant cd_auctioneer role to CDAuctioneer"
        );

        // Activate the ConvertibleDepositFacility contract functionality
        _pushAction(
            cdFacility,
            abi.encodeWithSelector(CDFacility.activate.selector),
            "Activate ConvertibleDepositFacility"
        );

        // Next steps:
        // - DAO MS needs to initialize the new EmissionManager policy
        // - DAO MS needs to initialize the new CDAuctioneer policy
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
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        address heartOld = addresses.getAddress("olympus-policy-heart-1_6");
        address heart = addresses.getAddress("olympus-policy-heart-1_7");
        address emissionManagerOld = addresses.getAddress("olympus-policy-emissionmanager");
        address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");
        address cdAuctioneer = addresses.getAddress(
            "olympus-policy-convertible-deposit-auctioneer"
        );
        address cdFacility = addresses.getAddress("olympus-policy-convertible-deposit-facility");

        // solhint-disable custom-errors

        // Validate cleanup
        // Validate that the old Heart policy is disabled
        require(Policy(heartOld).isActive() == false, "Old Heart policy is still active");

        // Validate that the old EmissionManager policy is disabled
        require(
            Policy(emissionManagerOld).isActive() == false,
            "Old EmissionManager policy is still active"
        );

        // Validate that the "heart" role is revoked from the old Heart policy
        require(
            roles.hasRole(heartOld, bytes32("heart")) == false,
            "Old Heart policy still has the heart role"
        );

        // Validate that the Timelock has the "emissions_admin" role
        require(
            roles.hasRole(timelock, bytes32("emissions_admin")) == true,
            "Timelock does not have the emissions_admin role"
        );

        // Validate that the DAO MS has the "emissions_admin" role
        require(
            roles.hasRole(daoMS, bytes32("emissions_admin")) == true,
            "DAO MS does not have the emissions_admin role"
        );

        // Validate that the Timelock has the "cd_admin" role
        require(
            roles.hasRole(timelock, bytes32("cd_admin")),
            "Timelock does not have the cd_admin role"
        );

        // Validate that the DAO MS has the "cd_admin" role
        require(
            roles.hasRole(daoMS, bytes32("cd_admin")),
            "DAO MS does not have the cd_admin role"
        );

        // Validate that the new Heart has the "heart" role
        require(
            roles.hasRole(heart, bytes32("heart")) == true,
            "Heart policy does not have the heart role"
        );

        // Validate that the EmissionManager has the "cd_emissionmanager" role
        require(
            roles.hasRole(emissionManager, bytes32("cd_emissionmanager")) == true,
            "EmissionManager policy does not have the cd_emissionmanager role"
        );

        // Validate that the CDAuctioneer has the "cd_auctioneer" role
        require(
            roles.hasRole(cdAuctioneer, bytes32("cd_auctioneer")) == true,
            "CDAuctioneer policy does not have the cd_auctioneer role"
        );

        // Validate that the new Heart policy is active
        require(Policy(heart).isActive() == true, "Heart policy is not active");

        // Validate that the new EmissionManager policy is active
        require(Policy(emissionManager).isActive() == true, "EmissionManager policy is not active");

        // Validate that the new ConvertibleDepositAuctioneer policy is active
        require(Policy(cdAuctioneer).isActive() == true, "CDAuctioneer policy is not active");

        // Validate that the new ConvertibleDepositFacility policy is active
        require(Policy(cdFacility).isActive() == true, "CDFacility policy is not active");

        // Validate that the new ConvertibleDepositFacility policy is locally active
        require(
            CDFacility(cdFacility).locallyActive() == true,
            "CDFacility policy is not locally active"
        );
    }
}

// solhint-disable-next-line contract-name-camelcase
contract ConvertibleDepositProposalScript is ProposalScript {
    constructor() ProposalScript(new ConvertibleDepositProposal()) {}
}
