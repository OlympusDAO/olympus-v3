// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BRIDGE_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPTokenPoolConfigTimelockTest} from "./CCIPTokenPoolConfigTimelockTest.sol";

contract CCIPTokenPoolConfigTimelockTests_queueRemoveChain is CCIPTokenPoolConfigTimelockTest {
    // ========== SHARED QUEUE GATE LADDER ========== //

    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    // The setUp default state; the Q1/Q2 order is unobservable (both raise NotEnabled)
    function test_givenTimelockDisabled_reverts() public givenChainAdded {
        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
    }

    // given the config policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenConfigDisabled_reverts()
        public
        givenEnabled
        givenChainAdded
        givenConfigDisabled
    {
        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
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
        _expectRevertNotEnabled();
        vm.prank(thirdParty);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
    }

    // when the caller does not hold the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Fuzzed; excludes the bridge admin account
    function test_whenCallerIsNotBridgeAdmin_reverts(
        address caller_
    ) public givenEnabled givenChainAdded {
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(caller_);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
    }

    // when the caller holds the admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // The admin removes routes directly on the config, never through the queue
    function test_whenCallerIsAdmin_reverts() public givenEnabled givenChainAdded {
        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(admin);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenChainAdded {
        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(emergency);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled givenChainAdded {
        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
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
        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(thirdParty);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
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
        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
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
        _expectRevertNotConfigOperator(address(0));
        vm.prank(bridgeAdmin);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
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
        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
    }

    // ========== VALIDATION MIRROR ========== //

    // given the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    function test_givenRouteDoesNotExist_reverts() public givenEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(bridgeAdmin);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);

        _assertRouteKeysFree(CHAIN_SELECTOR_A, "after the rejected queue");
    }

    // ========== KEY CONFLICTS ========== //

    // given a removal of the same route is already queued
    //   [X] it reverts with ConfigKeyPending carrying the rate limits key and the holder id
    // A three-domain conflict names the first key in the _configKeys order
    function test_givenSameRouteRemovalAlreadyQueued_reverts() public givenEnabled givenChainAdded {
        uint64 holderActionId = _queueRemoveChainAction(CHAIN_SELECTOR_A);

        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
    }

    // given a rate limit action is pending for the route
    //   [X] it reverts with ConfigKeyPending carrying the rate limits key and the holder id
    // The spec exclusion: a limit change and a removeChain can never coexist for one route.
    // This pins the direction where the limit change is queued first; the reverse direction
    // is pinned in the queueSetChainRateLimits pass.
    function test_givenRateLimitActionPending_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(CHAIN_SELECTOR_A), queuedActionId);
        vm.prank(bridgeAdmin);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
    }

    // given a remote pool action is pending for the route
    //   [X] it reverts with ConfigKeyPending carrying the remote pools key and the holder id
    // The rate limits key is free, so the walk reaches and rejects on the second key
    function test_givenRemotePoolActionPending_reverts() public givenEnabled givenChainAdded {
        uint64 holderActionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be free before the conflicting queue"
        );

        _expectRevertConfigKeyPending(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueRemoveChain(CHAIN_SELECTOR_A);
    }

    // ========== SUCCESS ========== //

    // when the caller is the bridge admin
    //   [X] it returns the action id and increments nextActionId
    //   [X] it reserves the rate limits, remote pools and route identity keys of the route
    //   [X] the stored hashes equal the recomputed live-route preimages: the default bucket
    //       configurations, the two-pool aggregate with count two, and the identity over
    //       (true, remote token)
    //   [X] it stores the destination, the config state count of three, the timestamps and
    //       the canonical payload
    //   [X] it emits three ConfigStateQueued events, one TimelockSubActionQueued and one
    //       TimelockActionQueued
    function test_whenCallerIsBridgeAdmin() public givenEnabled givenChainAdded {
        bytes memory payload = abi.encode(CHAIN_SELECTOR_A);

        // The scoped keys in _configKeys order: rate limits, remote pools, route identity
        bytes32[] memory keys = new bytes32[](3);
        keys[0] = timelock.getRateLimitsKey(CHAIN_SELECTOR_A);
        keys[1] = timelock.getRemotePoolsKey(CHAIN_SELECTOR_A);
        keys[2] = timelock.getRouteIdentityKey(CHAIN_SELECTOR_A);

        bytes32[] memory expectedHashes = new bytes32[](3);
        expectedHashes[0] = _expectedRateLimitsHash(CHAIN_SELECTOR_A);
        expectedHashes[1] = _expectedRemotePoolsHash(CHAIN_SELECTOR_A);
        expectedHashes[2] = _expectedRouteIdentityHash(CHAIN_SELECTOR_A);

        // The route is live, so the recomputed hashes carry the fixture state: both buckets
        // enabled at the rig defaults, two remote pools whose keccak hashes XOR into the
        // aggregate, and a supported chain with the default remote token
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
            "the live rate limits hash should carry the default bucket configurations"
        );
        assertEq(
            expectedHashes[1],
            keccak256(
                abi.encode(
                    timelock.REMOTE_POOLS_DOMAIN(),
                    CHAIN_SELECTOR_A,
                    uint256(2),
                    keccak256(REMOTE_POOL_ONE) ^ keccak256(REMOTE_POOL_TWO)
                )
            ),
            "the live remote pools hash should carry the two-pool aggregate"
        );
        assertEq(
            expectedHashes[2],
            keccak256(
                abi.encode(timelock.ROUTE_IDENTITY_DOMAIN(), CHAIN_SELECTOR_A, true, REMOTE_TOKEN)
            ),
            "the live route identity hash should carry the supported chain and remote token"
        );

        uint64 expectedActionId = timelock.nextActionId();
        // executableAt = now + 1 days (the delay); expiresAt = executableAt + 3 days (the
        // execution window)
        uint48 expectedExecutableAt = uint48(vm.getBlockTimestamp()) + TIMELOCK_DELAY;
        uint48 expectedExpiresAt = expectedExecutableAt + 3 days;
        bytes32 batchHash = keccak256(
            abi.encode(_singleActionBatch(_removeChainBatchAction(CHAIN_SELECTOR_A)))
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
            ICCIPTokenPoolConfig.removeChain.selector,
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
        uint64 actionId = timelock.queueRemoveChain(CHAIN_SELECTOR_A);

        assertEq(actionId, expectedActionId, "the returned action id should be the next id");
        assertEq(timelock.nextActionId(), expectedActionId + 1, "nextActionId should increment");
        _assertQueuedSingleAction(
            actionId,
            bridgeAdmin,
            ICCIPTokenPoolConfig.removeChain.selector,
            payload,
            keys,
            expectedHashes
        );
    }

    // given the route is contained
    //   [X] it queues the removal successfully
    // validateRemoveChain checks existence only; containment must not block a queued
    // removal. The recorded rate-limits hash covers the containment shape {true, 2, 1}.
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

        uint64 actionId = _queueRemoveChainAction(CHAIN_SELECTOR_A);

        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, actionId, "contained-route removal");
        (, bytes32 storedRateLimitsHash) = timelock.getQueuedConfigState(actionId, 0, 0);
        assertEq(
            storedRateLimitsHash,
            containedRateLimitsHash,
            "the stored hash should be the containment-shape hash"
        );
    }

    // given a removal of another route is already queued
    //   [X] it queues with a sequential id
    //   [X] each action holds only the keys of its own route
    // Cross-route independence of the reservation bookkeeping
    function test_givenSecondChainRemovalQueued()
        public
        givenEnabled
        givenChainAdded
        givenSecondChainAdded
    {
        uint64 firstActionId = _queueRemoveChainAction(CHAIN_SELECTOR_B);

        uint64 secondActionId = _queueRemoveChainAction(CHAIN_SELECTOR_A);

        assertEq(secondActionId, firstActionId + 1, "the ids should be sequential");
        _assertRouteKeysHeldBy(CHAIN_SELECTOR_B, firstActionId, "second route removal");
        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, secondActionId, "first route removal");
    }
}
