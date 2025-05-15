// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {Kernel, Actions} from "src/Kernel.sol";
import {console2} from "forge-std/console2.sol";

// CoolerV2Proposal imports
import {CoolerV2Proposal} from "src/proposals/CoolerV2Proposal.sol";

contract CoolerV2ProposalTest is ProposalTest {
    Kernel public kernel;

    // TODO update block after installation by MS
    uint48 public constant MS_INSTALLATION_BLOCK = 22430380;

    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to actual deployment of the proposal (otherwise it will fail)
        vm.createSelectFork(RPC_URL, MS_INSTALLATION_BLOCK + 1);

        /// @dev Deploy your proposal
        CoolerV2Proposal proposal = new CoolerV2Proposal();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = false;

        _setupSuite(address(proposal));
        kernel = Kernel(addresses.getAddress("olympus-kernel"));

        // Simulate the LoanConsolidatorInstall batch script having been run
        // The simulation will revert otherwise
        // This proposal will also fail until the RGSTY proposal has been executed
        // Install LoanConsolidator
        if (!hasBeenSubmitted) {
            console2.log("Activating LTV Oracle");
            address ltvOracle = addresses.getAddress("olympus-policy-cooler-v2-ltv-oracle");
            vm.prank(addresses.getAddress("olympus-multisig-dao"));
            kernel.executeAction(Actions.ActivatePolicy, ltvOracle);

            console2.log("Activating Treasury Borrower");
            address treasuryBorrower = addresses.getAddress(
                "olympus-policy-cooler-v2-treasury-borrower"
            );
            vm.prank(addresses.getAddress("olympus-multisig-dao"));
            kernel.executeAction(Actions.ActivatePolicy, treasuryBorrower);
        }

        // Simulate the proposal
        _setupSuite(address(proposal));
        _simulateProposal();
    }
}
