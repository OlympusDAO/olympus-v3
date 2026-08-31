// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";

import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_disableAllChains is CCIPBridgeConfigTest {
    /// @notice Asserts both buckets of a route hold the containment configuration.
    function _assertRouteContained(uint64 chainSelector_, string memory label_) internal view {
        _assertConfigEq(
            _toConfig(_outboundBucket(chainSelector_)),
            _containmentConfig(),
            string.concat(label_, ": outbound")
        );
        _assertConfigEq(
            _toConfig(_inboundBucket(chainSelector_)),
            _containmentConfig(),
            string.concat(label_, ": inbound")
        );
        assertTrue(config.isChainDisabled(chainSelector_), string.concat(label_, ": contained"));
    }

    // when the caller holds none of the four containment roles
    //   [X] it reverts with NotAuthorised
    // The fuzz excludes the emergency, admin, bridge admin and bridge rate limiter accounts
    // and the zero address.
    function test_whenCallerIsNotAuthorized_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenChainAdded {
        vm.assume(caller_ != emergency);
        vm.assume(caller_ != admin);
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != bridgeRateLimiter);
        vm.assume(caller_ != address(0));

        _expectRevertNotAuthorised();
        vm.prank(caller_);
        config.disableAllChains();
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with NotAuthorised
    // Role asymmetry: the operator configures routes but holds no containment authority
    function test_whenCallerIsConfigOperator_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
        givenChainAdded
    {
        _expectRevertNotAuthorised();
        vm.prank(operator);
        config.disableAllChains();
    }

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with Unauthorized carrying the config address
    // At least one route exists, so the pool call happens and fails on authority
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.Unauthorized.selector, address(config))
        );
        vm.prank(emergency);
        config.disableAllChains();

        assertFalse(config.isChainDisabled(CHAIN_SELECTOR_A), "the route should stay live");
    }

    // given no route is configured
    //   [X] it returns successfully
    //   [X] it emits no pool or config event
    // The early return: only the getSupportedChains read reaches the pool, and the write path
    // is never entered. The observable proof is log absence, which needs vm.recordLogs.
    function test_givenNoRoutesConfigured() public givenEnabled givenPoolOwnershipAccepted {
        assertEq(pool.getSupportedChains().length, 0, "no route should be configured");

        vm.recordLogs();
        vm.prank(emergency);
        config.disableAllChains();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countLogsFrom(logs, address(pool)), 0, "the pool should emit nothing");
        assertEq(_countLogsFrom(logs, address(config)), 0, "the config should emit nothing");
    }

    // given no route is configured
    //   given the pool is owned by an unrelated third party
    //     [X] it returns successfully
    // Pins the masking order: the early return answers before the pool would reject the
    // caller, so the zero-route no-op needs no pool authority at all.
    function test_givenNoRoutesConfigured_givenPoolOwnedByThirdParty()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        assertEq(pool.owner(), thirdParty, "the third party should own the pool");
        assertEq(pool.getSupportedChains().length, 0, "no route should be configured");

        vm.recordLogs();
        vm.prank(emergency);
        config.disableAllChains();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countLogsFrom(logs, address(pool)), 0, "the pool should emit nothing");
    }

    // when the caller holds the emergency role
    //   [X] both buckets of every route hold {true, 2, 1}
    //   [X] isChainDisabled reports true for every route
    //   [X] it emits RouteDisabled per route in the pool set order
    //   [X] the pool emits ChainConfigured per route
    // The main containment sweep over two routes
    function test_whenCallerIsEmergency()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenSecondChainAdded
    {
        uint64[] memory supportedChains = pool.getSupportedChains();
        assertEq(supportedChains.length, 2, "two routes should be configured");
        assertEq(supportedChains[0], CHAIN_SELECTOR_A, "route A should come first in the set");
        assertEq(supportedChains[1], CHAIN_SELECTOR_B, "route B should come second in the set");

        // The pool writes every route first, then the config emits one event per route in the
        // same order
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.ChainConfigured(
            CHAIN_SELECTOR_A,
            _containmentConfig(),
            _containmentConfig()
        );
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.ChainConfigured(
            CHAIN_SELECTOR_B,
            _containmentConfig(),
            _containmentConfig()
        );
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.RouteDisabled(CHAIN_SELECTOR_A);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.RouteDisabled(CHAIN_SELECTOR_B);
        vm.prank(emergency);
        config.disableAllChains();

        // Both routes were full at their capacities, so every fill clamps to min(2, tokens) = 2
        _assertBucket(_outboundBucket(CHAIN_SELECTOR_A), true, 2, 1, 2, "route A outbound");
        _assertBucket(_inboundBucket(CHAIN_SELECTOR_A), true, 2, 1, 2, "route A inbound");
        _assertBucket(_outboundBucket(CHAIN_SELECTOR_B), true, 2, 1, 2, "route B outbound");
        _assertBucket(_inboundBucket(CHAIN_SELECTOR_B), true, 2, 1, 2, "route B inbound");
        assertTrue(config.isChainDisabled(CHAIN_SELECTOR_A), "route A should be contained");
        assertTrue(config.isChainDisabled(CHAIN_SELECTOR_B), "route B should be contained");
    }

    // when the caller holds the admin role
    //   [X] it contains every route
    function test_whenCallerIsAdmin()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenSecondChainAdded
    {
        vm.prank(admin);
        config.disableAllChains();

        _assertRouteContained(CHAIN_SELECTOR_A, "route A");
        _assertRouteContained(CHAIN_SELECTOR_B, "route B");
    }

    // when the caller holds the bridge admin role
    //   [X] it contains every route
    function test_whenCallerIsBridgeAdmin()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenSecondChainAdded
    {
        vm.prank(bridgeAdmin);
        config.disableAllChains();

        _assertRouteContained(CHAIN_SELECTOR_A, "route A");
        _assertRouteContained(CHAIN_SELECTOR_B, "route B");
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it contains every route
    function test_whenCallerIsBridgeRateLimiter()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenSecondChainAdded
    {
        vm.prank(bridgeRateLimiter);
        config.disableAllChains();

        _assertRouteContained(CHAIN_SELECTOR_A, "route A");
        _assertRouteContained(CHAIN_SELECTOR_B, "route B");
    }

    // given the policy is disabled
    //   [X] it contains every route
    // No givenEnabled modifier exists: the emergency sweep survives the freeze
    function test_givenPolicyDisabled()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenDisabled
    {
        assertFalse(config.isEnabled(), "the policy should be disabled");

        vm.prank(emergency);
        config.disableAllChains();

        _assertRouteContained(CHAIN_SELECTOR_A, "route A");
    }

    // given the policy was deactivated in the kernel
    //   [X] it contains every route
    function test_givenPolicyDeactivatedInKernel()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPolicyDeactivatedInKernel
    {
        assertFalse(config.isActive(), "the policy should be deactivated in the kernel");

        vm.prank(emergency);
        config.disableAllChains();

        _assertRouteContained(CHAIN_SELECTOR_A, "route A");
    }

    // given some routes are already contained
    //   [X] it proceeds for all and every route ends contained
    // The idempotent mix: one contained route, one live route
    function test_givenSomeRoutesAlreadyContained()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenSecondChainAdded
        givenRouteContained
    {
        assertTrue(config.isChainDisabled(CHAIN_SELECTOR_A), "route A should start contained");
        assertFalse(config.isChainDisabled(CHAIN_SELECTOR_B), "route B should start live");

        vm.prank(emergency);
        config.disableAllChains();

        _assertRouteContained(CHAIN_SELECTOR_A, "route A");
        _assertRouteContained(CHAIN_SELECTOR_B, "route B");
    }

    // given a single route is configured
    //   [X] it contains the route and emits one RouteDisabled
    function test_givenSingleRoute()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.recordLogs();
        vm.prank(emergency);
        config.disableAllChains();

        _assertRouteContained(CHAIN_SELECTOR_A, "route A");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            _countLogs(logs, address(config), ICCIPBridgeConfig.RouteDisabled.selector),
            1,
            "the config should emit RouteDisabled exactly once"
        );
    }

    // given many routes are configured
    //   [X] it contains every route in one pool call
    // The linear-cost case (five routes); needs the many-routes builder
    function test_givenManyRoutes() public givenEnabled givenPoolOwnershipAccepted {
        uint64[] memory selectors = _addRoutes(5);
        assertEq(pool.getSupportedChains().length, 5, "five routes should be configured");

        vm.recordLogs();
        vm.prank(emergency);
        config.disableAllChains();

        for (uint256 i; i < selectors.length; ++i) {
            _assertRouteContained(selectors[i], "route");
        }

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            _countLogs(logs, address(config), ICCIPBridgeConfig.RouteDisabled.selector),
            5,
            "the config should emit one RouteDisabled per route"
        );
    }

    // given the pool is owned by a third party and the config is the rate limit admin
    //   [X] it contains every route
    function test_givenConfigIsRateLimitAdminOnly()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
        givenPoolOwnedByThirdParty
        givenConfigIsRateLimitAdmin
    {
        assertEq(pool.owner(), thirdParty, "the third party should own the pool");

        vm.prank(emergency);
        config.disableAllChains();

        _assertRouteContained(CHAIN_SELECTOR_A, "route A");
    }

    // given a route was added after a containment sweep
    //   [X] the new route starts with its supplied live limits
    // Containment is not sticky: no flag survives to catch later routes
    function test_givenRouteAddedAfterContainment()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenChainAdded
    {
        vm.prank(emergency);
        config.disableAllChains();
        _assertRouteContained(CHAIN_SELECTOR_A, "route A");

        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = REMOTE_POOL_B;
        vm.prank(admin);
        config.addChain(
            _chainUpdate(
                CHAIN_SELECTOR_B,
                remotePools,
                REMOTE_TOKEN_B,
                _defaultOutboundConfig(),
                _defaultInboundConfig()
            )
        );

        // The new route starts full at its supplied capacities, untouched by the earlier sweep
        _assertBucket(
            _outboundBucket(CHAIN_SELECTOR_B),
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            DEFAULT_OUTBOUND_RATE,
            DEFAULT_OUTBOUND_CAPACITY,
            "route B outbound"
        );
        assertFalse(config.isChainDisabled(CHAIN_SELECTOR_B), "route B should start live");
        assertTrue(config.isChainDisabled(CHAIN_SELECTOR_A), "route A should stay contained");
    }
}
