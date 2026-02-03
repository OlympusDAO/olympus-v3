// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.15;

import {BatchScript} from "./lib/BatchScript.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import {Surl} from "@surl-1.0.0/Surl.sol";
import {VmSafe} from "forge-std/Vm.sol";

abstract contract OlyBatch is BatchScript {
    using stdJson for string;
    using Surl for *;

    string internal env;
    string internal chain;
    address internal daoMS;
    address internal policyMS;
    address internal emergencyMS;

    modifier isDaoBatch(bool send_) {
        // Load environment addresses for chain
        chain = vm.envString("CHAIN");
        env = vm.readFile("./src/scripts/env.json");

        // TODO shift to using WithEnvironment.s.sol

        // Set safe addresses
        daoMS = vm.envAddress("DAO_MS"); // DAO MS address
        policyMS = vm.envAddress("POLICY_MS"); // Policy MS address
        emergencyMS = vm.envAddress("EMERGENCY_MS"); // Emergency MS address
        safe = daoMS;

        // Load addresses from env (as defined in batch script)
        loadEnv();

        // Compile batch
        _;

        // Execute batch
        executeBatch(send_);
    }

    modifier isPolicyBatch(bool send_) {
        // Load environment addresses for chain
        chain = vm.envString("CHAIN");
        env = vm.readFile("./src/scripts/env.json");

        // Set safe addresses
        daoMS = vm.envAddress("DAO_MS"); // DAO MS address
        policyMS = vm.envAddress("POLICY_MS"); // Policy MS address
        emergencyMS = vm.envAddress("EMERGENCY_MS"); // Emergency MS address
        safe = policyMS;

        // Load addresses from env (as defined in batch script)
        loadEnv();

        // Compile batch
        _;

        // Execute batch
        executeBatch(send_);
    }

    modifier isEmergencyBatch(bool send_) {
        // Load environment addresses for chain
        chain = vm.envString("CHAIN");
        env = vm.readFile("./src/scripts/env.json");

        // Set safe addresses
        daoMS = vm.envAddress("DAO_MS"); // DAO MS address
        policyMS = vm.envAddress("POLICY_MS"); // Policy MS address
        emergencyMS = vm.envAddress("EMERGENCY_MS"); // Emergency MS address
        safe = emergencyMS;

        // Load addresses from env (as defined in batch script)
        loadEnv();

        // Compile batch
        _;

        // Execute batch
        executeBatch(send_);
    }

    function envAddress(string memory version, string memory key) internal view returns (address) {
        return env.readAddress(string.concat(".", version, ".", chain, ".", key));
    }

    function loadEnv() internal virtual;

    function executeBatch(bool send_) internal override {
        bool useAnvilFork = vm.envOr("USE_ANVIL_FORK", false);
        bool useTenderlyFork = vm.envOr("USE_TENDERLY_FORK", false);

        if (send_) {
            if (useAnvilFork) {
                _sendAnvilBatch();
                return;
            }
            if (useTenderlyFork) {
                _sendTenderlyBatch();
                return;
            }
        }

        super.executeBatch(send_);
    }

    function _sendAnvilBatch() private {
        // Check if we're in broadcast mode
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Not broadcasting, skipping Anvil fork execution");
            return;
        }

        console2.log("Executing batch via Anvil fork");
        vm.startBroadcast(safe);

        for (uint256 i; i < actionsTo.length; i++) {
            console2.log("  Executing batch action ", i + 1);
            (bool success, bytes memory data) = actionsTo[i].call(actionsData[i]);
            if (!success) {
                // Revert with error data
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let revertStringLength := mload(data)
                    let revertStringPtr := add(data, 0x20)
                    revert(revertStringPtr, revertStringLength)
                }
            }
        }

        vm.stopBroadcast();
        console2.log("Batch executed successfully");
    }

    function _sendTenderlyBatch() private {
        // Check if we're in broadcast mode
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Not broadcasting, skipping Tenderly VNet execution");
            return;
        }

        // Get the testnet RPC URL and access key
        string memory TENDERLY_ACCOUNT_SLUG = vm.envString("TENDERLY_ACCOUNT_SLUG");
        string memory TENDERLY_PROJECT_SLUG = vm.envString("TENDERLY_PROJECT_SLUG");
        string memory TENDERLY_VNET_ID = vm.envString("TENDERLY_VNET_ID");
        string memory TENDERLY_ACCESS_KEY = vm.envString("TENDERLY_ACCESS_KEY");

        // Iterate over the proposal actions and execute them
        for (uint256 i; i < actionsTo.length; i++) {
            console2.log("Preparing batch action ", i + 1);

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
            console2.log("Executing batch action ", i + 1);
            (uint256 status, bytes memory response) = url.post(
                headers,
                string.concat(
                    "{",
                    '"callArgs": {',
                    '"from": "',
                    vm.toString(safe),
                    '", "to": "',
                    vm.toString(actionsTo[i]),
                    '", "gas": "0x7a1200", "gasPrice": "0x10", "value": "0x0", ',
                    '"data": "',
                    vm.toString(actionsData[i]),
                    '"',
                    "}}"
                )
            );
            // solhint-enable quotes

            string memory responseString = string(response);
            console2.log("Response: ", responseString);

            // If the response contains "error", exit
            if (status >= 400 || vm.keyExists(responseString, ".error")) {
                revert("Error executing batch action");
            }
        }
    }
}
