// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// Interfaces
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";

// Libraries
import {CCIPTokenPoolConfigKeyLib} from "src/policies/utils/CCIPTokenPoolConfigKeyLib.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {Actions} from "src/Kernel.sol";
import {CCIPTokenPoolConfig} from "src/policies/bridge/CCIPTokenPoolConfig.sol";
import {CCIPTokenPoolConfigTimelock} from "src/policies/bridge/CCIPTokenPoolConfigTimelock.sol";

import {CCIPTokenPoolConfigTimelockTest} from "./CCIPTokenPoolConfigTimelockTest.sol";

/// @notice The views over the key material of the timelock (`config` and the four domain
///         constants) and the shape of the keys it reserves. The timelock exposes no key getter:
///         the tests recompute the documented shape themselves and pin it against what the
///         reservations, the `ConfigStateQueued` events and the stored config states report.
///         The two parity tests pin that the keys the tooling derives through the library are
///         the keys the contract reserves.
contract CCIPTokenPoolConfigTimelockTests_KeyViews is CCIPTokenPoolConfigTimelockTest {
    // ========== FILE-LOCAL HELPERS ========== //

    /// @notice Queues an addChain action for the selector and asserts that the three keys the
    ///         base reserved, emitted and stored are the recomputed documented shape.
    function _assertChainActionReservesDocumentedKeys(uint64 selector_) internal {
        // The scoped keys in _configKeys order: rate limits, remote pools, route identity
        bytes32[] memory expectedKeys = new bytes32[](3);
        expectedKeys[0] = _rateLimitsKey(selector_);
        expectedKeys[1] = _remotePoolsKey(selector_);
        expectedKeys[2] = _routeIdentityKey(selector_);

        vm.recordLogs();
        uint64 actionId = _queueAddChainAction(selector_);

        _assertRouteKeysHeldBy(selector_, actionId, "after the queue");

        // The three ConfigStateQueued events carry the reserved key as the third topic, in
        // the _configKeys order
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 eventCount;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter != address(timelock) ||
                logs[i].topics[0] != IConfigTimelockBatchQueue.ConfigStateQueued.selector
            ) continue;
            assertEq(
                logs[i].topics[3],
                expectedKeys[eventCount],
                "the ConfigStateQueued event should carry the documented key"
            );
            ++eventCount;
        }
        assertEq(eventCount, 3, "exactly three ConfigStateQueued events should be emitted");

        for (uint256 i; i < expectedKeys.length; ++i) {
            (bytes32 storedKey, ) = timelock.getQueuedConfigState(actionId, 0, i);
            assertEq(
                storedKey,
                expectedKeys[i],
                "the stored config state key should equal the documented key"
            );
        }
    }

    // ========== TESTS ========== //

    // when config() is called
    //   [X] it reports the config policy address
    //   [X] the answer is identical before and after enable and disable transitions
    function test_config() public {
        assertEq(timelock.config(), address(config), "config() should report the bound config");

        vm.prank(admin);
        timelock.enable("");
        assertEq(timelock.config(), address(config), "config() should be constant while enabled");

        vm.prank(admin);
        timelock.disable("");
        assertEq(timelock.config(), address(config), "config() should be constant after a disable");
    }

    // [X] RATE_LIMITS_DOMAIN equals keccak256("CCIP_TOKEN_POOL_CONFIG_RATE_LIMITS")
    // [X] REMOTE_POOLS_DOMAIN equals keccak256("CCIP_TOKEN_POOL_CONFIG_REMOTE_POOLS")
    // [X] ROUTE_IDENTITY_DOMAIN equals keccak256("CCIP_TOKEN_POOL_CONFIG_ROUTE_IDENTITY")
    // [X] ALLOWLIST_DOMAIN equals keccak256("CCIP_TOKEN_POOL_CONFIG_ALLOWLIST")
    // [X] the four constants are pairwise distinct
    function test_domainConstantsMatchDocumentedStrings() public view {
        bytes32 rateLimits = timelock.RATE_LIMITS_DOMAIN();
        bytes32 remotePools = timelock.REMOTE_POOLS_DOMAIN();
        bytes32 routeIdentity = timelock.ROUTE_IDENTITY_DOMAIN();
        bytes32 allowList = timelock.ALLOWLIST_DOMAIN();

        assertEq(
            rateLimits,
            keccak256("CCIP_TOKEN_POOL_CONFIG_RATE_LIMITS"),
            "RATE_LIMITS_DOMAIN should hash the documented string"
        );
        assertEq(
            remotePools,
            keccak256("CCIP_TOKEN_POOL_CONFIG_REMOTE_POOLS"),
            "REMOTE_POOLS_DOMAIN should hash the documented string"
        );
        assertEq(
            routeIdentity,
            keccak256("CCIP_TOKEN_POOL_CONFIG_ROUTE_IDENTITY"),
            "ROUTE_IDENTITY_DOMAIN should hash the documented string"
        );
        assertEq(
            allowList,
            keccak256("CCIP_TOKEN_POOL_CONFIG_ALLOWLIST"),
            "ALLOWLIST_DOMAIN should hash the documented string"
        );

        assertTrue(rateLimits != remotePools, "rate limits and remote pools should differ");
        assertTrue(rateLimits != routeIdentity, "rate limits and route identity should differ");
        assertTrue(rateLimits != allowList, "rate limits and allowlist should differ");
        assertTrue(remotePools != routeIdentity, "remote pools and route identity should differ");
        assertTrue(remotePools != allowList, "remote pools and allowlist should differ");
        assertTrue(routeIdentity != allowList, "route identity and allowlist should differ");
    }

    // given an addChain action is queued
    //   [X] pendingActionId answers the action id for the documented key of all three route
    //       domains of the selector
    //   [X] the ConfigStateQueued events carried exactly these three keys
    //   [X] getQueuedConfigState returns these keys for the sub-action
    // The seam pin: the keys the base reserves must reproduce byte for byte the documented
    // shape, keccak256(abi.encode(config, keccak256(abi.encode(domain, selector)))), which is
    // what the reconciliation tooling derives without reading the contract
    function test_givenChainActionQueued() public givenEnabled {
        _assertChainActionReservesDocumentedKeys(CHAIN_SELECTOR_A);
    }

    // when the selector is zero
    //   [X] the keys reserved for the route are the documented shape
    // The abi.encode padding of a uint64 is exercised at the low end; no route-existence gate
    // stands between the selector and its keys
    function test_whenSelectorIsZero() public givenEnabled {
        _assertChainActionReservesDocumentedKeys(0);
    }

    // when the selector is the uint64 maximum
    //   [X] the keys reserved for the route are the documented shape
    function test_whenSelectorIsUint64Max() public givenEnabled {
        _assertChainActionReservesDocumentedKeys(type(uint64).max);
    }

    // given a rate limit action is queued for route A
    //   [X] pendingActionId answers the action id for the documented rate limits key
    //   [X] the remote pools and route identity keys of route A stay free
    function test_givenRateLimitActionQueued()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        assertEq(
            timelock.pendingActionId(_rateLimitsKey(CHAIN_SELECTOR_A)),
            queuedActionId,
            "the rate limits key should be reserved by the canonical action"
        );
        assertEq(
            timelock.pendingActionId(_remotePoolsKey(CHAIN_SELECTOR_A)),
            0,
            "the remote pools key should stay free"
        );
        assertEq(
            timelock.pendingActionId(_routeIdentityKey(CHAIN_SELECTOR_A)),
            0,
            "the route identity key should stay free"
        );
    }

    // given an allowlist action is queued on the allowlist rig
    //   [X] pendingActionId answers the action id for the documented allowlist key
    // The allowlist local key is the bare domain constant, not a hash of it: the pool-wide
    // domain has no selector component
    function test_givenAllowListActionQueued() public givenAllowListPoolRig givenEnabled {
        uint64 actionId = _queueApplyAllowListUpdatesAction();

        assertEq(
            timelock.pendingActionId(_allowListKey()),
            actionId,
            "the allowlist key should be reserved by the queued action"
        );
    }

    // given an addChain action is queued
    //   [X] the three route keys the library derives for the config equal the recomputed keys
    //   [X] pendingActionId answers the action id under the library's keys
    function test_givenChainActionQueued_libraryKeysMatchReservations() public givenEnabled {
        uint64 actionId = _queueAddChainAction(CHAIN_SELECTOR_A);
        address configAddress = address(config);

        bytes32 rateLimitsKey = CCIPTokenPoolConfigKeyLib.rateLimitsKey(
            configAddress,
            CHAIN_SELECTOR_A
        );
        bytes32 remotePoolsKey = CCIPTokenPoolConfigKeyLib.remotePoolsKey(
            configAddress,
            CHAIN_SELECTOR_A
        );
        bytes32 routeIdentityKey = CCIPTokenPoolConfigKeyLib.routeIdentityKey(
            configAddress,
            CHAIN_SELECTOR_A
        );

        assertEq(
            rateLimitsKey,
            _rateLimitsKey(CHAIN_SELECTOR_A),
            "the library rate limits key should match the documented shape"
        );
        assertEq(
            remotePoolsKey,
            _remotePoolsKey(CHAIN_SELECTOR_A),
            "the library remote pools key should match the documented shape"
        );
        assertEq(
            routeIdentityKey,
            _routeIdentityKey(CHAIN_SELECTOR_A),
            "the library route identity key should match the documented shape"
        );
        assertEq(
            timelock.pendingActionId(rateLimitsKey),
            actionId,
            "the contract should hold the reservation under the library rate limits key"
        );
        assertEq(
            timelock.pendingActionId(remotePoolsKey),
            actionId,
            "the contract should hold the reservation under the library remote pools key"
        );
        assertEq(
            timelock.pendingActionId(routeIdentityKey),
            actionId,
            "the contract should hold the reservation under the library route identity key"
        );
    }

    // given an allowlist action is queued on the allowlist rig
    //   [X] the allowlist key the library derives for the config equals the recomputed key
    //   [X] pendingActionId answers the action id under the library's key
    function test_givenAllowListActionQueued_libraryKeyMatchesReservation()
        public
        givenAllowListPoolRig
        givenEnabled
    {
        uint64 actionId = _queueApplyAllowListUpdatesAction();

        bytes32 allowListKey = CCIPTokenPoolConfigKeyLib.allowListKey(address(config));

        assertEq(
            allowListKey,
            _allowListKey(),
            "the library allowlist key should match the documented shape"
        );
        assertEq(
            timelock.pendingActionId(allowListKey),
            actionId,
            "the contract should hold the reservation under the library allowlist key"
        );
    }

    // when two selectors differ
    //   [X] the documented route keys differ for the two selectors, in every route domain
    // Fuzzed; vm.assume separates the selectors. A collision would let the reconciler read one
    // route's reservation as another's.
    function test_whenSelectorsDiffer(uint64 selectorA_, uint64 selectorB_) public view {
        vm.assume(selectorA_ != selectorB_);

        assertTrue(
            _rateLimitsKey(selectorA_) != _rateLimitsKey(selectorB_),
            "the rate limits keys of distinct selectors should differ"
        );
        assertTrue(
            _remotePoolsKey(selectorA_) != _remotePoolsKey(selectorB_),
            "the remote pools keys of distinct selectors should differ"
        );
        assertTrue(
            _routeIdentityKey(selectorA_) != _routeIdentityKey(selectorB_),
            "the route identity keys of distinct selectors should differ"
        );
    }

    // when one selector is shared across the domains
    //   [X] the three documented route keys are pairwise distinct
    //   [X] each route key differs from the allowlist key
    // Fuzzed over the full selector range
    function test_whenSelectorIsShared(uint64 selector_) public view {
        bytes32 rateLimitsKey = _rateLimitsKey(selector_);
        bytes32 remotePoolsKey = _remotePoolsKey(selector_);
        bytes32 routeIdentityKey = _routeIdentityKey(selector_);
        bytes32 allowListKey = _allowListKey();

        assertTrue(rateLimitsKey != remotePoolsKey, "rate limits and remote pools should differ");
        assertTrue(
            rateLimitsKey != routeIdentityKey,
            "rate limits and route identity should differ"
        );
        assertTrue(
            remotePoolsKey != routeIdentityKey,
            "remote pools and route identity should differ"
        );
        assertTrue(rateLimitsKey != allowListKey, "rate limits and allowlist should differ");
        assertTrue(remotePoolsKey != allowListKey, "remote pools and allowlist should differ");
        assertTrue(routeIdentityKey != allowListKey, "route identity and allowlist should differ");
    }

    // given a second timelock over a second config instance
    //   [X] the second timelock reserves the keys scoped to its own config
    //   [X] the same domains scoped to the primary config are free on the second timelock
    //   [X] the domains scoped to the second config are free on the primary timelock
    // Destination scoping: each timelock namespaces its keys with the config it is bound to,
    // so a replacement stack cannot collide with this one
    function test_givenSecondConfigInstance() public givenEnabled {
        (
            CCIPTokenPoolConfig secondConfig,
            CCIPTokenPoolConfigTimelock secondTimelock
        ) = _deployStackOnKernel(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(secondConfig));
        kernel.executeAction(Actions.ActivatePolicy, address(secondTimelock));
        vm.startPrank(admin);
        secondConfig.enable("");
        secondConfig.setConfigOperator(address(secondTimelock));
        secondTimelock.enable("");
        vm.stopPrank();

        // The same route on both timelocks: queueing needs no pool ownership, only the
        // validation mirror, which both configs run against the shared pool
        uint64 primaryActionId = _queueAddChainAction(CHAIN_SELECTOR_A);
        vm.prank(bridgeAdmin);
        uint64 secondActionId = secondTimelock.queueAddChain(_defaultChainUpdate(CHAIN_SELECTOR_A));

        bytes32[3] memory primaryKeys = [
            _rateLimitsKey(CHAIN_SELECTOR_A),
            _remotePoolsKey(CHAIN_SELECTOR_A),
            _routeIdentityKey(CHAIN_SELECTOR_A)
        ];
        bytes32[3] memory secondKeys = [
            _routeKeyOf(address(secondConfig), timelock.RATE_LIMITS_DOMAIN(), CHAIN_SELECTOR_A),
            _routeKeyOf(address(secondConfig), timelock.REMOTE_POOLS_DOMAIN(), CHAIN_SELECTOR_A),
            _routeKeyOf(address(secondConfig), timelock.ROUTE_IDENTITY_DOMAIN(), CHAIN_SELECTOR_A)
        ];
        for (uint256 i; i < 3; ++i) {
            assertTrue(primaryKeys[i] != secondKeys[i], "the namespaces should not collide");
            assertEq(
                timelock.pendingActionId(primaryKeys[i]),
                primaryActionId,
                "the primary timelock should reserve the key scoped to the primary config"
            );
            assertEq(
                timelock.pendingActionId(secondKeys[i]),
                0,
                "the key scoped to the second config should be free on the primary timelock"
            );
            assertEq(
                secondTimelock.pendingActionId(secondKeys[i]),
                secondActionId,
                "the second timelock should reserve the key scoped to the second config"
            );
            assertEq(
                secondTimelock.pendingActionId(primaryKeys[i]),
                0,
                "the key scoped to the primary config should be free on the second timelock"
            );
        }
    }
}
