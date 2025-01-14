// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";

// EmissionManagerProposal imports
import {EmissionManagerProposal} from "src/proposals/EmissionManagerProposal.sol";

contract EmissionManagerProposalTest is ProposalTest {
    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to actual deployment of the proposal (otherwise it will fail) - 21224026
        vm.createSelectFork(RPC_URL, 21224026 - 1);

        /// @dev Deploy your proposal
        EmissionManagerProposal proposal = new EmissionManagerProposal();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = true;

        // Simulate the proposal
        _simulateProposal(address(proposal));
    }
}
