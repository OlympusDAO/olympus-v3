// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";

// ConvertibleDepositProposal imports
import {ConvertibleDepositProposal} from "src/proposals/ConvertibleDepositProposal.sol";

contract ConvertibleDepositProposalTest is ProposalTest {
    /// @dev Block the kernel installation batch was executed
    uint256 public constant BLOCK = 23831097;

    function setUp() public virtual {
        // Mainnet fork at a fixed block prior to proposal execution to ensure deterministic state
        // At this point:
        // - Contracts deployed
        // - Modules and policies installed in the Kernel
        vm.createSelectFork(_RPC_ALIAS, BLOCK + 1);

        // Deploy proposal under test
        ConvertibleDepositProposal proposal = new ConvertibleDepositProposal();

        // Set to true once the proposal has been submitted on-chain to enforce calldata matching
        hasBeenSubmitted = true;

        // Simulate the proposal
        _setupSuite(address(proposal));
        _simulateProposal();
    }
}
