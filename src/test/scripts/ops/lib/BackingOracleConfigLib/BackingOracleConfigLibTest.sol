// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Test} from "@forge-std-1.16.2/Test.sol";

import {BackingOracleConfigLibHarness} from "src/test/scripts/ops/lib/mocks/BackingOracleConfigLibHarness.sol";

/// @notice Shared rig of the `BackingOracleConfigLib` suites: an inline `env.json` fixture with
///         one chain, whose `BackingOracle` config object every test composes, behind a harness
///         that exposes the readers of the library as external calls.
abstract contract BackingOracleConfigLibTest is Test {
    // =======================================================================
    // Constants
    // =======================================================================

    string internal constant CHAIN = "local";
    string internal constant BACKING_PATH = ".current.local.olympus.config.BackingOracle.backing";

    /// @notice A valid backing value: 12.04 USD per OHM, in 18 decimals (the launch value).
    uint256 internal constant BACKING = 12.04e18;

    // =======================================================================
    // State
    // =======================================================================

    BackingOracleConfigLibHarness internal harness;

    // =======================================================================
    // setUp
    // =======================================================================

    function setUp() public virtual {
        harness = new BackingOracleConfigLibHarness();
        vm.label(address(harness), "BackingOracleConfigLibHarness");
    }

    // =======================================================================
    // Helpers: fixtures
    // =======================================================================

    /// @notice The whole `env.json`: the chain with `oracle_` as the content of its
    ///         `BackingOracle` config object.
    function _env(string memory oracle_) internal pure returns (string memory env) {
        return
            string.concat(
                '{"current":{"local":{"olympus":{"config":{"BackingOracle":{',
                oracle_,
                "}}}}}}"
            );
    }

    /// @notice An `env.json` whose backing is `value_`, given as JSON text.
    function _envWithBacking(string memory value_) internal pure returns (string memory env) {
        return _env(string.concat('"backing":', value_));
    }

    /// @notice An unsigned integer as a JSON string.
    function _quoted(uint256 value_) internal pure returns (string memory text) {
        return string.concat('"', vm.toString(value_), '"');
    }

    // =======================================================================
    // Helpers: reverts
    // =======================================================================

    /// @notice Expects an `Error(string)` revert with exactly `message_`. The library reverts
    ///         with `require` strings by design (a script library), so the message is the data.
    function _expectRevertMessage(string memory message_) internal {
        vm.expectRevert(bytes(message_));
    }
}
