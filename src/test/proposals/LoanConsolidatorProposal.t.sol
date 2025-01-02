// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {TestSuite} from "proposal-sim/test/TestSuite.t.sol";
import {console2} from "forge-std/console2.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {LoanConsolidator} from "src/policies/LoanConsolidator.sol";

// Proposal imports
import {LoanConsolidatorProposal} from "src/proposals/LoanConsolidatorProposal.sol";

contract LoanConsolidatorProposalTest is ProposalTest {
    Kernel public kernel;

    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to the proposal deployment (otherwise it will fail)
        vm.createSelectFork(RPC_URL, 21501128 + 1);

        /// @dev Deploy your proposal
        LoanConsolidatorProposal proposal = new LoanConsolidatorProposal();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = true;

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

        // Simulate the LoanConsolidatorInstall batch script having been run
        // The simulation will revert otherwise
        // This proposal will also fail until the RGSTY proposal has been executed
        // Install LoanConsolidator
        {
            address loanConsolidator = addresses.getAddress("olympus-policy-loan-consolidator");

            if (!LoanConsolidator(loanConsolidator).isActive()) {
                console2.log("Activating LoanConsolidator");

                vm.prank(addresses.getAddress("olympus-multisig-dao"));
                kernel.executeAction(Actions.ActivatePolicy, loanConsolidator);
            }
        }

        // Simulate the proposal
        _simulateProposal(address(proposal));
    }
}
