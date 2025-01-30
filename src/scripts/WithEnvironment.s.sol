// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

abstract contract WithEnvironment is Script {
    using stdJson for string;

    string public chain;
    string public env;

    function _loadEnv(string calldata chain_) internal {
        chain = chain_;
        console2.log("Using chain:", chain_);

        // Load environment file
        env = vm.readFile("./src/scripts/env.json");
    }

    /// @notice Get address from environment file
    /// @dev    First checks in the current chain's environment file, then in axis-core's environment file
    ///
    /// @param  key_    The key to look up in the environment file
    /// @return address The address from the environment file, or the zero address
    function _envAddress(string memory key_) internal view returns (address) {
        console2.log("    Checking in env.json");
        string memory fullKey = string.concat(".current.", chain, ".", key_);
        address addr;
        bool keyExists = vm.keyExists(env, fullKey);

        if (keyExists) {
            addr = env.readAddress(fullKey);
            console2.log("    %s: %s (from env.json)", key_, addr);
        } else {
            console2.log("    %s: *** NOT FOUND ***", key_);
        }

        return addr;
    }

    /// @notice Get a non-zero address from environment file
    /// @dev    First checks in the current chain's environment file, then in axis-core's environment file
    ///
    ///         Reverts if the key is not found
    ///
    /// @param  key_    The key to look up in the environment file
    /// @return address The address from the environment file
    function _envAddressNotZero(string memory key_) internal view returns (address) {
        address addr = _envAddress(key_);
        require(
            addr != address(0),
            string.concat("WithEnvironment: key '", key_, "' has zero address")
        );

        return addr;
    }
}
