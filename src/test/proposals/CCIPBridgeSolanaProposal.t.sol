// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";

// CCIPBridgeSolanaProposal imports
import {SolanaCCIPBridgeProposal} from "src/proposals/CCIPBridgeSolana.sol";

contract CCIPBridgeSolanaProposalTest is ProposalTest {
    uint256 public constant BLOCK = 22631178;

    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to actual deployment of the proposal (otherwise it will fail)
        vm.createSelectFork(RPC_URL, BLOCK);

        /// @dev Deploy your proposal
        SolanaCCIPBridgeProposal proposal = new SolanaCCIPBridgeProposal();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = true;

        _setupSuite(address(proposal));

        // Simulate the proposal
        _setupSuite(address(proposal));
        _simulateProposal();
    }
}
