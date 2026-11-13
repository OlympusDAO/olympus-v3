// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: a failed `require` is meant to abort the whole run with
// its message.
// forge-lint: disable-start(custom-errors)

// Scripting
import {VmSafe} from "@forge-std-1.16.2/Vm.sol";
import {stdJson} from "@forge-std-1.16.2/StdJson.sol";

/// @title BackingOracleConfigLib
/// @notice Reads the desired state of the BackingOracle from `env.json` for the desired-state
///         tooling.
/// @dev The desired state of a chain lives under `current.<chain>.olympus.config.BackingOracle`:
///      - `backing` is the desired backing value (USD per OHM, 18 decimals).
///      The read fails closed: a missing key and a zero value revert with a message naming the
///      key. The oracle rejects a zero value in `enable` and in `setBacking`
///      (`BackingOracle_ZeroBacking`). The bound of one update relative to the live value is not
///      checked here: the library reads `env.json` only, and the batches call
///      `validateSetBacking` of the oracle.
library BackingOracleConfigLib {
    using stdJson for string;

    // ========== CONSTANTS ========== //

    VmSafe internal constant _VM = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant BACKING_KEY = "olympus.config.BackingOracle.backing";

    // ========== DESIRED STATE ========== //

    /// @notice Reads the desired backing value of a chain.
    /// @param env_ The content of `env.json`.
    /// @param chain_ The `env.json` name of the chain.
    /// @return backing The desired backing value (USD per OHM, 18 decimals); never zero.
    function desiredBacking(
        string memory env_,
        string memory chain_
    ) internal view returns (uint256 backing) {
        string memory key = backingPath(chain_);
        require(
            _VM.keyExistsJson(env_, key),
            string.concat("BackingOracleConfigLib: missing env.json key ", key)
        );
        backing = env_.readUint(key);
        require(
            backing != 0,
            string.concat(
                "BackingOracleConfigLib: the value of ",
                key,
                " is zero; the oracle rejects a zero backing"
            )
        );
    }

    /// @notice Returns the `env.json` path of the desired backing value of a chain.
    /// @param chain_ The `env.json` name of the chain.
    /// @return path The path, from the root of `env.json`.
    function backingPath(string memory chain_) internal pure returns (string memory path) {
        return string.concat(".current.", chain_, ".", BACKING_KEY);
    }
}

// forge-lint: disable-end(custom-errors)
