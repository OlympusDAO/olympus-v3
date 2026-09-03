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

contract CCIPTokenPoolConfigTimelockTests_queueAddChain is CCIPTokenPoolConfigTimelockTest {
    // ========== SHARED QUEUE GATE LADDER ========== //

    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    // The setUp default state. The Q1/Q2 order is unobservable (both gates raise NotEnabled),
    // so each disabled state gets its own test and no precedence test exists between them.
    function test_givenTimelockDisabled_reverts() public {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // given the config policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenConfigDisabled_reverts() public givenEnabled givenConfigDisabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // given the config policy is disabled
    //   when the caller is not a bridge admin
    //     [X] it reverts with NotEnabled
    // Pins the gate order: the config-enabled gate answers before the role gate
    function test_givenConfigDisabled_whenCallerIsNotBridgeAdmin_reverts()
        public
        givenEnabled
        givenConfigDisabled
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertNotEnabled();
        vm.prank(thirdParty);
        timelock.queueAddChain(update);
    }

    // when the caller does not hold the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Fuzzed; excludes the bridge admin account
    function test_whenCallerIsNotBridgeAdmin_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != address(0));
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(caller_);
        timelock.queueAddChain(update);
    }

    // when the caller holds the admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // The admin is deliberately not a proposer: every queued action targets a function the
    // admin can call directly on the config policy
    function test_whenCallerIsAdmin_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(admin);
        timelock.queueAddChain(update);
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(emergency);
        timelock.queueAddChain(update);
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // The bridge rate limiter holds no timelock authority at all
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        timelock.queueAddChain(update);
    }

    // given the config operator has been rotated away
    //   when the caller is not a bridge admin
    //     [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Pins the gate order: the role gate answers before the operator gate
    function test_givenOperatorRotated_whenCallerIsNotBridgeAdmin_reverts()
        public
        givenEnabled
        givenOperatorRotated
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(thirdParty);
        timelock.queueAddChain(update);
    }

    // given the config operator has been rotated to another account
    //   [X] it reverts with CCIPTokenPoolConfigTimelock_NotConfigOperator carrying the new
    //       operator
    function test_givenOperatorRotated_reverts() public givenEnabled givenOperatorRotated {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // given the config operator has been revoked
    //   [X] it reverts with CCIPTokenPoolConfigTimelock_NotConfigOperator carrying the zero
    //       address
    function test_givenOperatorRevoked_reverts() public givenEnabled givenOperatorRevoked {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertNotConfigOperator(address(0));
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // given the config operator has been rotated away
    //   when the update is invalid
    //     [X] it reverts with CCIPTokenPoolConfigTimelock_NotConfigOperator
    // Pins the gate order: the operator gate answers before the validation mirror
    function test_givenOperatorRotated_whenUpdateIsInvalid_reverts()
        public
        givenEnabled
        givenOperatorRotated
    {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _disabledConfig();

        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // ========== VALIDATION MIRROR LADDER ========== //

    // when the outbound configuration is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    function test_whenOutboundConfigIsDisabled_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _disabledConfig();

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // when the outbound rate is zero
    //   [X] it reverts with InvalidRateLimitRate carrying the outbound configuration
    function test_whenOutboundRateIsZero_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _rateLimiterConfig(true, DEFAULT_OUTBOUND_CAPACITY, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPRateLimiter.InvalidRateLimitRate.selector,
                update.outboundRateLimiterConfig
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // when the outbound rate equals the outbound capacity
    //   [X] it reverts with InvalidRateLimitRate
    //   [X] no key of the selector is reserved after the revert
    // The comparison is a non-strict >=, so equality is the failing side of the boundary.
    // Also pins that validation precedes reservation: the revert leaves pendingActionId zero.
    function test_whenOutboundRateEqualsCapacity_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _rateLimiterConfig(true, 100, 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPRateLimiter.InvalidRateLimitRate.selector,
                update.outboundRateLimiterConfig
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);

        _assertRouteKeysFree(CHAIN_SELECTOR_A, "after the rejected queue");
    }

    // when the inbound configuration is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    // The outbound configuration is valid, so the failure proves the inbound leg is checked
    function test_whenInboundConfigIsDisabled_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.inboundRateLimiterConfig = _disabledConfig();

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // when the inbound rate equals the inbound capacity
    //   [X] it reverts with InvalidRateLimitRate carrying the inbound configuration
    function test_whenInboundRateEqualsCapacity_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.inboundRateLimiterConfig = _rateLimiterConfig(true, 200, 200);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPRateLimiter.InvalidRateLimitRate.selector,
                update.inboundRateLimiterConfig
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // when the remote token is empty
    //   [X] it reverts with ZeroAddressNotAllowed
    function test_whenRemoteTokenIsEmpty_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.remoteTokenAddress = "";

        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.ZeroAddressNotAllowed.selector));
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // given the route already exists
    //   [X] it reverts with ChainAlreadyExists carrying the selector
    function test_givenRouteAlreadyExists_reverts() public givenEnabled givenChainAdded {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.ChainAlreadyExists.selector,
                CHAIN_SELECTOR_A
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // when the remote pool list is empty
    //   [X] it reverts with CCIPTokenPoolConfig_RemotePoolsEmpty
    function test_whenRemotePoolListIsEmpty_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.remotePoolAddresses = new bytes[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RemotePoolsEmpty.selector
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // when a remote pool entry is empty
    //   [X] it reverts with ZeroAddressNotAllowed
    function test_whenARemotePoolEntryIsEmpty_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.remotePoolAddresses[1] = "";

        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.ZeroAddressNotAllowed.selector));
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // when two remote pool entries are identical
    //   [X] it reverts with PoolAlreadyAdded carrying the selector and the entry
    function test_whenRemotePoolEntriesAreDuplicated_reverts() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.remotePoolAddresses[1] = REMOTE_POOL_ONE;

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.PoolAlreadyAdded.selector,
                CHAIN_SELECTOR_A,
                REMOTE_POOL_ONE
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // ========== KEY CONFLICTS ========== //

    // given an addChain action for the same selector is already queued
    //   [X] it reverts with ConfigKeyPending carrying the rate limits key and the holder id
    // The rate limits key is first in the _configKeys order, so a three-domain conflict
    // names it
    function test_givenSameRouteAlreadyQueued_reverts() public givenEnabled {
        uint64 holderActionId = _queueAddChainAction(CHAIN_SELECTOR_A);
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // given a rate limit action was queued for the route and the route was then removed
    //       directly by the admin
    //   [X] it reverts with ConfigKeyPending carrying the rate limits key and the holder id
    // The rate limits domain is held alone; validation passes because the route is gone
    function test_givenRateLimitActionPendingAfterDirectRemoval_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        _directRemoveChain(CHAIN_SELECTOR_A);
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(CHAIN_SELECTOR_A), queuedActionId);
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // given a remote pool action was queued for the route and the route was then removed
    //       directly by the admin
    //   [X] it reverts with ConfigKeyPending carrying the remote pools key and the holder id
    // The remote pools domain is held alone; the rate limits key is free, so the walk
    // reaches the second key
    function test_givenRemotePoolActionPendingAfterDirectRemoval_reverts()
        public
        givenEnabled
        givenChainAdded
    {
        uint64 holderActionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);
        _directRemoveChain(CHAIN_SELECTOR_A);
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);

        _expectRevertConfigKeyPending(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueAddChain(update);
    }

    // ========== SUCCESS ========== //

    // when the caller is the bridge admin
    //   [X] it returns the first action id and increments nextActionId
    //   [X] it reserves the rate limits, remote pools and route identity keys of the selector
    //   [X] the stored hashes equal the recomputed absent-route preimages of the three
    //       domains
    //   [X] it stores the config policy as the destination and a config state count of three
    //   [X] it stores the proposer, queuedAt, executableAt = now + delay and
    //       expiresAt = executableAt + 3 days
    //   [X] the stored sub-action carries the config target, the addChain selector and the
    //       canonical payload
    //   [X] it emits three ConfigStateQueued events with the scoped keys in domain order,
    //       one TimelockSubActionQueued and one TimelockActionQueued
    function test_whenCallerIsBridgeAdmin() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        bytes memory payload = abi.encode(update);

        // The scoped keys in _configKeys order: rate limits, remote pools, route identity
        bytes32[] memory keys = new bytes32[](3);
        keys[0] = timelock.getRateLimitsKey(CHAIN_SELECTOR_A);
        keys[1] = timelock.getRemotePoolsKey(CHAIN_SELECTOR_A);
        keys[2] = timelock.getRouteIdentityKey(CHAIN_SELECTOR_A);

        // For an absent route every pool getter answers its default, so the recomputed live
        // hashes reduce to the documented absent-route preimages:
        // - rate limits: both buckets disabled with zero capacity and rate;
        // - remote pools: zero count and a zero XOR aggregate;
        // - route identity: unsupported chain and an empty remote token.
        bytes32[] memory expectedHashes = new bytes32[](3);
        expectedHashes[0] = _expectedRateLimitsHash(CHAIN_SELECTOR_A);
        expectedHashes[1] = _expectedRemotePoolsHash(CHAIN_SELECTOR_A);
        expectedHashes[2] = _expectedRouteIdentityHash(CHAIN_SELECTOR_A);
        assertEq(
            expectedHashes[0],
            keccak256(
                abi.encode(
                    timelock.RATE_LIMITS_DOMAIN(),
                    CHAIN_SELECTOR_A,
                    false,
                    uint128(0),
                    uint128(0),
                    false,
                    uint128(0),
                    uint128(0)
                )
            ),
            "the live rate limits hash should reduce to the absent-route preimage"
        );
        assertEq(
            expectedHashes[1],
            keccak256(
                abi.encode(timelock.REMOTE_POOLS_DOMAIN(), CHAIN_SELECTOR_A, uint256(0), bytes32(0))
            ),
            "the live remote pools hash should reduce to the absent-route preimage"
        );
        assertEq(
            expectedHashes[2],
            keccak256(
                abi.encode(timelock.ROUTE_IDENTITY_DOMAIN(), CHAIN_SELECTOR_A, false, bytes(""))
            ),
            "the live route identity hash should reduce to the absent-route preimage"
        );

        uint64 expectedActionId = timelock.nextActionId();
        // executableAt = now + 1 days (the delay); expiresAt = executableAt + 3 days (the
        // execution window)
        uint48 expectedExecutableAt = uint48(vm.getBlockTimestamp()) + TIMELOCK_DELAY;
        uint48 expectedExpiresAt = expectedExecutableAt + 3 days;
        bytes32 batchHash = keccak256(abi.encode(_singleActionBatch(_addChainBatchAction(update))));

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
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            expectedActionId,
            0,
            keys[1],
            1,
            address(config),
            expectedHashes[1]
        );
        vm.expectEmit(true, true, true, true, address(timelock));
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            expectedActionId,
            0,
            keys[2],
            2,
            address(config),
            expectedHashes[2]
        );
        vm.expectEmit(true, true, true, true, address(timelock));
        emit ITimelockBatchQueue.TimelockSubActionQueued(
            expectedActionId,
            address(config),
            ICCIPTokenPoolConfig.addChain.selector,
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
        uint64 actionId = timelock.queueAddChain(update);

        assertEq(actionId, expectedActionId, "the returned action id should be the first id");
        assertEq(timelock.nextActionId(), expectedActionId + 1, "nextActionId should increment");
        _assertQueuedSingleAction(
            actionId,
            bridgeAdmin,
            ICCIPTokenPoolConfig.addChain.selector,
            payload,
            keys,
            expectedHashes
        );
    }

    // when the outbound rate is one below the capacity
    //   [X] it queues successfully
    // The passing side of the non-strict rate boundary
    function test_whenOutboundRateIsOneBelowCapacity() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        // rate = capacity - 1 is the largest accepted rate for the capacity
        update.outboundRateLimiterConfig = _rateLimiterConfig(
            true,
            DEFAULT_OUTBOUND_CAPACITY,
            DEFAULT_OUTBOUND_CAPACITY - 1
        );

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueAddChain(update);

        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, actionId, "boundary queue");
    }

    // when both configurations are the minimal enabled shape {true, 2, 1}
    //   [X] it queues successfully
    // The containment shape is a legal addChain configuration (rate 1 below capacity 2)
    function test_whenRateLimitConfigsAreMinimal() public givenEnabled {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(CHAIN_SELECTOR_A);
        update.outboundRateLimiterConfig = _containmentConfig();
        update.inboundRateLimiterConfig = _containmentConfig();

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueAddChain(update);

        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, actionId, "minimal-config queue");
    }

    // when the selector is the uint64 maximum
    //   [X] it queues successfully and reserves the keys of that selector
    function test_whenSelectorIsUint64Max() public givenEnabled {
        uint64 actionId = _queueAddChainAction(type(uint64).max);

        _assertRouteKeysHeldBy(type(uint64).max, actionId, "maximum-selector queue");
    }

    // given an addChain action for another selector is already queued
    //   [X] it queues with a sequential id
    //   [X] each action holds only the keys of its own selector
    // Cross-route independence of the reservation bookkeeping
    function test_givenAnotherChainActionQueued() public givenEnabled {
        uint64 firstActionId = _queueAddChainAction(CHAIN_SELECTOR_A);

        uint64 secondActionId = _queueAddChainAction(CHAIN_SELECTOR_B);

        assertEq(secondActionId, firstActionId + 1, "the ids should be sequential");
        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, firstActionId, "first route");
        _assertRouteKeysHeldBy(CHAIN_SELECTOR_B, secondActionId, "second route");
    }
}
