// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import {console2} from "forge-std/console2.sol";

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";
// Olympus Kernel, Modules, and Policies
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {GovernorBravoDelegate} from "src/external/governance/GovernorBravoDelegate.sol";
import {GovernorBravoDelegator} from "src/external/governance/GovernorBravoDelegator.sol";

// OIP_169 upgrades the Governor Bravo delegate with minor audit remediations.
contract OIP_169 is GovernorBravoProposal {
    Kernel internal _kernel;

    // Returns the id of the proposal.
    function id() public view override returns (uint256) {
        return 3;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "OIP-169";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return
            "## OIP 169: Post-audit OCG Upgrade\n"
            "\n"
            "### Audit Results\n"
            "\n"
            "yAudit recently completed their audit of the Olympus fork of GovernorBravo (as used in the current implementation). The full report can be found [here](TODO).\n"
            "\n"
            "No critical or high severity issues were found and none of the issues put any funds at risk. There were 3 medium severity issues and 4 low severity issues according to their rating system.\n"
            "\n"
            "### Remediations\n"
            "\n"
            "After receiving the audit results, Olympus devs reviewed the results with yAudit and developed a remediation plan. We either remediated or there are existing mitigations in place for all of the medium and low issues.\n"
            "\n"
            "The remediated GovernorBravoDelegate contract (which is the implementation contract the proxy GovernorBravoDelegator references for its logic) can be found in this [Pull Request](https://github.com/OlympusDAO/olympus-v3/pull/13) on the olympus-v3 repository. It has been deployed and verified at this address on mainnet: [0xdE3F82D378c3b4E3F3f848b8DF501914b3317E96](https://etherscan.io/address/0xdE3F82D378c3b4E3F3f848b8DF501914b3317E96).\n"
            "\n"
            "In order for the updated contract logic to take effect, an OCG proposal must be passed to set this address as the new implementation contract. This is done by calling the `_setImplementation(address)` function on the GovernorBravoDelegator contract (which is the canonical Governor address used for OCG).\n";
    }

    // No deploy actions needed
    function _deploy(Addresses addresses, address) internal override {
        // Cache the kernel address in state
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // NOTE: In its current form, OCG is limited to admin roles when it refers to interactions with
    //       exsting policies and modules. Nevertheless, the DAO MS is still the Kernel executor.
    //       Because of that, OCG can't interact (un/install policies/modules) with the Kernel, yet.

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        // Load the necessary addresses
        address governor = addresses.getAddress("olympus-governor");
        address newDelegate = addresses.getAddress("olympus-governor-delegate-v2");

        // STEP 1: Set the implementation on the Governor to the new delegate
        _pushAction(
            governor,
            abi.encodeWithSelector(GovernorBravoDelegator._setImplementation.selector, newDelegate),
            "Update the Governor Bravo delegate implementation"
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
    function _validate(Addresses addresses, address) internal override {
        // Load the contract addresses
        GovernorBravoDelegate governor = GovernorBravoDelegate(
            addresses.getAddress("olympus-governor")
        );
        address newDelegate = addresses.getAddress("olympus-governor-delegate-v2");

        // Validate the Governor Bravo delegate is updated on the Governor
        require(governor.implementation() == newDelegate, "Implementation not updated");
    }
}

import {ScriptSuite} from "proposal-sim/script/ScriptSuite.s.sol";

// @dev Use this script to simulates or run a single proposal
// Use this as a template to create your own script
// `forge script script/GovernorBravo.s.sol:GovernorBravoScript -vvvv --rpc-url {rpc} --broadcast --verify --etherscan-api-key {key}`
contract OIP_169_Script is ScriptSuite {
    string public constant ADDRESSES_PATH = "./src/proposals/addresses.json";

    constructor() ScriptSuite(ADDRESSES_PATH, new OIP_169()) {}

    function run() public override {
        // set debug mode to true and run it to build the actions list
        proposal.setDebug(true);

        // run the proposal to build it
        proposal.run(addresses, address(0));

        // get the calldata for the proposal, doing so in debug mode prints it to the console
        proposal.getCalldata();
    }
}
