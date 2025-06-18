// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ScriptSuite} from "proposal-sim/script/ScriptSuite.s.sol";
import {Address} from "proposal-sim/utils/Address.sol";
import {Surl} from "@surl-1.0.0/Surl.sol";
import {console2} from "forge-std/console2.sol";
import {IProposal} from "proposal-sim/proposals/IProposal.sol";

/// @notice Allows submission and testing of OCG proposals
/// @dev    Inheriting contracts must implement the constructor
///
///         See the scripts in `src/scripts/proposals/`
abstract contract ProposalScript is ScriptSuite {
    using Address for address;
    using Surl for *;

    string public constant ADDRESSES_PATH = "./src/proposals/addresses.json";

    constructor(IProposal _proposal) ScriptSuite(ADDRESSES_PATH, _proposal) {}

    function run() public override {
        // set debug mode to true and run it to build the actions list
        proposal.setDebug(true);

        // run the proposal to build it
        proposal.run(addresses, address(0));

        // get the calldata for the proposal, doing so in debug mode prints it to the console
        bytes memory proposalCalldata = proposal.getCalldata();

        address governor = addresses.getAddress("olympus-governor");

        // Register the proposal
        console2.log("\n\n");
        console2.log("Submitting proposal...");
        vm.startBroadcast();
        console2.log("Proposer: ", msg.sender);
        bytes memory proposalReturnData = address(payable(governor)).functionCall(proposalCalldata);
        vm.stopBroadcast();
        uint256 proposalId = abi.decode(proposalReturnData, (uint256));
        console2.log("Proposal ID:", proposalId);
    }

    function printProposalInputs() public {
        // set debug mode to true and run it to build the actions list
        proposal.setDebug(true);

        // run the proposal to build it
        proposal.run(addresses, address(0));

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = proposal
            .getProposalActions();
        uint256 len = targets.length;
        // print the targets
        console2.log("Targets:");
        string memory t_str = "[";
        for (uint256 i = 0; i < len; i++) {
            if (i == len - 1) {
                t_str = string.concat(t_str, vm.toString(targets[i]), "]");
            } else {
                t_str = string.concat(t_str, vm.toString(targets[i]), ", ");
            }
        }
        console2.log(t_str);

        // print the values
        console2.log("Values:");
        string memory v_str = "[";
        for (uint256 i = 0; i < len; i++) {
            if (i == len - 1) {
                v_str = string.concat(v_str, vm.toString(values[i]), "]");
            } else {
                v_str = string.concat(v_str, vm.toString(values[i]), ", ");
            }
        }
        console2.log(v_str);

        // print the calldatas
        console2.log("Calldatas:");
        string memory c_str = "[";
        for (uint256 i = 0; i < len; i++) {
            if (i == len - 1) {
                c_str = string.concat(c_str, vm.toString(calldatas[i]), "]");
            } else {
                c_str = string.concat(c_str, vm.toString(calldatas[i]), ", ");
            }
        }
        console2.log(c_str);

        // print the signatures list of empty strings
        console2.log("Signatures:");
        string memory s_str = "[";
        for (uint256 i = 0; i < len; i++) {
            if (i == len - 1) {
                s_str = string.concat(s_str, '""', "]");
            } else {
                s_str = string.concat(s_str, '""', ", ");
            }
        }

        // print the description
        console2.log("Description:");
        console2.log(proposal.description());
    }

    function executeOnTestnet() public {
        console2.log("Building proposal...");
        // set debug mode to true and run it to build the actions list
        proposal.setDebug(true);

        // run the proposal to build it
        proposal.run(addresses, address(0));

        console2.log("Preparing transactions");
        // Get the timelock address
        address timelock = addresses.getAddress("olympus-timelock");

        // Get the testnet RPC URL and access key
        string memory TENDERLY_ACCOUNT_SLUG = vm.envString("TENDERLY_ACCOUNT_SLUG");
        string memory TENDERLY_PROJECT_SLUG = vm.envString("TENDERLY_PROJECT_SLUG");
        string memory TENDERLY_VNET_ID = vm.envString("TENDERLY_VNET_ID");
        string memory TENDERLY_ACCESS_KEY = vm.envString("TENDERLY_ACCESS_KEY");

        // Iterate over the proposal actions and execute them
        (address[] memory targets, , bytes[] memory arguments) = proposal.getProposalActions();
        for (uint256 i; i < targets.length; i++) {
            console2.log("Preparing proposal action ", i + 1);

            // Construct the API call
            string[] memory headers = new string[](3);
            headers[0] = "Accept: application/json";
            headers[1] = "Content-Type: application/json";
            headers[2] = string.concat("X-Access-Key: ", TENDERLY_ACCESS_KEY);

            string memory url = string.concat(
                "https://api.tenderly.co/api/v1/account/",
                TENDERLY_ACCOUNT_SLUG,
                "/project/",
                TENDERLY_PROJECT_SLUG,
                "/vnets/",
                TENDERLY_VNET_ID,
                "/transactions"
            );

            // Execute the API call
            // solhint-disable quotes
            console2.log("Executing proposal action ", i + 1);
            (uint256 status, bytes memory response) = url.post(
                headers,
                string.concat(
                    "{",
                    '"callArgs": {',
                    '"from": "',
                    vm.toString(timelock),
                    '", "to": "',
                    vm.toString(targets[i]),
                    '", "gas": "0x7a1200", "gasPrice": "0x10", "value": "0x0", ',
                    '"data": "',
                    vm.toString(arguments[i]),
                    '"',
                    "}}"
                )
            );
            // solhint-enable quotes

            string memory responseString = string(response);
            console2.log("Response: ", responseString);

            // If the response contains "error", exit
            if (status >= 400 || vm.keyExists(responseString, ".error")) {
                revert("Error executing proposal action");
            }
        }
    }
}
