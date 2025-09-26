// SPDX-License-Identifier: UNLICENSED
// solhint-disable contract-name-camelcase
pragma solidity ^0.8.0;

// Proposal test-suite imports
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TestSuite} from "proposal-sim/test/TestSuite.t.sol";
import {Addresses} from "proposal-sim/addresses/Addresses.sol";

import {OIP_170} from "src/proposals/OIP_170.sol";

/// @notice Creates a sandboxed environment from a mainnet fork, to simulate the proposal.
/// @dev    Update the `setUp` function to deploy your proposal and set the submission
///         flag to `true` once the proposal has been submitted on-chain.
/// Note: this will fail if the OCGPermissions script has not been run yet.
contract OIP_170_OCGProposalTest is Test {
    string public constant ADDRESSES_PATH = "./src/proposals/addresses.json";
    TestSuite public suite;
    Addresses public addresses;

    // Wether the proposal has been submitted or not.
    // If true, the framework will check that calldatas match.
    bool public hasBeenSubmitted;

    /// @notice Creates a sandboxed environment from a mainnet fork.
    function setUp() public virtual {
        /// @dev Deploy your proposal
        OIP_170 proposal = new OIP_170();

        console2.log(proposal.description());

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = false;

        /// [DO NOT DELETE]
        /// @notice This section is used to simulate the proposal on the mainnet fork.
        {
            // Populate addresses array
            address[] memory proposalsAddresses = new address[](1);
            proposalsAddresses[0] = address(proposal);

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
                    assertTrue(matches[i]);
                }
            } else {
                console2.log("\n\n------- Calldata check (simulation vs mainnet) -------\n");
                console2.log("Proposal has NOT been submitted on-chain yet.\n");
            }
        }
    }

    // [DO NOT DELETE] Dummy test to ensure `setUp` is executed and the proposal simulated.
    function testProposal_simulate() public pure {
        assertTrue(true);
    }
}
