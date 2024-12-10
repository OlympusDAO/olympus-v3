// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {TestSuite} from "proposal-sim/test/TestSuite.t.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

// OIP_166 imports
import {OIP_166} from "src/proposals/OIP_166.sol";

contract OIP166Test is ProposalTest {
    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to actual deployment of the proposal (otherwise it will fail) - 20872023
        vm.createSelectFork(RPC_URL, 20872023 - 1);

        /// @dev Deploy your proposal
        OIP_166 proposal = new OIP_166();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = true;

        // NOTE: unique to OIP 166
        // In prepation for this particular proposal, we need to:
        // Push the roles admin "admin" permission to the Timelock from the DAO MS (multisig)
        {
            // Populate addresses array
            address[] memory proposalsAddresses = new address[](1);
            proposalsAddresses[0] = address(proposal);

            // Deploy TestSuite contract
            suite = new TestSuite(ADDRESSES_PATH, proposalsAddresses);

            // Set addresses object
            addresses = suite.addresses();

            address daoMS = addresses.getAddress("olympus-multisig-dao");
            address timelock = addresses.getAddress("olympus-timelock");
            RolesAdmin rolesAdmin = RolesAdmin(addresses.getAddress("olympus-policy-roles-admin"));

            vm.prank(daoMS);
            rolesAdmin.pushNewAdmin(timelock);
        }

        // Simulate the proposal
        _simulateProposal(address(proposal));
    }
}
