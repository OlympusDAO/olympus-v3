// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "./ProposalScript.sol";

/// @notice Proposal for activation of the CCIP Bridge for Solana
// solhint-disable gas-custom-errors
contract SolanaCCIPBridgeProposal is GovernorBravoProposal {
    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 10;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "Solana CCIP Bridge Activation";
    }

    // Provides a brief description of the proposal.
    // solhint-disable quotes
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Solana CCIP Bridge Activation\n\n",
                "This is an in-principle proposal for activating the CCIP Bridge for Solana.\n\n",
                "## Justification\n\n",
                "As voted upon in [OIP-183](https://snapshot.box/#/s:olympusdao.eth/proposal/0x737aeb9e5b5ecf1bd757ec46dd6a1a3c4332b2b30cf6156fde19cd532e4200d3), it was proposed that CCIP be used to implement as bridging infrastructure to Solana.\n\n",
                "The contracts are designed in a way where they do not require privileged actions nor permissions, and so do not require installation/activation in the Kernel.\n\n",
                "However, as it was explicitly mentioned in the OIP that there would be an OCG proposal for this matter, this proposal has been created.\n\n",
                "The CCIP Bridge will operate between Ethereum mainnet and Solana mainnet.\n\n",
                "On the mainnet side, the CCIP Bridge is composed of the following:\n\n",
                "- LockReleaseTokenPool: A standard CCIP contract that custodies tokens bridged from Ethereum mainnet to Solana. The custodied tokens provide an upper cap on the amount of OHM that can be bridged back from Solana (or any other chain), which increases security of the system.\n",
                "- CCIPCrossChainBridge: A custom contract that makes it simple for integrators or the Olympus frontend to bridge OHM from Ethereum mainnet to Solana.\n\n",
                "On the Solana side, the CCIP Bridge is composed of the following:\n\n",
                "- BurnMintTokenPool: A standard CCIP contract that will mint and burn OHM as necessary.\n",
                "- OHM token: A standard SPL token will be deployed on Solana, with minting rights given to the BurnMintTokenPool.\n\n",
                "## Resources\n\n",
                "The custom/modified contracts have been [audited by Electisec](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2025-06_Electisec_CCIP_Bridge.pdf).\n\n",
                "The code changes can be viewed at [PR 69](https://github.com/OlympusDAO/olympus-v3/pull/69).\n\n",
                "## Proposal Steps\n\n",
                "As stated, this proposal is an in-principle proposal, and there are no actions to be taken upon execution of the proposal.\n\n",
                "At the completion of the proposal, the DAO MS will enable the bridging contracts in order to allow bridging to/from Solana.\n\n"
            );
    }

    // solhint-enable quotes

    function _deploy(Addresses addresses, address) internal override {
        // Nothing to do
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        // Nothing to do
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
        // Nothing to do
    }
}

contract SolanaCCIPBridgeProposalScript is ProposalScript {
    constructor() ProposalScript(new SolanaCCIPBridgeProposal()) {}
}
