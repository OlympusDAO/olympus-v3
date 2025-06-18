// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.15;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

abstract contract WithEnvironment is Script {
    using stdJson for string;

    string public chain;
    string public env;

    function _loadEnv(string memory chain_) internal {
        chain = chain_;
        console2.log("  Using chain:", chain_);

        // Load environment file
        env = vm.readFile("./src/scripts/env.json");
    }

    function _isDebugLogLevel() internal view returns (bool) {
        return vm.envOr("DEBUG", false);
    }

    // ===== ADDRESSES ===== //

    /// @notice Get address from environment file
    ///
    /// @param  chain_  The chain to look up in the environment file
    /// @param  key_    The key to look up in the environment file
    /// @return address The address from the environment file, or the zero address
    function _envAddress(string memory chain_, string memory key_) internal view returns (address) {
        bool isDebug = _isDebugLogLevel();

        if (isDebug) console2.log("  Checking in env.json for", key_, "on", chain_);
        string memory fullKey = string.concat(".current.", chain_, ".", key_);
        address addr;
        bool keyExists = vm.keyExists(env, fullKey);

        if (keyExists) {
            addr = env.readAddress(fullKey);
            if (isDebug) console2.log("    %s: %s (from env.json)", key_, addr);
        } else {
            if (isDebug) console2.log("    %s: *** NOT FOUND ***", key_);
        }

        return addr;
    }

    /// @notice Get address from environment file for the current chain
    ///
    /// @param  key_    The key to look up in the environment file
    /// @return address The address from the environment file
    function _envAddress(string memory key_) internal view returns (address) {
        return _envAddress(chain, key_);
    }

    /// @notice Get a non-zero address from environment file
    /// @dev    Reverts if the key is not found or the address is zero
    ///
    /// @param  chain_  The chain to look up in the environment file
    /// @param  key_    The key to look up in the environment file
    /// @return address The address from the environment file
    function _envAddressNotZero(
        string memory chain_,
        string memory key_
    ) internal view returns (address) {
        address addr = _envAddress(chain_, key_);
        // solhint-disable-next-line custom-errors
        require(
            addr != address(0),
            string.concat("WithEnvironment: key '", key_, "' has zero address")
        );

        return addr;
    }

    /// @notice Get a non-zero address from environment file for the current chain
    /// @dev    Reverts if the key is not found or the address is zero
    ///
    /// @param  key_    The key to look up in the environment file
    /// @return address The address from the environment file
    function _envAddressNotZero(string memory key_) internal view returns (address) {
        return _envAddressNotZero(chain, key_);
    }

    // ===== STRINGS ===== //

    /// @notice Get string from environment file
    ///
    /// @param  chain_  The chain to look up in the environment file
    /// @param  key_    The key to look up in the environment file
    /// @return string The string from the environment file, or the empty string
    function _envString(
        string memory chain_,
        string memory key_
    ) internal view returns (string memory) {
        bool isDebug = _isDebugLogLevel();

        if (isDebug) console2.log("  Checking in env.json for", key_, "on", chain_);
        string memory fullKey = string.concat(".current.", chain_, ".", key_);
        string memory str;
        bool keyExists = vm.keyExists(env, fullKey);

        if (keyExists) {
            str = env.readString(fullKey);
            if (isDebug) console2.log("    %s: %s (from env.json)", key_, str);
        } else {
            if (isDebug) console2.log("    %s: *** NOT FOUND ***", key_);
        }

        return str;
    }

    function _envString(string memory key_) internal view returns (string memory) {
        return _envString(chain, key_);
    }

    function _envStringNotEmpty(
        string memory chain_,
        string memory key_
    ) internal view returns (string memory) {
        string memory str = _envString(chain_, key_);
        // solhint-disable-next-line custom-errors
        require(
            bytes(str).length > 0,
            string.concat("WithEnvironment: key '", key_, "' has empty string")
        );

        return str;
    }

    function _envStringNotEmpty(string memory key_) internal view returns (string memory) {
        return _envStringNotEmpty(chain, key_);
    }

    // ===== STRING ARRAYS ===== //

    /// @notice Get a string array from environment file
    ///
    /// @param  chain_  The chain to look up in the environment file
    /// @param  key_    The key to look up in the environment file
    /// @return string The string from the environment file, or the empty string
    function _envStringArray(
        string memory chain_,
        string memory key_
    ) internal view returns (string[] memory) {
        bool isDebug = _isDebugLogLevel();

        if (isDebug) console2.log("  Checking in env.json for", key_, "on", chain_);
        string memory fullKey = string.concat(".current.", chain_, ".", key_);
        string[] memory str;
        bool keyExists = vm.keyExists(env, fullKey);

        if (keyExists) {
            str = env.readStringArray(fullKey);

            string memory strStr = "[";
            for (uint256 i = 0; i < str.length; i++) {
                strStr = string.concat(strStr, str[i]);
                if (i < str.length - 1) {
                    strStr = string.concat(strStr, ", ");
                }
            }
            strStr = string.concat(strStr, "]");

            if (isDebug) console2.log("    %s: %s (from env.json)", key_, strStr);
        } else {
            if (isDebug) console2.log("    %s: *** NOT FOUND ***", key_);
        }

        return str;
    }

    function _envStringArray(string memory key_) internal view returns (string[] memory) {
        return _envStringArray(chain, key_);
    }

    function _envStringArrayNotEmpty(
        string memory chain_,
        string memory key_
    ) internal view returns (string[] memory) {
        string[] memory str = _envStringArray(chain_, key_);
        // solhint-disable-next-line custom-errors
        require(
            str.length > 0,
            string.concat("WithEnvironment: key '", key_, "' has empty string array")
        );

        return str;
    }

    function _envStringArrayNotEmpty(string memory key_) internal view returns (string[] memory) {
        return _envStringArrayNotEmpty(chain, key_);
    }

    // ===== NUMBERS ===== //

    function _envUint(string memory chain_, string memory key_) internal view returns (uint256) {
        bool isDebug = _isDebugLogLevel();

        if (isDebug) console2.log("  Checking in env.json for", key_, "on", chain_);
        string memory fullKey = string.concat(".current.", chain_, ".", key_);
        uint256 num;
        bool keyExists = vm.keyExists(env, fullKey);

        if (keyExists) {
            num = env.readUint(fullKey);
            if (isDebug) console2.log("    %s: %s (from env.json)", key_, num);
        } else {
            if (isDebug) console2.log("    %s: *** NOT FOUND ***", key_);
        }

        return num;
    }

    function _envUint(string memory key_) internal view returns (uint256) {
        return _envUint(chain, key_);
    }

    function _envUintNotZero(
        string memory chain_,
        string memory key_
    ) internal view returns (uint256) {
        uint256 num = _envUint(chain_, key_);
        // solhint-disable-next-line custom-errors
        require(num > 0, string.concat("WithEnvironment: key '", key_, "' has zero value"));
        return num;
    }

    function _envUintNotZero(string memory key_) internal view returns (uint256) {
        return _envUintNotZero(chain, key_);
    }
}
