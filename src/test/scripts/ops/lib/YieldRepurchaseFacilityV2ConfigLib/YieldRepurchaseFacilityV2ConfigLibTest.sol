// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Test} from "@forge-std-1.16.2/Test.sol";

import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/libraries/internal/YieldRepurchaseFacilityV2Constants.sol";
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";

import {YieldRepurchaseFacilityV2ConfigLibHarness} from "src/test/scripts/ops/lib/mocks/YieldRepurchaseFacilityV2ConfigLibHarness.sol";
import {YieldRepurchaseFacilityV2ValidationLibHarness} from "src/test/scripts/ops/lib/mocks/YieldRepurchaseFacilityV2ValidationLibHarness.sol";

/// @notice Shared rig of the `YieldRepurchaseFacilityV2ConfigLib` suites: an inline `env.json`
///         fixture with one chain, whose facility config block, token addresses and price feed
///         every test composes, behind a harness that exposes the readers of the library as
///         external calls, and a harness of the value rules the facility applies.
abstract contract YieldRepurchaseFacilityV2ConfigLibTest is Test {
    // =======================================================================
    // Constants
    // =======================================================================

    string internal constant CHAIN = "local";
    string internal constant CONFIG_PATH =
        ".current.local.olympus.config.YieldRepurchaseFacilityV2";
    string internal constant ASSETS_PATH =
        ".current.local.olympus.config.YieldRepurchaseFacilityV2.assets";
    string internal constant CLEARINGHOUSES_PATH =
        ".current.local.olympus.config.YieldRepurchaseFacilityV2.clearinghouses";
    string internal constant TOKENS_PATH = ".current.local.external.tokens";
    string internal constant FEED_PATH = ".current.local.external.chainlink.usdeUsdPriceFeed";

    string internal constant SUSDS = "sUSDS";
    string internal constant SUSDE = "sUSDe";

    /// @notice Valid values of the scalar parameters, the launch values of the facility.
    uint256 internal constant GRACE_PERIOD = 432_000;
    uint256 internal constant STEP_GAS_LIMIT = 2_000_000;
    uint256 internal constant TIMELOCK_DELAY = 86_400;
    uint256 internal constant INITIAL_DISCOUNT = 3e16;
    uint256 internal constant MAX_PRICE_PREMIUM = 10e16;

    /// @notice The bounds the facility enforces, read from its constants.
    uint256 internal constant ONE_HUNDRED_PERCENT =
        YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT;
    uint256 internal constant MAX_GRACE_PERIOD =
        YieldRepurchaseFacilityV2Constants.MAX_GRACE_PERIOD;
    uint256 internal constant MIN_STEP_GAS_LIMIT =
        YieldRepurchaseFacilityV2Constants.MIN_STEP_GAS_LIMIT;
    uint256 internal constant MAX_STEP_GAS_LIMIT =
        YieldRepurchaseFacilityV2Constants.MAX_STEP_GAS_LIMIT;
    uint256 internal constant MAX_PRICE_PREMIUM_LIMIT =
        YieldRepurchaseFacilityV2Constants.MAX_PRICE_PREMIUM_LIMIT;

    /// @notice The bound of the timelock delay, as the library declares it.
    uint256 internal constant MIN_TIMELOCK_DELAY =
        YieldRepurchaseFacilityV2ConfigLib.MIN_TIMELOCK_DELAY;
    uint256 internal constant MAX_TIMELOCK_DELAY =
        YieldRepurchaseFacilityV2ConfigLib.MAX_TIMELOCK_DELAY;

    // =======================================================================
    // State
    // =======================================================================

    YieldRepurchaseFacilityV2ConfigLibHarness internal harness;
    YieldRepurchaseFacilityV2ValidationLibHarness internal validation;

    address internal susds;
    address internal susde;
    address internal clearinghouseA;
    address internal clearinghouseB;
    address internal clearinghouseC;
    address internal usdeFeed;

    // =======================================================================
    // setUp
    // =======================================================================

    function setUp() public virtual {
        harness = new YieldRepurchaseFacilityV2ConfigLibHarness();
        vm.label(address(harness), "YieldRepurchaseFacilityV2ConfigLibHarness");
        validation = new YieldRepurchaseFacilityV2ValidationLibHarness();
        vm.label(address(validation), "YieldRepurchaseFacilityV2ValidationLibHarness");

        susds = makeAddr("sUSDS");
        susde = makeAddr("sUSDe");
        clearinghouseA = makeAddr("clearinghouseA");
        clearinghouseB = makeAddr("clearinghouseB");
        clearinghouseC = makeAddr("clearinghouseC");
        usdeFeed = makeAddr("usdeFeed");
    }

    // =======================================================================
    // Helpers: JSON fragments
    // =======================================================================

    /// @notice One member of a JSON object, with the value given as JSON text.
    function _member(
        string memory name_,
        string memory value_
    ) internal pure returns (string memory member) {
        return string.concat('"', name_, '":', value_);
    }

    /// @notice An unsigned integer as a JSON string, the form `env.json` uses for the values
    ///         that exceed the safe integer range of JSON tooling.
    function _quoted(uint256 value_) internal pure returns (string memory text) {
        return string.concat('"', vm.toString(value_), '"');
    }

    function _quoted(address value_) internal pure returns (string memory text) {
        return string.concat('"', vm.toString(value_), '"');
    }

    function _quoted(string memory value_) internal pure returns (string memory text) {
        return string.concat('"', value_, '"');
    }

    function _bool(bool value_) internal pure returns (string memory text) {
        return value_ ? "true" : "false";
    }

    /// @notice Joins two comma-separated lists of members or of array entries; an empty list
    ///         adds nothing.
    function _join(
        string memory first_,
        string memory second_
    ) internal pure returns (string memory joined) {
        if (bytes(first_).length == 0) return second_;
        if (bytes(second_).length == 0) return first_;
        return string.concat(first_, ",", second_);
    }

    // =======================================================================
    // Helpers: fixtures
    // =======================================================================

    /// @notice The whole `env.json`: the chain with `config_` as the content of its facility
    ///         config object, `tokens_` as the content of `external.tokens` and `chainlink_`
    ///         as the content of `external.chainlink`.
    function _env(
        string memory config_,
        string memory tokens_,
        string memory chainlink_
    ) internal pure returns (string memory env) {
        return
            string.concat(
                '{"current":{"local":{"external":{"chainlink":{',
                chainlink_,
                '},"tokens":{',
                tokens_,
                '}},"olympus":{"config":{"YieldRepurchaseFacilityV2":{',
                config_,
                "}}}}}}"
            );
    }

    /// @notice The five scalar members of the facility config object.
    function _parameterMembers(
        uint256 gracePeriod_,
        uint256 stepGasLimit_,
        uint256 timelockDelay_,
        uint256 initialDiscount_,
        uint256 maxPricePremium_
    ) internal pure returns (string memory members) {
        members = _member("gracePeriod", _quoted(gracePeriod_));
        members = _join(members, _member("stepGasLimit", _quoted(stepGasLimit_)));
        members = _join(members, _member("timelockDelay", _quoted(timelockDelay_)));
        members = _join(members, _member("initialDiscount", _quoted(initialDiscount_)));
        members = _join(members, _member("maxPricePremium", _quoted(maxPricePremium_)));
    }

    /// @notice The five scalar members with the valid values of the rig.
    function _validParameterMembers() internal pure returns (string memory members) {
        return
            _parameterMembers(
                GRACE_PERIOD,
                STEP_GAS_LIMIT,
                TIMELOCK_DELAY,
                INITIAL_DISCOUNT,
                MAX_PRICE_PREMIUM
            );
    }

    /// @notice One entry of the `assets` object.
    function _asset(
        string memory name_,
        bool enabled_,
        bool sellShares_,
        uint256 yieldBuybackShare_
    ) internal pure returns (string memory entry) {
        return
            _member(
                name_,
                string.concat(
                    "{",
                    _member("enabled", _bool(enabled_)),
                    ",",
                    _member("sellShares", _bool(sellShares_)),
                    ",",
                    _member("yieldBuybackShare", _quoted(yieldBuybackShare_)),
                    "}"
                )
            );
    }

    /// @notice The `assets` and `backingVault` members of the facility config object.
    function _assetMembers(
        string memory entries_,
        string memory backingVaultName_
    ) internal pure returns (string memory members) {
        return
            _join(
                _member("assets", string.concat("{", entries_, "}")),
                _member("backingVault", _quoted(backingVaultName_))
            );
    }

    /// @notice The asset members of the rig: sUSDS as the backing vault and sUSDe selling
    ///         shares, both enabled with a full yield buyback share.
    function _validAssetMembers() internal pure returns (string memory members) {
        return
            _assetMembers(
                _join(
                    _asset(SUSDS, true, false, ONE_HUNDRED_PERCENT),
                    _asset(SUSDE, true, true, ONE_HUNDRED_PERCENT)
                ),
                SUSDS
            );
    }

    /// @notice The `external.tokens` members of the rig.
    function _validTokens() internal view returns (string memory members) {
        return _join(_member(SUSDS, _quoted(susds)), _member(SUSDE, _quoted(susde)));
    }

    /// @notice One entry of the `clearinghouses` array.
    function _clearinghouse(
        address clearinghouse_,
        bool included_,
        uint256 offset_
    ) internal pure returns (string memory entry) {
        return
            string.concat(
                "{",
                _member("address", _quoted(clearinghouse_)),
                ",",
                _member("included", _bool(included_)),
                ",",
                _member("offset", _quoted(offset_)),
                "}"
            );
    }

    /// @notice The `clearinghouses` member of the facility config object.
    function _clearinghouseMember(
        string memory entries_
    ) internal pure returns (string memory member) {
        return _member("clearinghouses", string.concat("[", entries_, "]"));
    }

    /// @notice The Clearinghouse member of the rig: two included entries and one that is not,
    ///         each with its own offset.
    function _validClearinghouseMember() internal view returns (string memory member) {
        string memory entries = _clearinghouse(clearinghouseA, true, 0);
        entries = _join(entries, _clearinghouse(clearinghouseB, true, 2_000_000e18));
        entries = _join(entries, _clearinghouse(clearinghouseC, false, 5));
        return _clearinghouseMember(entries);
    }

    /// @notice An `env.json` whose facility config object holds `config_`, next to the tokens
    ///         of the rig.
    function _envWithConfig(string memory config_) internal view returns (string memory env) {
        return _env(config_, _validTokens(), "");
    }

    /// @notice An `env.json` with every valid block of the rig.
    function _validEnv() internal view returns (string memory env) {
        string memory config = _join(_validParameterMembers(), _validAssetMembers());
        config = _join(config, _validClearinghouseMember());
        return _env(config, _validTokens(), _member("usdeUsdPriceFeed", _quoted(usdeFeed)));
    }

    // =======================================================================
    // Helpers: reverts
    // =======================================================================

    /// @notice Expects an `Error(string)` revert with exactly `message_`. The library reverts
    ///         with `require` strings by design (a script library), so the message is the data.
    function _expectRevertMessage(string memory message_) internal {
        vm.expectRevert(bytes(message_));
    }

    function _expectRevertMissingKey(string memory path_) internal {
        _expectRevertMessage(
            string.concat("YieldRepurchaseFacilityV2ConfigLib: missing env.json key ", path_)
        );
    }

    function _expectRevertZeroAddress(string memory path_) internal {
        _expectRevertMessage(
            string.concat("YieldRepurchaseFacilityV2ConfigLib: zero address for ", path_)
        );
    }

    /// @notice Expects the revert of a value outside its bound: the key, the value and the
    ///         bound as the library words it.
    function _expectRevertOutOfBound(
        string memory path_,
        uint256 value_,
        string memory bound_
    ) internal {
        _expectRevertMessage(
            string.concat(
                "YieldRepurchaseFacilityV2ConfigLib: the value of ",
                path_,
                " is ",
                vm.toString(value_),
                "; ",
                bound_
            )
        );
    }

    // =======================================================================
    // Assertions
    // =======================================================================

    function _assertAsset(
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory actual_,
        string memory name_,
        address vault_,
        bool enabled_,
        bool sellShares_,
        uint256 yieldBuybackShare_,
        string memory label_
    ) internal pure {
        assertEq(actual_.name, name_, string.concat(label_, ".name"));
        assertEq(actual_.vault, vault_, string.concat(label_, ".vault"));
        assertEq(actual_.enabled, enabled_, string.concat(label_, ".enabled"));
        assertEq(actual_.sellShares, sellShares_, string.concat(label_, ".sellShares"));
        assertEq(
            actual_.yieldBuybackShare,
            yieldBuybackShare_,
            string.concat(label_, ".yieldBuybackShare")
        );
    }

    function _assertClearinghouse(
        YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory actual_,
        address clearinghouse_,
        bool included_,
        uint256 offset_,
        string memory label_
    ) internal pure {
        assertEq(actual_.clearinghouse, clearinghouse_, string.concat(label_, ".clearinghouse"));
        assertEq(actual_.included, included_, string.concat(label_, ".included"));
        assertEq(actual_.offset, offset_, string.concat(label_, ".offset"));
    }
}
