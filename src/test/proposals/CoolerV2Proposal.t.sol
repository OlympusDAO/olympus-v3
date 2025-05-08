// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";

// CoolerV2Proposal imports
import {CoolerV2Proposal} from "src/proposals/CoolerV2Proposal.sol";

contract CoolerV2ProposalTest is ProposalTest {
    uint48 public constant TREASURY_BORROWER_BLOCK = 22430380;

    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to actual deployment of the proposal (otherwise it will fail)
        vm.createSelectFork(RPC_URL, TREASURY_BORROWER_BLOCK + 1);

        /// @dev Deploy your proposal
        CoolerV2Proposal proposal = new CoolerV2Proposal();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = false;

        // Simulate the proposal
        _simulateProposal(address(proposal));
    }
}
