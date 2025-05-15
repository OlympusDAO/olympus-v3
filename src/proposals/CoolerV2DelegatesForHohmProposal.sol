// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Olympus Kernel, Modules, and Policies
import {Kernel} from "src/Kernel.sol";
import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";

// Script
import {ProposalScript} from "./ProposalScript.sol";

// Libraries
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

/// @notice Sets gOHM delegation limits for hOHM.
// solhint-disable gas-custom-errors
contract CoolerV2DelegatesForHohmProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    uint32 public constant MAX_DELEGATE_ADDRESSES = 1_000_000;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 9;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "Cooler V2 Delegates Limit for hOHM";
    }

    // Provides a brief description of the proposal.
    // solhint-disable quotes
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Set Cooler V2 Delegates limit for hOHM\n\n",
                "This proposal sets the maximum number of addresses that Origami Finance's hOHM is permitted delegate gOHM voting power to.\n\n",
                "## Justification\n\n",
                "Origami Finance's hOHM is an OHM derivative that uses Cooler v2 to programmatically leverage OHM to buy more OHM using the increase in Loan to Backing over time. This creates a maximally leveraged position whose health is contractually managed with minimized downside but leveraged upside. It also creates an economy of scale with a perpetual bid on OHM to grow.\n\n",
                "* Within Cooler v2's DLGTE module, individual borrowers, as well as platforms building on top of Cooler v2, can assign all or a portion of their gOHM voting power to delegate addresses.\n",
                "  * By default, the maximum number of delegates for an account is 10.\n",
                "* This proposal is to allow hOHM to delegate up to 1,000,000 addresses.\n",
                "  * Given that hOHM is immutable, the number of delegates is intentionally high to allow hOHM to support OHM users well into the foreseeable future.\n",
                "  * Through our extensive audits, we have demonstrated that a very high number of delegates will not present a security risk, but will provide hOHM with necessary and sufficient scalability.\n\n",
                "## Resources\n\n",
                "hOHm has been well audited by several discrete parties:\n\n",
                "- [Nethermind Audit Report - hOHM](https://github.com/TempleDAO/origami-public/tree/main/audits/hOHM/Nethermind_hOHM.pdf)\n",
                "- [Guardefy (Panprog) Audit Report - hOHM](https://github.com/TempleDAO/origami-public/tree/main/audits/hOHM/Panprog_hOHM.pdf)\n",
                "- [Electisec Audit Report - hOHM](https://github.com/TempleDAO/origami-public/tree/main/audits/hOHM/Electisec_hOHM.pdf)\n",
                "- [Electisec Audit Report - hOHM Migrator](https://github.com/TempleDAO/origami-public/tree/main/audits/hOHM/Electisec_hOHM_Migrator.pdf)\n\n",
                "## Liquidation Risk Mitigations\n\n",
                "In order to liquidate an unhealthy Cooler V2 position, all delegations for that account must be rescinded first. Block gas limits need to be considered to ensure positions can still be operationally liquidated.\n",
                "hOHM's economic design ensures it will not become unhealthy. However mitigations are in place to ensure hOHM can still be liquidated if there is an unforseen issue, even with the increase in allowed delegations:\n\n"
                "- hOHM: Users of hOHM may only delegate their gOHM voting power to one single address, all or nothing.\n",
                "- hOHM: Minimum gOHM to delegate: Users of hOHM must have a minimum effective gOHM balance of 0.1 gOHM. This economically limits the realistic number of delegations which hOHM will be able to delegate within Cooler V2.\n",
                "- hOHM: Auto delegation removal: If a hOHM user which has previously delegated > 0.1 gOHM then redeems their hOHM and reduces their effective gOHM balance below 0.1 gOHM, the delegation will automatically be removed. This prevents hOHM from having any 'dust' delegations.\n",
                "- Cooler V2: Unhealhy positions can have their delegations permisionlessly removed in batches. Once the number of delegations are reduced, the liquidation can proceed as normal.\n",
                "## Assumptions\n\n",
                "- The DLGTE module has been installed into the Kernel\n",
                "- The LTV Oracle, Treasury Borrower and Mono Cooler policies have been activated in the Kernel\n",
                "- The Treasury Borrower policy has been set on the Mono Cooler policy\n\n",
                "## Proposal Steps\n\n",
                string.concat(
                    "1. Set the maximum delegate addresses for hOHM to ",
                    Strings.toString(MAX_DELEGATE_ADDRESSES),
                    "."
                )
            );
    }

    // solhint-enable quotes

    // No deploy actions needed
    function _deploy(Addresses addresses, address) internal override {
        // Cache the kernel address in state
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        address coolerV2 = addresses.getAddress("olympus-policy-cooler-v2");
        address hohmManager = addresses.getAddress("origami-finance-hohm-manager");

        // STEP 1: Set the maximum delegate addresses for the hOHM account
        _pushAction(
            coolerV2,
            abi.encodeWithSelector(
                IMonoCooler.setMaxDelegateAddresses.selector,
                hohmManager,
                MAX_DELEGATE_ADDRESSES
            ),
            "Set max delegate addresses for hOHM"
        );
    }

    // Executes the proposal actions.
    function _run(Addresses addresses, address) internal override {
        // Simulates actions on TimelockController
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    // Validates the post-execution state.
    function _validate(Addresses addresses, address) internal view override {
        address coolerV2 = addresses.getAddress("olympus-policy-cooler-v2");
        address hohmManager = addresses.getAddress("origami-finance-hohm-manager");

        // Validate that the hOHM account has an updated maximum number of delegate addresses
        require(
            IMonoCooler(coolerV2).accountPosition(hohmManager).maxDelegateAddresses ==
                MAX_DELEGATE_ADDRESSES,
            "hOHM does not have the updated maximum number of delegate addresses"
        );
    }
}

contract CoolerV2ProposalScript is ProposalScript {
    constructor() ProposalScript(new CoolerV2DelegatesForHohmProposal()) {}
}
