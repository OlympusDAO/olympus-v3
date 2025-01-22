// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";

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

        // Next steps:
        // - DAO MS needs to initialize the new EmissionManager policy
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
        // Validate that the Timelock has the "emissions_admin" role
        // Validate that the DAO MS has the "emissions_admin" role
        // Validate that the Timelock has the "cd_admin" role
        // Validate that the Heart has the "heart" role
        // Validate that the EmissionManager has the "cd_emissionmanager" role
        // Validate that the CDAuctioneer has the "cd_auctioneer" role
        // Validate that the old Heart policy is disabled
        // Validate that the old EmissionManager policy is disabled
        // Validate that the new Heart policy is active
        // Validate that the new EmissionManager policy is active
        // Validate that the new ConvertibleDepositAuctioneer policy is active
        // Validate that the new ConvertibleDepositFacility policy is active
    }
}
