// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";

// Proposal imports
import {LoanConsolidatorProposal} from "src/proposals/LoanConsolidatorProposal.sol";

contract LoanConsolidatorProposalTest is ProposalTest {
    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to the proposal deployment (otherwise it will fail)
        vm.createSelectFork(RPC_URL, 21070000);

        /// @dev Deploy your proposal
        LoanConsolidatorProposal proposal = new LoanConsolidatorProposal();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = false;

        // Simulate the proposal
        _simulateProposal(address(proposal));
    }
}
