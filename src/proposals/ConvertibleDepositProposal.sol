// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/roles/ROLESv1.sol";

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
        return "";
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

        address heartOld = addresses.getAddress("olympus-policy-heart-1_6");
        address heartNew = addresses.getAddress("olympus-policy-heart-1_7");
        address emissionManagerOld = addresses.getAddress("olympus-policy-emissionmanager");
        address emissionManagerNew = addresses.getAddress("olympus-policy-emissionmanager-1_2");
        address cdAuctioneer = addresses.getAddress(
            "olympus-policy-convertible-deposit-auctioneer"
        );
        address cdFacility = addresses.getAddress("olympus-policy-convertible-deposit-facility");

        // Revoke the "heart" role from the old Heart policy

        // Disable the old Heart policy

        // Disable the old EmissionManager policy

        // Grant the "cd_admin" role to the Timelock

        // Grant the "emissions_admin" role to the Timelock

        // Grant the "emissions_admin" role to the DAO MS

        // Grant the "heart" role to the Heart policy

        // Grant the "cd_emissionmanager" role to the EmissionManager to call CDAuctioneer

        // Grant the "cd_auctioneer" role to the CDAuctioneer policy to call CDFacility

        // Activate the ConvertibleDepositFacility policy

        // Activate the ConvertibleDepositAuctioneer policy

        // Activate the EmissionManager policy

        // Activate the Heart policy

        // Activate the ConvertibleDepositFacility contract functionality

        // TODO can we initialize the CDAuctioneer and EmissionManager policies here?

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
        require(
            heartOld.isActive() == false,
            "Old Heart policy is still active"
        );

        // Validate that the old EmissionManager policy is disabled
        require(
            emissionManagerOld.isActive() == false,
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
        require(
            heart.isActive() == true,
            "Heart policy is not active"
        );

        // Validate that the new EmissionManager policy is active
        require(
            emissionManager.isActive() == true,
            "EmissionManager policy is not active"
        );

        // Validate that the new ConvertibleDepositAuctioneer policy is active
        require(
            cdAuctioneer.isActive() == true,
            "CDAuctioneer policy is not active"
        );

        // Validate that the new ConvertibleDepositFacility policy is active
        require(
            cdFacility.isActive() == true,
            "CDFacility policy is not active"
        );

        // Validate that the new ConvertibleDepositFacility policy is locally active
        require(
            cdFacility.locallyActive() == true,
            "CDFacility policy is not locally active"
        );
    }
}

// solhint-disable-next-line contract-name-camelcase
contract ConvertibleDepositProposalScript is ProposalScript {
    constructor() ProposalScript(new ConvertibleDepositProposal()) {}
}
