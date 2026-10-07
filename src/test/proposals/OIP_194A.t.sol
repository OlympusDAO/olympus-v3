// SPDX-FileCopyrightText: Contributors to OlympusDAO
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ProposalTest} from "./ProposalTest.sol";

// OIP_194A imports
import {OIP_194A} from "src/proposals/OIP_194A.sol";

contract OIP194ATest is ProposalTest {
    function setUp() public virtual {
        // Mainnet Fork at a fixed block.
        // This block is after Cooler V2 infrastructure deployment and role wiring.
        vm.createSelectFork(_RPC_ALIAS, 24_876_700);

        /// @dev Deploy your proposal
        OIP_194A proposal = new OIP_194A();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = false;

        _setupSuite(address(proposal));
        _simulateProposal();
    }
}
