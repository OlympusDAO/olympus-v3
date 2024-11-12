// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Proposal test-suite imports
import "forge-std/Test.sol";
import {TestSuite} from "proposal-sim/test/TestSuite.t.sol";
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {GovernorBravoDelegator} from "src/external/governance/GovernorBravoDelegator.sol";
import {GovernorBravoDelegate} from "src/external/governance/GovernorBravoDelegate.sol";
import {Timelock} from "src/external/governance/Timelock.sol";

// OIP_166 imports
import {OIP_166} from "proposals/OIP_166.sol";

/// @notice Creates a sandboxed environment from a mainnet fork, to simulate the proposal.
/// @dev    Update the `setUp` function to deploy your proposal and set the submission
///         flag to `true` once the proposal has been submitted on-chain.
/// Note: this will fail if the OCGPermissions script has not been run yet.
contract OIP_166_OCGProposalTest is Test {
    string public constant ADDRESSES_PATH = "./src/proposals/addresses.json";
    TestSuite public suite;
    Addresses public addresses;

    // Wether the proposal has been submitted or not.
    // If true, the framework will check that calldatas match.
    bool public hasBeenSubmitted;

    string RPC_URL = vm.envString("FORK_TEST_RPC_URL");

    /// @notice Creates a sandboxed environment from a mainnet fork.
    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to actual deployment of the proposal (otherwise it will fail) - 20872023
        vm.createSelectFork(RPC_URL, 20872022);

        /// @dev Deploy your proposal
        OIP_166 proposal = new OIP_166();

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

            // NOTE: unique to OIP 166
            // In prepation for this particular proposal, we need to:
            // Push the roles admin "admin" permission to the Timelock from the DAO MS (multisig)
            address daoMS = addresses.getAddress("olympus-multisig-dao");
            address timelock = addresses.getAddress("olympus-timelock");
            RolesAdmin rolesAdmin = RolesAdmin(addresses.getAddress("olympus-policy-roles-admin"));

            vm.prank(daoMS);
            rolesAdmin.pushNewAdmin(timelock);

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
                console.log("\n\n------- Calldata check (simulation vs mainnet) -------\n");
                console.log("Proposal has NOT been submitted on-chain yet.\n");
            }
        }
    }

    // [DO NOT DELETE] Dummy test to ensure `setUp` is executed and the proposal simulated.
    function testProposal_simulate() public {
        assertTrue(true);
    }
}
