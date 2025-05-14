// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {Kernel, Actions} from "src/Kernel.sol";
import {console2} from "forge-std/console2.sol";

import {CoolerV2Proposal} from "src/proposals/CoolerV2Proposal.sol";
import {CoolerV2DelegatesForHohmProposal} from "src/proposals/CoolerV2DelegatesForHohmProposal.sol";

contract CoolerV2DelegatesForHohmProposalTest is ProposalTest {
    Kernel public kernel;

    // TODO update block after installation by MS
    uint48 public constant MS_INSTALLATION_BLOCK = 22430380;

    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to actual deployment of the proposal (otherwise it will fail)
        vm.createSelectFork(RPC_URL, MS_INSTALLATION_BLOCK + 1);

        /// @dev Deploy your proposal
        CoolerV2Proposal coolerProposal = new CoolerV2Proposal();
        CoolerV2DelegatesForHohmProposal hohmProposal = new CoolerV2DelegatesForHohmProposal();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = false;

        address[] memory proposals_ = new address[](2);
        proposals_[0] = address(coolerProposal);
        proposals_[1] = address(hohmProposal);
        _setupSuites(proposals_);
        kernel = Kernel(addresses.getAddress("olympus-kernel"));

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

            console2.log("Activating DLGTE");
            address dlgte = addresses.getAddress("olympus-module-dlgte");
            vm.prank(addresses.getAddress("olympus-multisig-dao"));
            kernel.executeAction(Actions.InstallModule, dlgte);

            console2.log("Activating Cooler V2");
            address coolerV2 = addresses.getAddress("olympus-policy-cooler-v2");
            vm.prank(addresses.getAddress("olympus-multisig-dao"));
            kernel.executeAction(Actions.ActivatePolicy, coolerV2);
        }

        // Simulate the proposals
        _simulateProposal();
    }
}
