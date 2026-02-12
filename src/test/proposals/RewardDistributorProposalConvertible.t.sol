// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";

import {RewardDistributorProposalConvertible} from "src/proposals/RewardDistributorProposalConvertible.sol";

contract RewardDistributorProposalConvertibleTest is ProposalTest {
    /// @dev Block after contracts are deployed and installed in the Kernel.
    ///      Update this once the contracts are deployed on mainnet.
    uint256 public constant BLOCK = 23831097;

    function setUp() public virtual {
        // Mainnet fork at a fixed block prior to proposal execution to ensure deterministic state
        vm.createSelectFork(_RPC_ALIAS, BLOCK + 1);

        // Deploy proposal under test
        RewardDistributorProposalConvertible proposal = new RewardDistributorProposalConvertible();

        // Set to true once the proposal has been submitted on-chain to enforce calldata matching
        hasBeenSubmitted = false;

        // Simulate the proposal
        _setupSuite(address(proposal));
        _simulateProposal();
    }
}
