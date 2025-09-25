// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";
// Olympus Kernel, Modules, and Policies
import {Kernel} from "src/Kernel.sol";
import {GovernorBravoDelegate} from "src/external/governance/GovernorBravoDelegate.sol";
import {GovernorBravoDelegator} from "src/external/governance/GovernorBravoDelegator.sol";

import {ScriptSuite} from "proposal-sim/script/ScriptSuite.s.sol";

// OIP_170 upgrades the Governor Bravo delegate with minor audit remediations.
contract OIP_170 is GovernorBravoProposal {
    Kernel internal _kernel;

    // Returns the id of the proposal.
    function id() public view override returns (uint256) {
        return 3;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "OIP-170";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return
            "## OIP-170: Post-audit OCG Upgrade\n"
            "\n"
            "### Context\n"
            "\n"
            "Olympus has deployed a modified version of the GovernorBravo system (originally by Compound) to use for onchain governance (OCG). Up to date information about the system can be found on the Olympus [documentation](https://docs.olympusdao.finance/main/governance/governance) site.\n"
            "\n"
            "As a safeguard against potential issues and following best practices used by other DAOs, Olympus' GovernorBravo is upgradable using a proxy pattern. This allows, among other things, OCG proposals to upgrade the Governor logic itself to patch certain types of issues with the contract.\n"
            "\n"
            "In line with the activation of the GovernorBravo system executed by [OIP-166](https://app.olympusdao.finance/#/governance/proposals/1), Olympus commissioned another audit of the code from yAudit. No major issues were found and the proposal proceeded with activation. However, there were some minor issues that were deemed appropriate to address in a follow-on proposal. We are now here.\n"
            "\n"
            "### Audit Results\n"
            "\n"
            "yAudit's full report from their audit of the OCG system can be found [here](https://docs.olympusdao.finance/assets/files/yaudit_report-47a860aa5e5083dce8d9fbc8a4dcfad8.pdf).\n"
            "\n"
            "No critical or high severity issues were found, and none of the issues put any funds at risk. There were 3 medium severity issues and 4 low severity issues according to their rating system.\n"
            "\n"
            "To directly quote their final remarks in the report:\n"
            "OlympusDAO has selected a solid and battle-tested option to implement its on-chain governance system. The review has identified some issues within edge cases for the functionalities added by the client, which can lead to an inability to execute proposals when the system enters the emergency state or allow an attacker to brick a proposal's execution under rare conditions.\n"
            "\n"
            "Additionally, the review has identified a theoretical attack vector by which an attacker can inflate or deflate a proposal's quorum requirements: at the time of the report's writing, the largest relative manipulation possible was around 1% of the non-manipulated amount.\n"
            "\n"
            "Overall, the system lies on solid foundations that have proven reliable for normal state operations. In the case of emergency state operations, additional care and testing should be applied to verify that the system processes proposals correctly, both when their entire lifecycle occurs with the system in emergency state and when the system switches state during it.\n"
            "\n"
            "### Remediations\n"
            "\n"
            "After receiving the audit results, Olympus devs reviewed the results with yAudit and developed a remediation plan. We either remediated or there are existing mitigations in place for all of the issues raised.\n"
            "\n"
            "The issues that were fixed are M3, L2, L3, L4, and I5.\n"
            "\n"
            "M1 is not fixed because the likelihood is very low and the impact is minimal (would simply need to resubmit the proposal). Additionally, it would require a change to the storage layout which we wish to avoid.\n"
            "\n"
            "M2 is not truly fixable without deploying a new gOHM token, which would be a significant undertaking and has many downstream effects within the Olympus system as a whole. The impact of the issue is constrained to the amount of OHM that is flashloanable (less than 1% of supply). We also have the option to mitigate this issue entirely by enabling a staking warm-up (but with UX costs for users) if needed in the future.\n"
            "\n"
            "L1 is more of an inconvenience than a true issue in that overpaying for an execution that requires native ETH can result in the executor overpaying. This can be resolved by refunding the executor at a later time.\n"
            "\n"
            "The remediated GovernorBravoDelegate contract (which is the implementation contract the proxy GovernorBravoDelegator references for its logic) can be found in this [Pull Request](https://github.com/OlympusDAO/olympus-v3/pull/13) on the olympus-v3 repository. It has been deployed and verified at this address on mainnet: [0xdE3F82D378c3b4E3F3f848b8DF501914b3317E96](https://etherscan.io/address/0xdE3F82D378c3b4E3F3f848b8DF501914b3317E96).\n"
            "\n"
            "In order for the updated contract logic to take effect, an OCG proposal must be passed to set this address as the new implementation contract. This is done by calling the `_setImplementation(address)` function on the GovernorBravoDelegator contract (which is the canonical Governor address used for OCG).";
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

// @dev Use this script to simulates or run a single proposal
// Use this as a template to create your own script
// `forge script script/GovernorBravo.s.sol:GovernorBravoScript -vvvv --rpc-url {rpc} --broadcast --verify --etherscan-api-key {key}`
contract OIP_170_Script is ScriptSuite {
    string public constant ADDRESSES_PATH = "./src/proposals/addresses.json";

    constructor() ScriptSuite(ADDRESSES_PATH, new OIP_170()) {}

    function run() public override {
        // set debug mode to true and run it to build the actions list
        proposal.setDebug(true);

        // run the proposal to build it
        proposal.run(addresses, address(0));

        // get the calldata for the proposal, doing so in debug mode prints it to the console
        proposal.getCalldata();
    }
}
