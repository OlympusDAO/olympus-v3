// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {TestSuite} from "proposal-sim/test/TestSuite.t.sol";
import {console2} from "forge-std/console2.sol";

import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {ContractRegistryAdmin} from "src/policies/ContractRegistryAdmin.sol";

import {ContractRegistryProposal} from "src/proposals/ContractRegistryProposal.sol";

contract ContractRegistryProposalTest is ProposalTest {
    Kernel public kernel;

    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to the proposal deployment (otherwise it will fail)
        // 21371770 is the deployment block for ContractRegistryAdmin
        vm.createSelectFork(RPC_URL, 21371770);

        /// @dev Deploy your proposal
        ContractRegistryProposal proposal = new ContractRegistryProposal();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = false;

        // Populate addresses array
        {
            // Populate addresses array
            address[] memory proposalsAddresses = new address[](1);
            proposalsAddresses[0] = address(proposal);

            // Deploy TestSuite contract
            suite = new TestSuite(ADDRESSES_PATH, proposalsAddresses);

            // Set addresses object
            addresses = suite.addresses();

            kernel = Kernel(addresses.getAddress("olympus-kernel"));
        }

        // Simulate the ContractRegistryInstall batch script having been run
        // The simulation will revert otherwise
        // Install RGSTY
        {
            address rgsty = addresses.getAddress("olympus-module-rgsty");

            if (address(kernel.getModuleForKeycode(toKeycode("RGSTY"))) == address(0)) {
                console2.log("Installing RGSTY");

                vm.prank(addresses.getAddress("olympus-multisig-dao"));
                kernel.executeAction(Actions.InstallModule, rgsty);
            }
        }

        // Install ContractRegistryAdmin
        {
            address contractRegistryAdmin = addresses.getAddress(
                "olympus-policy-contract-registry-admin"
            );

            if (!ContractRegistryAdmin(contractRegistryAdmin).isActive()) {
                console2.log("Activating ContractRegistryAdmin");

                vm.prank(addresses.getAddress("olympus-multisig-dao"));
                kernel.executeAction(Actions.ActivatePolicy, contractRegistryAdmin);
            }
        }

        // Simulate the proposal
        _simulateProposal(address(proposal));
    }
}
