// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPBridgeConfigTimelock} from "src/policies/interfaces/bridge/ICCIPBridgeConfigTimelock.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {stdJson} from "@forge-std-1.16.2/StdJson.sol";

import {Kernel} from "src/Kernel.sol";
import {CCIPBridgeConfig} from "src/policies/bridge/CCIPBridgeConfig.sol";
import {CCIPBridgeConfigTimelock} from "src/policies/bridge/CCIPBridgeConfigTimelock.sol";

/// @notice Shared base of the CCIP migration fork tests. The suites replay the migration
///         procedures (the bootstrap of a chain, the config-pair replacement and the
///         pool-and-config-pair replacement) against the REAL deployed contracts of one chain, pinned at a
///         recent block: every authority is impersonated at its live address, everything the
///         procedure deploys is deployed by the test, and every gate, ordering constraint and
///         end state the procedure relies on is asserted against the live state.
/// @dev    Addresses come from `src/scripts/env.json` (the deployment's desired-state record),
///         read at run time so the tests follow redeployments without edits. Each network base
///         pins its own fork block, checks the live preconditions the procedures
///         assume, and fails loudly with a labelled require when the chain has moved in a way
///         that invalidates the procedure, rather than producing a misleading test failure.
///
///         The wording avoids the legacy "L2" label on purpose: the counterpart of Ethereum in
///         these procedures is any non-Ethereum EVM chain, whether or not it is a rollup.
abstract contract CCIPMigrationForkTestBase is Test {
    using stdJson for string;

    // ========== ENVIRONMENT ========== //

    /// @notice The raw contents of env.json; parsed lazily by the readers below.
    string internal _env;

    /// @notice The pair the running procedure deploys: the config policy and the config
    ///         timelock. The replacement suites additionally track the outgoing pair below.
    CCIPBridgeConfig internal config;
    CCIPBridgeConfigTimelock internal timelock;

    /// @notice The outgoing pair of a replacement procedure, captured from `config`/`timelock`
    ///         by `_promoteToOldPair` before the new pair is deployed over them.
    CCIPBridgeConfig internal oldConfig;
    CCIPBridgeConfigTimelock internal oldTimelock;

    /// @notice The action a replacement suite seeds in the outgoing timelock, so the
    ///         migration's cancellation step has something meaningful to cancel.
    uint64 internal seededActionId;

    /// @notice The deployment's standard timelock parameters (env.json records the same values
    ///         for every chain that has a config section; chains without one use these).
    uint48 internal constant STANDARD_TIMELOCK_DELAY = 1 days;
    uint32 internal constant STANDARD_GRACE_PERIOD = 3 days;

    function _loadEnv() internal {
        _env = vm.readFile("./src/scripts/env.json");
    }

    function _envAddress(string memory chain_, string memory key_) internal view returns (address) {
        return _env.readAddress(string.concat("$.current.", chain_, ".", key_));
    }

    function _envUint(string memory chain_, string memory key_) internal view returns (uint256) {
        return _env.readUint(string.concat("$.current.", chain_, ".", key_));
    }

    /// @notice The chain selector of a chain, per its external CCIP section.
    function _envChainSelector(string memory chain_) internal view returns (uint64) {
        // casting to 'uint64' is safe because CCIP chain selectors are uint64 values
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(_envUint(chain_, "external.ccip.ChainSelector"));
    }

    /// @notice One directional rate limiter configuration of a declared route.
    function _envRouteLimit(
        string memory chain_,
        string memory route_,
        string memory direction_
    ) internal view returns (ICCIPRateLimiter.Config memory) {
        string memory prefix = string.concat(
            "$.current.",
            chain_,
            ".olympus.config.CCIP.routes.",
            route_,
            ".",
            direction_
        );
        return
            ICCIPRateLimiter.Config({
                isEnabled: _env.readBool(string.concat(prefix, ".isEnabled")),
                // casting to 'uint128' is safe because the declared limits are OHM base units
                // far below the uint128 maximum
                // forge-lint: disable-next-line(unsafe-typecast)
                capacity: uint128(_env.readUint(string.concat(prefix, ".capacity"))),
                // forge-lint: disable-next-line(unsafe-typecast)
                rate: uint128(_env.readUint(string.concat(prefix, ".rate")))
            });
    }

    // ========== DEPLOYMENT ========== //

    /// @notice Deploys a config policy over a pool and a timelock over that config, the way
    ///         every procedure's deployment step does, and binds them to the `config` and
    ///         `timelock` variables.
    function _deployPair(Kernel kernel_, address pool_) internal {
        config = new CCIPBridgeConfig(kernel_, pool_, STANDARD_GRACE_PERIOD);
        vm.label(address(config), "newConfig");
        timelock = new CCIPBridgeConfigTimelock(
            kernel_,
            address(config),
            STANDARD_TIMELOCK_DELAY,
            STANDARD_GRACE_PERIOD
        );
        vm.label(address(timelock), "newTimelock");
    }

    /// @notice Rebinds the current pair as the outgoing one, so a replacement suite can
    ///         deploy the incoming pair into `config`/`timelock`.
    function _promoteToOldPair() internal {
        oldConfig = config;
        vm.label(address(oldConfig), "oldConfig");
        oldTimelock = timelock;
        vm.label(address(oldTimelock), "oldTimelock");
    }

    /// @notice Seeds one queued rate limit action in a timelock and records its id in
    ///         `seededActionId`, asserting the reservation landed. This is what the
    ///         cancellation step of every replacement procedure exists for.
    function _seedQueuedRateLimitAction(
        CCIPBridgeConfigTimelock timelock_,
        CCIPBridgeConfig config_,
        address proposer_,
        uint64 chainSelector_
    ) internal {
        (
            ICCIPRateLimiter.Config memory outbound,
            ICCIPRateLimiter.Config memory inbound
        ) = _serviceableRateLimits(config_.pool(), chainSelector_);
        vm.prank(proposer_);
        seededActionId = timelock_.queueSetChainRateLimits(chainSelector_, outbound, inbound);
        assertEq(
            timelock_.pendingActionId(timelock_.getRateLimitsKey(chainSelector_)),
            seededActionId,
            "seeding: the queued action should reserve the rate limits domain"
        );
    }

    /// @notice Rate limit values a queue or write for the route always accepts: the live
    ///         configurations when they are enabled, standard enabled values otherwise (a
    ///         disabled live bucket is a legacy direct-owner shape the config's validated
    ///         paths refuse to write back).
    function _serviceableRateLimits(
        address pool_,
        uint64 chainSelector_
    )
        internal
        view
        returns (ICCIPRateLimiter.Config memory outbound, ICCIPRateLimiter.Config memory inbound)
    {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(pool_);
        outbound = _toConfig(rigPool.getCurrentOutboundRateLimiterState(chainSelector_));
        inbound = _toConfig(rigPool.getCurrentInboundRateLimiterState(chainSelector_));
        if (!outbound.isEnabled) {
            outbound = ICCIPRateLimiter.Config({isEnabled: true, capacity: 10_000, rate: 100});
        }
        if (!inbound.isEnabled) {
            inbound = ICCIPRateLimiter.Config({isEnabled: true, capacity: 20_000, rate: 200});
        }
        return (outbound, inbound);
    }

    // ========== ROUTE OBSERVATION ========== //

    /// @notice The configuration fields of a bucket, without the volatile fill level and
    ///         refill timestamp, so digests stay stable across skipped time.
    function _toConfig(
        ICCIPRateLimiter.TokenBucket memory bucket_
    ) internal pure returns (ICCIPRateLimiter.Config memory) {
        return
            ICCIPRateLimiter.Config({
                isEnabled: bucket_.isEnabled,
                capacity: bucket_.capacity,
                rate: bucket_.rate
            });
    }

    /// @notice Digest of every route a pool serves: the selector set and, per route, the
    ///         remote token, the accepted remote pools and both bucket configurations. Fill
    ///         levels are excluded, so the digest is stable across time and the "the migration
    ///         leaves the routes untouched" claims compare cleanly.
    function _routeDigest(address pool_) internal view returns (bytes32) {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(pool_);
        uint64[] memory selectors = rigPool.getSupportedChains();
        bytes memory acc = abi.encode(selectors);
        for (uint256 i; i < selectors.length; ++i) {
            acc = bytes.concat(
                acc,
                abi.encode(
                    rigPool.getRemoteToken(selectors[i]),
                    rigPool.getRemotePools(selectors[i]),
                    _toConfig(rigPool.getCurrentOutboundRateLimiterState(selectors[i])),
                    _toConfig(rigPool.getCurrentInboundRateLimiterState(selectors[i]))
                )
            );
        }
        return keccak256(acc);
    }

    /// @notice Asserts every field of one route against expected values.
    function _assertRoute(
        address pool_,
        uint64 chainSelector_,
        bytes memory remoteToken_,
        ICCIPRateLimiter.Config memory outbound_,
        ICCIPRateLimiter.Config memory inbound_,
        string memory label_
    ) internal view {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(pool_);
        assertTrue(
            rigPool.isSupportedChain(chainSelector_),
            string.concat(label_, ": the route should exist")
        );
        assertEq(
            rigPool.getRemoteToken(chainSelector_),
            remoteToken_,
            string.concat(label_, ": remote token")
        );
        _assertConfigEq(
            _toConfig(rigPool.getCurrentOutboundRateLimiterState(chainSelector_)),
            outbound_,
            string.concat(label_, ": outbound")
        );
        _assertConfigEq(
            _toConfig(rigPool.getCurrentInboundRateLimiterState(chainSelector_)),
            inbound_,
            string.concat(label_, ": inbound")
        );
    }

    function _assertConfigEq(
        ICCIPRateLimiter.Config memory actual_,
        ICCIPRateLimiter.Config memory expected_,
        string memory label_
    ) internal pure {
        assertEq(actual_.isEnabled, expected_.isEnabled, string.concat(label_, ": isEnabled"));
        assertEq(actual_.capacity, expected_.capacity, string.concat(label_, ": capacity"));
        assertEq(actual_.rate, expected_.rate, string.concat(label_, ": rate"));
    }

    // ========== TRIAD END-STATE ASSERTIONS ========== //

    /// @notice Asserts the steady-state wiring every procedure must end in: the config policy
    ///         enabled and owning the pool, the timelock enabled and holding the operator
    ///         seat, and both active in the kernel.
    function _assertStackWired(
        Kernel kernel_,
        CCIPBridgeConfig config_,
        CCIPBridgeConfigTimelock timelock_,
        address pool_,
        string memory label_
    ) internal view {
        assertEq(config_.pool(), pool_, string.concat(label_, ": config pool binding"));
        assertEq(
            timelock_.config(),
            address(config_),
            string.concat(label_, ": timelock config binding")
        );
        assertTrue(config_.isEnabled(), string.concat(label_, ": config should be enabled"));
        assertTrue(timelock_.isEnabled(), string.concat(label_, ": timelock should be enabled"));
        assertEq(
            ICCIPTokenPoolAdmin(pool_).owner(),
            address(config_),
            string.concat(label_, ": the config should own the pool")
        );
        assertEq(
            config_.configOperator(),
            address(timelock_),
            string.concat(label_, ": the timelock should hold the operator seat")
        );
        assertTrue(
            kernel_.isPolicyActive(config_),
            string.concat(label_, ": the config should be active in the kernel")
        );
        assertTrue(
            kernel_.isPolicyActive(timelock_),
            string.concat(label_, ": the timelock should be active in the kernel")
        );
    }

    /// @notice Proves the steady-state authority model serves after a migration: the bridge
    ///         admin queues a rate limit change through the timelock, the delay elapses, and
    ///         anyone executes it. The queued values equal the live ones when those are
    ///         enabled, keeping the round trip state-neutral; a route whose live buckets are
    ///         disabled (a shape only legacy direct-owner tooling produces, which the config's
    ///         validated paths refuse to write back) is instead moved onto standard enabled
    ///         limits, which is exactly the write the real rollout performs next.
    function _assertTimelockPathServes(
        CCIPBridgeConfig config_,
        CCIPBridgeConfigTimelock timelock_,
        address bridgeAdmin_,
        uint64 chainSelector_
    ) internal {
        (
            ICCIPRateLimiter.Config memory outbound,
            ICCIPRateLimiter.Config memory inbound
        ) = _serviceableRateLimits(config_.pool(), chainSelector_);

        vm.prank(bridgeAdmin_);
        uint64 actionId = timelock_.queueSetChainRateLimits(chainSelector_, outbound, inbound);
        assertEq(
            timelock_.pendingActionId(timelock_.getRateLimitsKey(chainSelector_)),
            actionId,
            "steady state: the queued action should reserve the rate limits domain"
        );

        skip(timelock_.timelockDelay());
        address executor = makeAddr("permissionlessExecutor");
        vm.prank(executor);
        timelock_.executeQueuedAction(actionId);

        assertEq(
            timelock_.pendingActionId(timelock_.getRateLimitsKey(chainSelector_)),
            0,
            "steady state: the executed action should release its domain"
        );
    }

    // ========== REVERT EXPECTATION HELPERS ========== //

    function _expectRevertNotEnabled() internal {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    function _expectRevertNotDisabled() internal {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
    }

    function _expectRevertConfigNotActive(address config_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPBridgeConfigTimelock.CCIPBridgeConfigTimelock_ConfigNotActive.selector,
                config_
            )
        );
    }

    function _expectRevertMustBeProposedOwner() internal {
        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.MustBeProposedOwner.selector));
    }

    function _expectRevertChainAlreadyExists(uint64 chainSelector_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.ChainAlreadyExists.selector, chainSelector_)
        );
    }

    function _expectRevertPolicyAlreadyActivated(address policy_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(Kernel.Kernel_PolicyAlreadyActivated.selector, policy_)
        );
    }
}
