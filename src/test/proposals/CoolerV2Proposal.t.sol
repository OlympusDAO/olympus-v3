// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {Kernel, Actions, Policy, toKeycode} from "src/Kernel.sol";
import {console2} from "forge-std/console2.sol";

// CoolerV2Proposal imports
import {CoolerV2Proposal} from "src/proposals/CoolerV2Proposal.sol";

contract CoolerV2ProposalTest is ProposalTest {
    Kernel public kernel;

    uint48 public constant MS_INSTALLATION_BLOCK = 22490036;

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

        // Simulate the CoolerV2 batch script having been run
        // The simulation will revert otherwise
        {
            address dlgte = addresses.getAddress("olympus-module-dlgte");
            if (address(kernel.getModuleForKeycode(toKeycode("DLGTE"))) == address(0)) {
                console2.log("Installing DLGTE");
                vm.prank(addresses.getAddress("olympus-multisig-dao"));
                kernel.executeAction(Actions.InstallModule, dlgte);
            }

            address ltvOracle = addresses.getAddress("olympus-policy-cooler-v2-ltv-oracle");
            if (!Policy(ltvOracle).isActive()) {
                console2.log("Activating LTV Oracle");
                vm.prank(addresses.getAddress("olympus-multisig-dao"));
                kernel.executeAction(Actions.ActivatePolicy, ltvOracle);
            }

            address treasuryBorrower = addresses.getAddress(
                "olympus-policy-cooler-v2-treasury-borrower"
            );
            if (!Policy(treasuryBorrower).isActive()) {
                console2.log("Activating Treasury Borrower");
                vm.prank(addresses.getAddress("olympus-multisig-dao"));
                kernel.executeAction(Actions.ActivatePolicy, treasuryBorrower);
            }

            address coolerV2 = addresses.getAddress("olympus-policy-cooler-v2");
            if (!Policy(coolerV2).isActive()) {
                console2.log("Activating CoolerV2");
                vm.prank(addresses.getAddress("olympus-multisig-dao"));
                kernel.executeAction(Actions.ActivatePolicy, coolerV2);
            }
        }

        // Simulate the proposal
        _setupSuite(address(proposal));
        _simulateProposal();
    }
}
