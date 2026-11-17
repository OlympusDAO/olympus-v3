// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Test
import {Vm} from "@forge-std-1.16.2/Vm.sol";

// Libraries
import {BackingOracleConfigLib} from "src/scripts/ops/lib/BackingOracleConfigLib.sol";
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";

/// @title YieldRepurchaseFacilityV2EnvFixture
/// @notice Reads the desired state of the YieldRepurchaseFacilityV2 launch from an `env.json`
///         and writes it back as a minimal `env.json`: the keys of one chain that
///         `YieldRepurchaseFacilityV2ConfigLib` and `BackingOracleConfigLib` read, and nothing
///         else. A test changes one member of the state and renders the file a proposal or a
///         deployment would read in that case.
library YieldRepurchaseFacilityV2EnvFixture {
    Vm internal constant _VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice The desired state of the launch.
    /// @param config The desired state of the facility stack.
    /// @param backing The desired backing value of the oracle (USD per OHM, 18 decimals).
    /// @param usdeUsdPriceFeed The USDe/USD price feed.
    struct State {
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig config;
        uint256 backing;
        address usdeUsdPriceFeed;
    }

    /// @notice Reads the desired state of a chain through the two libraries.
    function read(
        string memory env_,
        string memory chain_
    ) internal view returns (State memory state) {
        state.config = YieldRepurchaseFacilityV2ConfigLib.desiredConfig(env_, chain_);
        state.backing = BackingOracleConfigLib.desiredBacking(env_, chain_);
        state.usdeUsdPriceFeed = YieldRepurchaseFacilityV2ConfigLib.usdeUsdPriceFeed(env_, chain_);
    }

    /// @notice Renders the state as an `env.json` with one chain.
    /// @dev The backing vault is named after the declared asset that holds its address; a
    ///      state whose backing vault is no declared asset renders the name `undeclared`,
    ///      which the library rejects.
    function toJson(
        State memory state_,
        string memory chain_
    ) internal pure returns (string memory json) {
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig memory config = state_.config;

        string memory tokens;
        string memory assets;
        string memory backingVault = "undeclared";
        for (uint256 i = 0; i < config.assets.length; ++i) {
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory asset = config.assets[i];
            tokens = _join(tokens, _member(asset.name, _quoted(_VM.toString(asset.vault))));
            assets = _join(
                assets,
                _member(
                    asset.name,
                    string.concat(
                        "{",
                        _member("enabled", asset.enabled ? "true" : "false"),
                        ",",
                        _member("sellShares", asset.sellShares ? "true" : "false"),
                        ",",
                        _member("yieldBuybackShare", _quoted(asset.yieldBuybackShare)),
                        "}"
                    )
                )
            );
            if (asset.vault == config.backingVault) backingVault = asset.name;
        }

        string memory clearinghouses;
        for (uint256 i = 0; i < config.clearinghouses.length; ++i) {
            clearinghouses = _join(
                clearinghouses,
                string.concat(
                    "{",
                    _member(
                        "address",
                        _quoted(_VM.toString(config.clearinghouses[i].clearinghouse))
                    ),
                    ",",
                    _member("included", config.clearinghouses[i].included ? "true" : "false"),
                    ",",
                    _member("offset", _quoted(config.clearinghouses[i].offset)),
                    "}"
                )
            );
        }

        string memory facility = string.concat(
            "{",
            _member("assets", string.concat("{", assets, "}")),
            ",",
            _member("backingVault", _quoted(backingVault)),
            ",",
            _member("clearinghouses", string.concat("[", clearinghouses, "]")),
            ",",
            _member("gracePeriod", _quoted(uint256(config.parameters.gracePeriod))),
            ",",
            _member("initialDiscount", _quoted(config.parameters.initialDiscount)),
            ",",
            _member("maxPricePremium", _quoted(config.parameters.maxPricePremium)),
            ",",
            _member("stepGasLimit", _quoted(uint256(config.parameters.stepGasLimit))),
            ",",
            _member("timelockDelay", _quoted(uint256(config.parameters.timelockDelay))),
            "}"
        );

        return
            string.concat(
                '{"current":{"',
                chain_,
                '":{"external":{"chainlink":{',
                _member("usdeUsdPriceFeed", _quoted(_VM.toString(state_.usdeUsdPriceFeed))),
                '},"tokens":{',
                tokens,
                '}},"olympus":{"config":{"BackingOracle":{',
                _member("backing", _quoted(state_.backing)),
                '},"YieldRepurchaseFacilityV2":',
                facility,
                "}}}}}"
            );
    }

    /// @notice One member of a JSON object, with the value given as JSON text.
    function _member(
        string memory name_,
        string memory value_
    ) private pure returns (string memory member) {
        return string.concat('"', name_, '":', value_);
    }

    /// @notice An unsigned integer as a JSON string, the form `env.json` uses for the values
    ///         that exceed the safe integer range of JSON tooling.
    function _quoted(uint256 value_) private pure returns (string memory text) {
        return string.concat('"', _VM.toString(value_), '"');
    }

    function _quoted(string memory value_) private pure returns (string memory text) {
        return string.concat('"', value_, '"');
    }

    /// @notice Joins two comma-separated lists; an empty list adds nothing.
    function _join(
        string memory first_,
        string memory second_
    ) private pure returns (string memory joined) {
        if (bytes(first_).length == 0) return second_;
        return string.concat(first_, ",", second_);
    }
}
