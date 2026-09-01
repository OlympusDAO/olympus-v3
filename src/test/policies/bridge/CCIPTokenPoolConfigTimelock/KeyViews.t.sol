// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {CCIPTokenPoolConfig} from "src/policies/bridge/CCIPTokenPoolConfig.sol";
import {CCIPTokenPoolConfigTimelock} from "src/policies/bridge/CCIPTokenPoolConfigTimelock.sol";

import {CCIPTokenPoolConfigTimelockTest} from "./CCIPTokenPoolConfigTimelockTest.sol";

contract CCIPTokenPoolConfigTimelockTests_KeyViews is CCIPTokenPoolConfigTimelockTest {
    // ========== SHAPE HELPERS (file-local) ========== //

    /// @notice Recomputes the documented two-level route key shape:
    ///         keccak256(abi.encode(config, keccak256(abi.encode(domain, selector)))).
    function _routeKeyShape(bytes32 domain_, uint64 selector_) internal view returns (bytes32) {
        return keccak256(abi.encode(address(config), keccak256(abi.encode(domain_, selector_))));
    }

    /// @notice Asserts all three route getters against the documented shape for one selector.
    function _assertRouteKeyShapes(uint64 selector_) internal view {
        assertEq(
            timelock.getRateLimitsKey(selector_),
            _routeKeyShape(timelock.RATE_LIMITS_DOMAIN(), selector_),
            "getRateLimitsKey should match the documented shape"
        );
        assertEq(
            timelock.getRemotePoolsKey(selector_),
            _routeKeyShape(timelock.REMOTE_POOLS_DOMAIN(), selector_),
            "getRemotePoolsKey should match the documented shape"
        );
        assertEq(
            timelock.getRouteIdentityKey(selector_),
            _routeKeyShape(timelock.ROUTE_IDENTITY_DOMAIN(), selector_),
            "getRouteIdentityKey should match the documented shape"
        );
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

    // when getRateLimitsKey is called for a selector
    //   [X] it equals keccak256(abi.encode(config, keccak256(abi.encode(RATE_LIMITS_DOMAIN,
    //       selector))))
    // Runs on the setUp default state (disabled, no routes): the key is a pure function of
    // the selector, with no route-existence or lifecycle gate
    function test_getRateLimitsKey_matchesDocumentedShape() public view {
        assertEq(
            timelock.getRateLimitsKey(CHAIN_SELECTOR_A),
            _routeKeyShape(timelock.RATE_LIMITS_DOMAIN(), CHAIN_SELECTOR_A),
            "getRateLimitsKey should match the documented shape on the bare rig"
        );
    }

    // when getRemotePoolsKey is called for a selector
    //   [X] it equals the documented two-level hash over REMOTE_POOLS_DOMAIN
    function test_getRemotePoolsKey_matchesDocumentedShape() public view {
        assertEq(
            timelock.getRemotePoolsKey(CHAIN_SELECTOR_A),
            _routeKeyShape(timelock.REMOTE_POOLS_DOMAIN(), CHAIN_SELECTOR_A),
            "getRemotePoolsKey should match the documented shape on the bare rig"
        );
    }

    // when getRouteIdentityKey is called for a selector
    //   [X] it equals the documented two-level hash over ROUTE_IDENTITY_DOMAIN
    function test_getRouteIdentityKey_matchesDocumentedShape() public view {
        assertEq(
            timelock.getRouteIdentityKey(CHAIN_SELECTOR_A),
            _routeKeyShape(timelock.ROUTE_IDENTITY_DOMAIN(), CHAIN_SELECTOR_A),
            "getRouteIdentityKey should match the documented shape on the bare rig"
        );
    }

    // when getAllowListKey is called
    //   [X] it equals keccak256(abi.encode(config, ALLOWLIST_DOMAIN))
    // The allowlist local key is the bare domain constant, not a hash of it: the pool-wide
    // domain has no selector component
    function test_getAllowListKey_matchesDocumentedShape() public view {
        assertEq(
            timelock.getAllowListKey(),
            keccak256(abi.encode(address(config), timelock.ALLOWLIST_DOMAIN())),
            "getAllowListKey should scope the bare domain constant"
        );
    }

    // when two selectors differ
    //   [X] each route getter answers differently for the two selectors
    // Fuzzed; vm.assume separates the selectors
    function test_whenSelectorsDiffer(uint64 selectorA_, uint64 selectorB_) public view {
        vm.assume(selectorA_ != selectorB_);

        assertTrue(
            timelock.getRateLimitsKey(selectorA_) != timelock.getRateLimitsKey(selectorB_),
            "the rate limits keys of distinct selectors should differ"
        );
        assertTrue(
            timelock.getRemotePoolsKey(selectorA_) != timelock.getRemotePoolsKey(selectorB_),
            "the remote pools keys of distinct selectors should differ"
        );
        assertTrue(
            timelock.getRouteIdentityKey(selectorA_) != timelock.getRouteIdentityKey(selectorB_),
            "the route identity keys of distinct selectors should differ"
        );
    }

    // when one selector is shared across the getters
    //   [X] the three route keys are pairwise distinct
    //   [X] each route key differs from the allowlist key
    // Fuzzed over the full selector range
    function test_whenSelectorIsShared(uint64 selector_) public view {
        bytes32 rateLimitsKey = timelock.getRateLimitsKey(selector_);
        bytes32 remotePoolsKey = timelock.getRemotePoolsKey(selector_);
        bytes32 routeIdentityKey = timelock.getRouteIdentityKey(selector_);
        bytes32 allowListKey = timelock.getAllowListKey();

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

    // when the selector is zero
    //   [X] every route getter answers the documented shape
    function test_whenSelectorIsZero() public view {
        _assertRouteKeyShapes(0);
    }

    // when the selector is the uint64 maximum
    //   [X] every route getter answers the documented shape
    function test_whenSelectorIsUint64Max() public view {
        _assertRouteKeyShapes(type(uint64).max);
    }

    // given an addChain action is queued
    //   [X] pendingActionId answers the action id for all three route keys of the selector
    //   [X] the ConfigStateQueued events carried exactly these three keys
    //   [X] getQueuedConfigState returns these keys for the sub-action
    // The seam pin: the public getters must reproduce byte for byte the keys the base
    // reserved, or the views and the bookkeeping have diverged
    function test_givenChainActionQueued() public givenEnabled {
        bytes32[] memory expectedKeys = new bytes32[](3);
        expectedKeys[0] = timelock.getRateLimitsKey(CHAIN_SELECTOR_A);
        expectedKeys[1] = timelock.getRemotePoolsKey(CHAIN_SELECTOR_A);
        expectedKeys[2] = timelock.getRouteIdentityKey(CHAIN_SELECTOR_A);

        vm.recordLogs();
        uint64 actionId = _queueAddChainAction(CHAIN_SELECTOR_A);

        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, actionId, "after the queue");

        // The three ConfigStateQueued events carry the reserved key as the third topic, in
        // the _configKeys order: rate limits, remote pools, route identity
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
                "the ConfigStateQueued event should carry the getter's key"
            );
            ++eventCount;
        }
        assertEq(eventCount, 3, "exactly three ConfigStateQueued events should be emitted");

        for (uint256 i; i < expectedKeys.length; ++i) {
            (bytes32 storedKey, ) = timelock.getQueuedConfigState(actionId, 0, i);
            assertEq(
                storedKey,
                expectedKeys[i],
                "the stored config state key should equal the getter's key"
            );
        }
    }

    // given a rate limit action is queued for route A
    //   [X] pendingActionId answers the action id for the rate limits key
    //   [X] the remote pools and route identity keys of route A stay free
    function test_givenRateLimitActionQueued()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            queuedActionId,
            "the rate limits key should be reserved by the canonical action"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            0,
            "the remote pools key should stay free"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRouteIdentityKey(CHAIN_SELECTOR_A)),
            0,
            "the route identity key should stay free"
        );
    }

    // given an allowlist action is queued on the allowlist rig
    //   [X] pendingActionId answers the action id for getAllowListKey()
    function test_givenAllowListActionQueued() public givenAllowListPoolRig givenEnabled {
        uint64 actionId = _queueApplyAllowListUpdatesAction();

        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            actionId,
            "the allowlist key should be reserved by the queued action"
        );
    }

    // given a second timelock over a second config instance
    //   [X] its keys differ from the primary timelock's keys for the same inputs
    // Destination scoping: each config policy namespaces its own keys, so a replacement
    // stack cannot collide with this one
    function test_givenSecondConfigInstance() public {
        (
            CCIPTokenPoolConfig secondConfig,
            CCIPTokenPoolConfigTimelock secondTimelock
        ) = _deployStackOnKernel(kernel);
        assertEq(
            secondTimelock.config(),
            address(secondConfig),
            "the second timelock should bind the second config"
        );

        assertTrue(
            secondTimelock.getRateLimitsKey(CHAIN_SELECTOR_A) !=
                timelock.getRateLimitsKey(CHAIN_SELECTOR_A),
            "the rate limits keys should differ across config namespaces"
        );
        assertTrue(
            secondTimelock.getRemotePoolsKey(CHAIN_SELECTOR_A) !=
                timelock.getRemotePoolsKey(CHAIN_SELECTOR_A),
            "the remote pools keys should differ across config namespaces"
        );
        assertTrue(
            secondTimelock.getRouteIdentityKey(CHAIN_SELECTOR_A) !=
                timelock.getRouteIdentityKey(CHAIN_SELECTOR_A),
            "the route identity keys should differ across config namespaces"
        );
        assertTrue(
            secondTimelock.getAllowListKey() != timelock.getAllowListKey(),
            "the allowlist keys should differ across config namespaces"
        );
    }
}
