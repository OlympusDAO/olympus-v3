// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Proposal test-suite imports
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TestSuite} from "proposal-sim/test/TestSuite.t.sol";
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {GovernorBravoDelegator} from "src/external/governance/GovernorBravoDelegator.sol";
import {GovernorBravoDelegate} from "src/external/governance/GovernorBravoDelegate.sol";
import {Timelock} from "src/external/governance/Timelock.sol";

/// @notice Creates a sandboxed environment from a mainnet fork, to simulate the proposal.
/// @dev    Update the `setUp` function to deploy your proposal and set the submission
///         flag to `true` once the proposal has been submitted on-chain.
/// Note: this will fail if the OCGPermissions script has not been run yet.
abstract contract ProposalTest is Test {
    string public constant ADDRESSES_PATH = "./src/proposals/addresses.json";
    TestSuite public suite;
    Addresses public addresses;

    // Wether the proposal has been submitted or not.
    // If true, the framework will check that calldatas match.
    bool public hasBeenSubmitted;

    string RPC_URL = vm.envString("FORK_TEST_RPC_URL");

    /// @notice This function simulates the proposal with the given address.
    /// @dev    This function assumes the following:
    ///         - A mainnet fork has been created using `vm.createSelectFork` with a block number prior to the proposal deployment.
    ///         - If the proposal has been submitted on-chain, the `hasBeenSubmitted` flag has been set to `true`.
    ///         - The proposal contract has been deployed within the test contract and passed as an argument.
    ///
    /// @param  proposal_ The address of the proposal contract.
    function _simulateProposal(address proposal_) internal virtual {
        /// @notice This section is used to simulate the proposal on the mainnet fork.
        {
            // Populate addresses array
            address[] memory proposalsAddresses = new address[](1);
            proposalsAddresses[0] = address(proposal_);

            // Deploy TestSuite contract
            suite = new TestSuite(ADDRESSES_PATH, proposalsAddresses);

            // Set addresses object
            addresses = suite.addresses();

            // Set debug mode
            suite.setDebug(true);
            // Execute proposals
            suite.testProposals();

            // Proposals execution may change addresses, so we need to update the addresses object.
            addresses = suite.addresses();

            // Check if simulated calldatas match the ones from mainnet.
            if (hasBeenSubmitted) {
                address governor = addresses.getAddress("olympus-governor");
                bool[] memory matches = suite.checkProposalCalldatas(governor);
                for (uint256 i; i < matches.length; i++) {
                    assertTrue(matches[i], "Calldata should match");
                }
            } else {
                console2.log("\n\n------- Calldata check (simulation vs mainnet) -------\n");
                console2.log("Proposal has NOT been submitted on-chain yet.\n");
            }
        }
    }

    /// @dev Dummy test to ensure `setUp` is executed and the proposal simulated.
    function testProposal_simulate() public {
        assertTrue(true, "Proposal should be simulated");
    }
}
