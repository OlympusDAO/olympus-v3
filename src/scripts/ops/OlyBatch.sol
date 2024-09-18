// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {BatchScript} from "./lib/BatchScript.sol";
import {stdJson} from "forge-std/StdJson.sol";

abstract contract OlyBatch is BatchScript {
    using stdJson for string;

    string internal env;
    string internal chain;
    address internal daoMS;
    address internal policyMS;
    address internal emergencyMS;

    modifier isDaoBatch(bool send_) {
        // Load environment addresses for chain
        chain = vm.envString("CHAIN");
        env = vm.readFile("./src/scripts/env.json");

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
}
