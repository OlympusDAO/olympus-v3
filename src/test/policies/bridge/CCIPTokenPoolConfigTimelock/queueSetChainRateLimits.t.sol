// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BRIDGE_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPTokenPoolConfigTimelockTest} from "./CCIPTokenPoolConfigTimelockTest.sol";

contract CCIPTokenPoolConfigTimelockTests_queueSetChainRateLimits is
    CCIPTokenPoolConfigTimelockTest
{
    // ========== SHARED QUEUE GATE LADDER ========== //

    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    // The setUp default state; the Q1/Q2 order is unobservable (both raise NotEnabled)
    function test_givenTimelockDisabled_reverts() public givenChainAdded {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // given the config policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenConfigDisabled_reverts()
        public
        givenEnabled
        givenChainAdded
        givenConfigDisabled
    {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // given the config policy is disabled
    //   when the caller is not a bridge admin
    //     [X] it reverts with NotEnabled
    // Pins the gate order: the config-enabled gate answers before the role gate
    function test_givenConfigDisabled_whenCallerIsNotBridgeAdmin_reverts()
        public
        givenEnabled
        givenChainAdded
        givenConfigDisabled
    {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertNotEnabled();
        vm.prank(thirdParty);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // when the caller does not hold the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Fuzzed; excludes the bridge admin account
    function test_whenCallerIsNotBridgeAdmin_reverts(
        address caller_
    ) public givenEnabled givenChainAdded {
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != address(0));
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(caller_);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // when the caller holds the admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsAdmin_reverts() public givenEnabled givenChainAdded {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(admin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenChainAdded {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(emergency);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // The direct rate-limit role holds no QUEUE authority: its surface is the config's
    // setChainRateLimits, never the timelock
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled givenChainAdded {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // given the config operator has been rotated away
    //   when the caller is not a bridge admin
    //     [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Pins the gate order: the role gate answers before the operator gate
    function test_givenOperatorRotated_whenCallerIsNotBridgeAdmin_reverts()
        public
        givenEnabled
        givenChainAdded
        givenOperatorRotated
    {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(thirdParty);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // given the config operator has been rotated to another account
    //   [X] it reverts with CCIPTokenPoolConfigTimelock_NotConfigOperator carrying the new
    //       operator
    function test_givenOperatorRotated_reverts()
        public
        givenEnabled
        givenChainAdded
        givenOperatorRotated
    {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // given the config operator has been revoked
    //   [X] it reverts with CCIPTokenPoolConfigTimelock_NotConfigOperator carrying the zero
    //       address
    function test_givenOperatorRevoked_reverts()
        public
        givenEnabled
        givenChainAdded
        givenOperatorRevoked
    {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertNotConfigOperator(address(0));
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // given the config operator has been rotated away
    //   given the route does not exist
    //     [X] it reverts with CCIPTokenPoolConfigTimelock_NotConfigOperator
    // Pins the gate order: the operator gate answers before the validation mirror
    function test_givenOperatorRotated_givenRouteDoesNotExist_reverts()
        public
        givenEnabled
        givenOperatorRotated
    {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // ========== VALIDATION MIRROR LADDER ========== //

    // given the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    // Unlike validateAddChain, the existence check leads the mirror
    function test_givenRouteDoesNotExist_reverts() public givenEnabled {
        // The configurations are valid, so only the missing route can fail the mirror
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // when the outbound configuration is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    function test_whenOutboundConfigIsDisabled_reverts() public givenEnabled givenChainAdded {
        ICCIPRateLimiter.Config memory outbound = _disabledConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // when the outbound rate equals the outbound capacity
    //   [X] it reverts with InvalidRateLimitRate carrying the outbound configuration
    // The comparison is a non-strict >=, so equality is the failing side of the boundary
    function test_whenOutboundRateEqualsCapacity_reverts() public givenEnabled givenChainAdded {
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(
            true,
            CANONICAL_OUTBOUND_CAPACITY,
            CANONICAL_OUTBOUND_CAPACITY
        );
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPRateLimiter.InvalidRateLimitRate.selector, outbound)
        );
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should stay free after the rejected queue"
        );
    }

    // when the inbound configuration is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    // The outbound configuration is valid, so the failure proves the inbound leg is checked
    function test_whenInboundConfigIsDisabled_reverts() public givenEnabled givenChainAdded {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _disabledConfig();

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // when the inbound rate is zero
    //   [X] it reverts with InvalidRateLimitRate carrying the inbound configuration
    function test_whenInboundRateIsZero_reverts() public givenEnabled givenChainAdded {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _rateLimiterConfig(
            true,
            CANONICAL_INBOUND_CAPACITY,
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPRateLimiter.InvalidRateLimitRate.selector, inbound)
        );
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // ========== KEY CONFLICTS ========== //

    // given a rate limit change for the same route is already queued
    //   [X] it reverts with ConfigKeyPending carrying the rate limits key and the holder id
    // The domain conflicts with itself
    function test_givenSameRouteRateLimitAlreadyQueued_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        // A different payload: the domain conflicts regardless of the values
        ICCIPRateLimiter.Config memory outbound = _defaultOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _defaultInboundConfig();

        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(CHAIN_SELECTOR_A), queuedActionId);
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // given a removal of the route is already queued
    //   [X] it reverts with ConfigKeyPending carrying the rate limits key and the holder id
    // The spec exclusion, removal-first direction: a limit change and a removeChain can
    // never coexist for one route (the limit-first direction is pinned in the
    // queueRemoveChain pass)
    function test_givenChainRemovalQueuedForRoute_reverts() public givenEnabled givenChainAdded {
        uint64 holderActionId = _queueRemoveChainAction(CHAIN_SELECTOR_A);
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // given a token change is queued for the route
    //   [X] it reverts with ConfigKeyPending carrying the rate limits key and the holder id
    // A three-key holder blocks through its rate limits key
    function test_givenTokenChangeQueuedForRoute_reverts() public givenEnabled givenChainAdded {
        uint64 holderActionId = _queueSetRemoteTokenAction(CHAIN_SELECTOR_A);
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);
    }

    // given an addChain action is queued for the selector
    //   [X] it reverts with NonExistentChain, not ConfigKeyPending
    // The existence check masks the conflict: a route still being created accepts no
    // rate-limit queue, and the error must not be read as "domain free"
    function test_givenChainAdditionQueuedForSelector_reverts() public givenEnabled {
        uint64 holderActionId = _queueAddChainAction(CHAIN_SELECTOR_A);
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(bridgeAdmin);
        timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        // The domain is not free at all: the addChain action holds it while the mirror
        // reports a missing route
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            holderActionId,
            "the rate limits key should still be held by the pending addChain action"
        );
    }

    // ========== SUCCESS ========== //

    // when the caller is the bridge admin
    //   [X] it returns the action id and increments nextActionId
    //   [X] it reserves ONLY the rate limits key: the remote pools and route identity keys
    //       of the route stay free
    //   [X] the stored hash equals the live default bucket configurations
    //   [X] it stores the destination, a config state count of ONE, the timestamps and the
    //       canonical payload
    //   [X] it emits one ConfigStateQueued, one TimelockSubActionQueued and one
    //       TimelockActionQueued
    function test_whenCallerIsBridgeAdmin() public givenEnabled givenChainAdded {
        ICCIPRateLimiter.Config memory outbound = _canonicalOutboundConfig();
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();
        bytes memory payload = abi.encode(CHAIN_SELECTOR_A, outbound, inbound);

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = timelock.getRateLimitsKey(CHAIN_SELECTOR_A);

        bytes32[] memory expectedHashes = new bytes32[](1);
        expectedHashes[0] = _expectedRateLimitsHash(CHAIN_SELECTOR_A);
        // The hash records the state at queue time: the live default configurations, not the
        // canonical values the action would write
        assertEq(
            expectedHashes[0],
            keccak256(
                abi.encode(
                    timelock.RATE_LIMITS_DOMAIN(),
                    CHAIN_SELECTOR_A,
                    true,
                    DEFAULT_OUTBOUND_CAPACITY,
                    DEFAULT_OUTBOUND_RATE,
                    true,
                    DEFAULT_INBOUND_CAPACITY,
                    DEFAULT_INBOUND_RATE
                )
            ),
            "the recorded hash should carry the live default bucket configurations"
        );

        uint64 expectedActionId = timelock.nextActionId();
        // executableAt = now + 1 days (the delay); expiresAt = executableAt + 3 days (the
        // execution window)
        uint48 expectedExecutableAt = uint48(vm.getBlockTimestamp()) + TIMELOCK_DELAY;
        uint48 expectedExpiresAt = expectedExecutableAt + 3 days;
        bytes32 batchHash = keccak256(
            abi.encode(
                _singleActionBatch(
                    _setChainRateLimitsBatchAction(CHAIN_SELECTOR_A, outbound, inbound)
                )
            )
        );

        vm.expectEmit(true, true, true, true, address(timelock));
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            expectedActionId,
            0,
            keys[0],
            0,
            address(config),
            expectedHashes[0]
        );
        vm.expectEmit(true, true, true, true, address(timelock));
        emit ITimelockBatchQueue.TimelockSubActionQueued(
            expectedActionId,
            address(config),
            ICCIPTokenPoolConfig.setChainRateLimits.selector,
            0,
            keccak256(payload)
        );
        vm.expectEmit(true, true, true, true, address(timelock));
        emit ITimelockBatchQueue.TimelockActionQueued(
            expectedActionId,
            bridgeAdmin,
            batchHash,
            expectedExecutableAt,
            expectedExpiresAt
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        assertEq(actionId, expectedActionId, "the returned action id should be the next id");
        assertEq(timelock.nextActionId(), expectedActionId + 1, "nextActionId should increment");
        _assertQueuedSingleAction(
            actionId,
            bridgeAdmin,
            ICCIPTokenPoolConfig.setChainRateLimits.selector,
            payload,
            keys,
            expectedHashes
        );

        // The narrowness of the reservation: the two sibling domains of the route stay free
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

    // when the outbound rate is one below the capacity
    //   [X] it queues successfully
    // The passing side of the non-strict rate boundary
    function test_whenOutboundRateIsOneBelowCapacity() public givenEnabled givenChainAdded {
        // rate = capacity - 1 is the largest accepted rate for the capacity
        ICCIPRateLimiter.Config memory outbound = _rateLimiterConfig(
            true,
            CANONICAL_OUTBOUND_CAPACITY,
            CANONICAL_OUTBOUND_CAPACITY - 1
        );
        ICCIPRateLimiter.Config memory inbound = _canonicalInboundConfig();

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            actionId,
            "the rate limits key should belong to the boundary action"
        );
    }

    // when both configurations are the minimal enabled shape {true, 2, 1}
    //   [X] it queues successfully
    // The queue path can carry containment-equivalent values
    function test_whenRateLimitConfigsAreMinimal() public givenEnabled givenChainAdded {
        ICCIPRateLimiter.Config memory outbound = _containmentConfig();
        ICCIPRateLimiter.Config memory inbound = _containmentConfig();

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueSetChainRateLimits(CHAIN_SELECTOR_A, outbound, inbound);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            actionId,
            "the rate limits key should belong to the minimal-config action"
        );
    }

    // given the route is contained
    //   [X] it queues successfully
    // The queue path of the un-containment recovery; the recorded hash covers the
    // containment shape
    function test_givenRouteIsContained() public givenEnabled givenChainAdded givenRouteContained {
        bytes32 containedRateLimitsHash = _expectedRateLimitsHash(CHAIN_SELECTOR_A);
        // The containment write is {true, 2, 1} on both buckets
        assertEq(
            containedRateLimitsHash,
            keccak256(
                abi.encode(
                    timelock.RATE_LIMITS_DOMAIN(),
                    CHAIN_SELECTOR_A,
                    true,
                    uint128(2),
                    uint128(1),
                    true,
                    uint128(2),
                    uint128(1)
                )
            ),
            "the recorded rate limits hash should carry the containment shape"
        );

        uint64 actionId = _queueRateLimitAction(CHAIN_SELECTOR_A);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            actionId,
            "the rate limits key should belong to the un-containment action"
        );
        (, bytes32 storedRateLimitsHash) = timelock.getQueuedConfigState(actionId, 0, 0);
        assertEq(
            storedRateLimitsHash,
            containedRateLimitsHash,
            "the stored hash should be the containment-shape hash"
        );
    }

    // given a rate limit action is queued for another route
    //   [X] it queues successfully and each action holds only its own route's key
    function test_givenSecondRouteRateLimitQueued()
        public
        givenEnabled
        givenChainAdded
        givenSecondChainAdded
    {
        uint64 secondRouteActionId = _queueRateLimitAction(CHAIN_SELECTOR_B);

        uint64 firstRouteActionId = _queueRateLimitAction(CHAIN_SELECTOR_A);

        assertEq(firstRouteActionId, secondRouteActionId + 1, "the ids should be sequential");
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_B)),
            secondRouteActionId,
            "the second route's rate limits key should belong to its own action"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            firstRouteActionId,
            "the first route's rate limits key should belong to its own action"
        );
    }
}
