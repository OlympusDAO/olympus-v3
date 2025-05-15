// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";

// OIP_168 imports
import {OIP_168} from "src/proposals/OIP_168.sol";

contract OIP168Test is ProposalTest {
    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to actual deployment of the proposal (otherwise it will fail) - 21218711
        vm.createSelectFork(RPC_URL, 21218711 - 1);

        /// @dev Deploy your proposal
        OIP_168 proposal = new OIP_168();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = true;

        // Simulate the proposal
        _setupSuite(address(proposal));
        _simulateProposal();
    }
}
