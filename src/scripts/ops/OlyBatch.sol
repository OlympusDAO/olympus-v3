// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {BatchScript} from "./lib/BatchScript.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";

abstract contract OlyBatch is BatchScript {
    using stdJson for string;

    string internal env;
    string internal chain;
    address daoMS;
    address policyMS;
    address emergencyMS;
    address safe;

    modifier isDaoBatch(bool send_) {
        // Load environment addresses for chain
        console2.log("\n\n*** Loading environment");
        chain = vm.envString("CHAIN");
        env = vm.readFile("./src/scripts/env.json");

        // Set safe addresses
        daoMS = vm.envAddress("DAO_MS"); // DAO MS address
        policyMS = vm.envAddress("POLICY_MS"); // Policy MS address
        emergencyMS = vm.envAddress("EMERGENCY_MS"); // Emergency MS address
        safe = daoMS;

        // Load addresses from env (as defined in batch script)
        console2.log("\n\n*** Compiling batch");
        loadEnv();

        // Compile batch
        _;

        // Execute batch
        console2.log("\n\n*** Executing batch");
        executeBatch(daoMS, send_);
    }

    modifier isPolicyBatch(bool send_) {
        // Load environment addresses for chain
        console2.log("\n\n*** Loading environment");
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
        console2.log("\n\n*** Compiling batch");
        _;

        // Execute batch
        console2.log("\n\n*** Executing batch");
        executeBatch(policyMS, send_);
    }

    modifier isEmergencyBatch(bool send_) {
        // Load environment addresses for chain
        console2.log("\n\n*** Loading environment");
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
        console2.log("\n\n*** Compiling batch");
        _;

        // Execute batch
        console2.log("\n\n*** Executing batch");
        executeBatch(emergencyMS, send_);
    }

    /// @notice     For testing purposes only, when calling from another script
    /// @dev        This is necessary as a parent script may want to combine the results of multiple functions into a single batch, whereas the modifiers above will execute each function in a separate batch
    function initTestBatch() public {
        // Load environment addresses for chain
        console2.log("\n\n*** Loading environment");
        chain = vm.envString("CHAIN");
        env = vm.readFile("./src/scripts/env.json");

        // Set safe addresses
        daoMS = vm.envAddress("DAO_MS"); // DAO MS address
        policyMS = vm.envAddress("POLICY_MS"); // Policy MS address
        emergencyMS = vm.envAddress("EMERGENCY_MS"); // Emergency MS address
        safe = daoMS;

        // Load addresses from env
        console2.log("\n\n*** Compiling batch");
        loadEnv();
    }

    function envAddress(string memory version, string memory key) internal view returns (address) {
        return env.readAddress(string.concat(".", version, ".", chain, ".", key));
    }

    function envAddressWithChain(
        string memory chain_,
        string memory version_,
        string memory key_
    ) internal view returns (address) {
        return env.readAddress(string.concat(".", version_, ".", chain_, ".", key_));
    }

    function envUint(string memory version, string memory key) internal view returns (uint256) {
        return env.readUint(string.concat(".", version, ".", chain, ".", key));
    }

    function envInt(string memory version, string memory key) internal view returns (int256) {
        return env.readInt(string.concat(".", version, ".", chain, ".", key));
    }

    function loadEnv() internal virtual;

    function addToBatch(address to_, bytes memory data_) internal returns (bytes memory) {
        return addToBatch(safe, to_, data_);
    }

    function addToBatch(
        address to_,
        uint256 value_,
        bytes memory data_
    ) internal returns (bytes memory) {
        return addToBatch(safe, to_, value_, data_);
    }
}