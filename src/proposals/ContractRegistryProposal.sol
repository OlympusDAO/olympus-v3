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
import {ContractRegistryAdmin} from "src/policies/ContractRegistryAdmin.sol";
import {RGSTYv1} from "src/modules/RGSTY/RGSTY.v1.sol";

// Script
import {ProposalScript} from "./ProposalScript.sol";

/// @notice Activates the contract registry module and associated configuration policy.
contract ContractRegistryProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    // Immutable contract addresses
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address public constant GOHM = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;
    address public constant OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;

    // Mutable contract addresses
    address public constant FLASH_LENDER = 0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA;
    address public constant DAI_USDS_MIGRATOR = 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 6;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "Contract Registry Activation";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Contract Registry Activation\n",
                "\n",
                "This proposal activates the RGSTY module (and associated ContractRegistryAdmin configuration policy).\n",
                "\n",
                "The RGSTY module is used to register commonly-used addresses that can be referenced by other contracts. These addresses are marked as either mutable or immutable.\n",
                "\n",
                "The ContractRegistryAdmin policy is used to manage the addresses registered in the RGSTY module.\n",
                "\n",
                "The RGSTY module will be used by the LoanConsolidator policy to lookup contract addresses. In order to roll-out the improved LoanConsolidator, this proposal must be executed first.\n",
                "\n",
                "## Resources\n",
                "\n",
                "- [View the audit report here](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2024_10_LoanConsolidator_Audit.pdf)\n",
                "- [View the pull request here](https://github.com/OlympusDAO/olympus-v3/pull/19)\n",
                "\n",
                "## Assumptions\n",
                "\n",
                "- The RGSTY module has been deployed and activated as a module by the DAO MS.\n",
                "- The ContractRegistryAdmin policy has been deployed and activated as a policy by the DAO MS.\n",
                "\n",
                "## Proposal Steps\n",
                "\n",
                "1. Grant the `contract_registry_admin` role to the OCG Timelock.\n",
                "2. Register immutable addresses for DAI, SDAI, USDS, SUSDS, GOHM and OHM.\n",
                "3. Register mutable addresses for the Flash Lender and DAI-USDS Migrator contracts.\n"
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
        address contractRegistryAdmin = addresses.getAddress(
            "olympus-policy-contract-registry-admin"
        );

        // STEP 1: Grant the `contract_registry_admin` role to the OCG Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("contract_registry_admin"),
                timelock
            ),
            "Grant contract_registry_admin to Timelock"
        );

        // STEP 2: Register immutable addresses for DAI, SDAI, USDS, SUSDS, GOHM and OHM
        _pushAction(
            contractRegistryAdmin,
            abi.encodeWithSelector(
                ContractRegistryAdmin.registerImmutableContract.selector,
                bytes5("dai"),
                DAI
            ),
            "Register immutable DAI address"
        );
        _pushAction(
            contractRegistryAdmin,
            abi.encodeWithSelector(
                ContractRegistryAdmin.registerImmutableContract.selector,
                bytes5("sdai"),
                SDAI
            ),
            "Register immutable SDAI address"
        );
        _pushAction(
            contractRegistryAdmin,
            abi.encodeWithSelector(
                ContractRegistryAdmin.registerImmutableContract.selector,
                bytes5("usds"),
                USDS
            ),
            "Register immutable USDS address"
        );
        _pushAction(
            contractRegistryAdmin,
            abi.encodeWithSelector(
                ContractRegistryAdmin.registerImmutableContract.selector,
                bytes5("susds"),
                SUSDS
            ),
            "Register immutable SUSDS address"
        );
        _pushAction(
            contractRegistryAdmin,
            abi.encodeWithSelector(
                ContractRegistryAdmin.registerImmutableContract.selector,
                bytes5("gohm"),
                GOHM
            ),
            "Register immutable GOHM address"
        );
        _pushAction(
            contractRegistryAdmin,
            abi.encodeWithSelector(
                ContractRegistryAdmin.registerImmutableContract.selector,
                bytes5("ohm"),
                OHM
            ),
            "Register immutable OHM address"
        );

        // STEP 3: Register mutable addresses for the Flash Lender and DAI-USDS Migrator contracts
        _pushAction(
            contractRegistryAdmin,
            abi.encodeWithSelector(
                ContractRegistryAdmin.registerContract.selector,
                bytes5("flash"),
                FLASH_LENDER
            ),
            "Register mutable Flash Lender address"
        );
        _pushAction(
            contractRegistryAdmin,
            abi.encodeWithSelector(
                ContractRegistryAdmin.registerContract.selector,
                bytes5("dmgtr"),
                DAI_USDS_MIGRATOR
            ),
            "Register mutable DAI-USDS Migrator address"
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
        address rgsty = addresses.getAddress("olympus-module-rgsty");
        RGSTYv1 RGSTY = RGSTYv1(rgsty);

        // Validate that the OCG timelock has the contract_registry_admin role
        require(
            roles.hasRole(timelock, bytes32("contract_registry_admin")),
            "Timelock does not have the contract_registry_admin role"
        );

        // Validate that the DAI, SDAI, USDS, SUSDS, GOHM and OHM addresses are registered and immutable
        require(RGSTY.getImmutableContract("dai") == DAI, "DAI address is not immutable");
        require(RGSTY.getImmutableContract("sdai") == SDAI, "SDAI address is not immutable");
        require(RGSTY.getImmutableContract("usds") == USDS, "USDS address is not immutable");
        require(RGSTY.getImmutableContract("susds") == SUSDS, "SUSDS address is not immutable");
        require(RGSTY.getImmutableContract("gohm") == GOHM, "GOHM address is not immutable");
        require(RGSTY.getImmutableContract("ohm") == OHM, "OHM address is not immutable");

        // Validate that the Flash Lender and DAI-USDS Migrator addresses are registered and mutable
        require(RGSTY.getContract("flash") == FLASH_LENDER, "Flash Lender address is not mutable");
        require(
            RGSTY.getContract("dmgtr") == DAI_USDS_MIGRATOR,
            "DAI-USDS Migrator address is not mutable"
        );
    }
}

contract ContractRegistryProposalScript is ProposalScript {
    constructor() ProposalScript(new ContractRegistryProposal()) {}
}
