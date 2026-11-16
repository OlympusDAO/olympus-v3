// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Test} from "@forge-std-1.16.2/Test.sol";

import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";

import {CCIPConfigLibHarness} from "src/test/scripts/ops/lib/mocks/CCIPConfigLibHarness.sol";

/// @notice Shared rig of the `CCIPConfigLib` suites: an inline `env.json` fixture with one
///         local chain, one EVM remote chain and one SVM remote chain, whose config block and
///         route entries every test composes, behind a harness that exposes the library's
///         desired-state readers as external calls.
abstract contract CCIPConfigLibTest is Test {
    // =======================================================================
    // Constants
    // =======================================================================

    string internal constant LOCAL_CHAIN = "local";
    string internal constant EVM_CHAIN = "remote";
    string internal constant SVM_CHAIN = "solana";
    string internal constant CONFIG_PATH = ".current.local.olympus.config.CCIPTokenPoolConfig";

    uint64 internal constant EVM_SELECTOR = 4949039107694359620;
    uint64 internal constant SVM_SELECTOR = 124615329519749607;

    uint32 internal constant GRACE_PERIOD = 259_200;
    uint48 internal constant TIMELOCK_DELAY = 86_400;

    /// @notice The bound of the desired timelock delay, the values of the library constants.
    uint48 internal constant MIN_TIMELOCK_DELAY = 1 days;
    uint48 internal constant MAX_TIMELOCK_DELAY = 30 days;

    /// @notice The floor of an EVM periphery gas limit, the value of the library constant.
    uint32 internal constant GAS_LIMIT_FLOOR = 275_000;

    /// @notice The smallest EVM remote address the library accepts, the value of the library
    ///         constant.
    uint256 internal constant MIN_EVM_REMOTE_ADDRESS = 1024;

    uint128 internal constant OUT_CAPACITY = 100_000e9;
    uint128 internal constant OUT_RATE = 1_157_407_407;
    uint128 internal constant IN_CAPACITY = 55_000e9;
    uint128 internal constant IN_RATE = 636_574_074;

    /// @notice The live Solana OHM mint and pool, as base58 strings.
    string internal constant SVM_OHM = "2Xva1NeLRuBFdK41gEuXqgeWtnKKDve9PKeCnMEpNG6K";
    string internal constant SVM_POOL = "4N7bZnVSC1GE27vo2Bv6kG983brwhT68BGsLuzH5nTQp";

    bytes32 internal constant SVM_RECEIVER =
        0x1111111111111111111111111111111111111111111111111111111111111111;

    // =======================================================================
    // State
    // =======================================================================

    CCIPConfigLibHarness internal harness;
    address internal rebalancer;
    address internal rateLimitAdmin;
    address internal remoteOhm;
    address internal remotePool;
    address internal remoteBridge;

    // =======================================================================
    // setUp
    // =======================================================================

    function setUp() public virtual {
        harness = new CCIPConfigLibHarness();
        vm.label(address(harness), "CCIPConfigLibHarness");
        rebalancer = makeAddr("rebalancer");
        rateLimitAdmin = makeAddr("rateLimitAdmin");
        remoteOhm = makeAddr("remoteOhm");
        remotePool = makeAddr("remotePool");
        remoteBridge = makeAddr("remoteBridge");
    }

    // =======================================================================
    // Helpers: fixtures
    // =======================================================================

    /// @notice The whole `env.json`: the local chain with `localConfig_` as the content of its
    ///         `olympus.config` object, the EVM remote chain with its selector, OHM, burn/mint
    ///         pool and periphery, and the SVM remote chain with its selector, mint and pool.
    function _env(string memory localConfig_) internal view returns (string memory env) {
        return
            string.concat(
                '{"current":{"local":{"olympus":{"config":{',
                localConfig_,
                '}}},"remote":{"external":{"ccip":{"ChainSelector":"',
                vm.toString(uint256(EVM_SELECTOR)),
                '"}},"olympus":{"legacy":{"OHM":"',
                vm.toString(remoteOhm),
                '"},"policies":{"CCIPBurnMintTokenPool":"',
                vm.toString(remotePool),
                '"},"periphery":{"CCIPCrossChainBridge":"',
                vm.toString(remoteBridge),
                '"}}},"solana":{"external":{"ccip":{"ChainSelector":"',
                vm.toString(uint256(SVM_SELECTOR)),
                '"}},"olympus":{"legacy":{"OHM":"',
                SVM_OHM,
                '"},"periphery":{"TokenPool":"',
                SVM_POOL,
                '"}}}}}'
            );
    }

    /// @notice The `CCIPTokenPoolConfig` block with the given periods and the rig's addresses.
    function _configBlock(
        uint256 gracePeriod_,
        uint256 timelockDelay_
    ) internal view returns (string memory block_) {
        return
            string.concat(
                '"CCIPTokenPoolConfig":{"gracePeriod":',
                vm.toString(gracePeriod_),
                ',"timelockDelay":',
                vm.toString(timelockDelay_),
                ',"rebalancer":"',
                vm.toString(rebalancer),
                '","rateLimitAdmin":"',
                vm.toString(rateLimitAdmin),
                '"}'
            );
    }

    /// @notice The `CCIP` block with `entries_` as the content of its `routes` object.
    function _routesBlock(string memory entries_) internal pure returns (string memory block_) {
        return string.concat('"CCIP":{"routes":{', entries_, "}}");
    }

    /// @notice One member of a JSON object.
    function _entry(
        string memory name_,
        string memory value_
    ) internal pure returns (string memory entry) {
        return string.concat('"', name_, '":', value_);
    }

    /// @notice Two members of a JSON object.
    function _entries(
        string memory first_,
        string memory second_
    ) internal pure returns (string memory entries) {
        return string.concat(first_, ",", second_);
    }

    /// @notice A rate limiter block.
    function _limitBlock(
        bool isEnabled_,
        uint256 capacity_,
        uint256 rate_
    ) internal pure returns (string memory block_) {
        return
            string.concat(
                '{"isEnabled":',
                isEnabled_ ? "true" : "false",
                ',"capacity":"',
                vm.toString(capacity_),
                '","rate":"',
                vm.toString(rate_),
                '"}'
            );
    }

    /// @notice An enabled route entry with the rig's limits and `extra_` appended inside the
    ///         object, as `,"key":value` text.
    function _routeBlock(string memory extra_) internal pure returns (string memory block_) {
        return
            _routeBlockWithLimits(
                _limitBlock(true, OUT_CAPACITY, OUT_RATE),
                _limitBlock(true, IN_CAPACITY, IN_RATE),
                extra_
            );
    }

    /// @notice An enabled route entry with the given limiter blocks and `extra_` appended
    ///         inside the object, as `,"key":value` text.
    function _routeBlockWithLimits(
        string memory outbound_,
        string memory inbound_,
        string memory extra_
    ) internal pure returns (string memory block_) {
        return
            string.concat(
                '{"enabled":true,"outboundRateLimit":',
                outbound_,
                ',"inboundRateLimit":',
                inbound_,
                extra_,
                "}"
            );
    }

    /// @notice A route entry marked for removal, with `extra_` appended inside the object.
    function _removalBlock(string memory extra_) internal pure returns (string memory block_) {
        return string.concat('{"enabled":false', extra_, "}");
    }

    /// @notice An `env.json` whose local chain declares the config block alone.
    function _envWithConfig(
        uint256 gracePeriod_,
        uint256 timelockDelay_
    ) internal view returns (string memory env) {
        return _env(_configBlock(gracePeriod_, timelockDelay_));
    }

    /// @notice An `env.json` whose local chain declares the routes alone.
    function _envWithRoutes(string memory entries_) internal view returns (string memory env) {
        return _env(_routesBlock(entries_));
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
        _expectRevertMessage(string.concat("CCIPConfigLib: missing env.json key ", path_));
    }

    // =======================================================================
    // Assertions
    // =======================================================================

    function _assertConfig(
        ICCIPRateLimiter.Config memory actual_,
        bool isEnabled_,
        uint128 capacity_,
        uint128 rate_,
        string memory label_
    ) internal pure {
        assertEq(actual_.isEnabled, isEnabled_, string.concat(label_, ".isEnabled"));
        assertEq(actual_.capacity, capacity_, string.concat(label_, ".capacity"));
        assertEq(actual_.rate, rate_, string.concat(label_, ".rate"));
    }
}
