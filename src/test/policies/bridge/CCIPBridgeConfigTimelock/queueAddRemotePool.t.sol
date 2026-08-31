// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BRIDGE_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPBridgeConfigTimelockTest} from "./CCIPBridgeConfigTimelockTest.sol";

contract CCIPBridgeConfigTimelockTests_queueAddRemotePool is CCIPBridgeConfigTimelockTest {
    // ========== SHARED QUEUE GATE LADDER ========== //

    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    // The setUp default state; the Q1/Q2 order is unobservable (both raise NotEnabled)
    function test_givenTimelockDisabled_reverts() public givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // given the config policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenConfigDisabled_reverts()
        public
        givenEnabled
        givenChainAdded
        givenConfigDisabled
    {
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
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
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertNotEnabled();
        vm.prank(thirdParty);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // when the caller does not hold the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Fuzzed; excludes the bridge admin account
    function test_whenCallerIsNotBridgeAdmin_reverts(
        address caller_
    ) public givenEnabled givenChainAdded {
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != address(0));
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(caller_);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // when the caller holds the admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsAdmin_reverts() public givenEnabled givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(admin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(emergency);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
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
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(thirdParty);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // given the config operator has been rotated to another account
    //   [X] it reverts with CCIPBridgeConfigTimelock_NotConfigOperator carrying the new
    //       operator
    function test_givenOperatorRotated_reverts()
        public
        givenEnabled
        givenChainAdded
        givenOperatorRotated
    {
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // given the config operator has been revoked
    //   [X] it reverts with CCIPBridgeConfigTimelock_NotConfigOperator carrying the zero
    //       address
    function test_givenOperatorRevoked_reverts()
        public
        givenEnabled
        givenChainAdded
        givenOperatorRevoked
    {
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertNotConfigOperator(address(0));
        vm.prank(bridgeAdmin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // given the config operator has been rotated away
    //   when the pool value is empty
    //     [X] it reverts with CCIPBridgeConfigTimelock_NotConfigOperator
    // Pins the gate order: the operator gate answers before the validation mirror
    function test_givenOperatorRotated_whenPoolIsEmpty_reverts()
        public
        givenEnabled
        givenChainAdded
        givenOperatorRotated
    {
        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, "");
    }

    // ========== VALIDATION MIRROR LADDER ========== //

    // given the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    function test_givenRouteDoesNotExist_reverts() public givenEnabled {
        bytes memory remotePool = REMOTE_POOL_THREE;

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(bridgeAdmin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // when the pool value is empty
    //   [X] it reverts with ZeroAddressNotAllowed
    function test_whenPoolIsEmpty_reverts() public givenEnabled givenChainAdded {
        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.ZeroAddressNotAllowed.selector));
        vm.prank(bridgeAdmin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, "");

        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            0,
            "the remote pools key should stay free after the rejected queue"
        );
    }

    // given the pool value is already accepted for the route
    //   [X] it reverts with PoolAlreadyAdded carrying the selector and the value
    function test_givenPoolIsAlreadyAccepted_reverts() public givenEnabled givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_ONE;

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.PoolAlreadyAdded.selector,
                CHAIN_SELECTOR_A,
                remotePool
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // ========== KEY CONFLICTS AND COEXISTENCE ========== //

    // given another pool addition is queued for the route
    //   [X] it reverts with ConfigKeyPending carrying the remote pools key and the holder id
    // Same domain, DIFFERENT value: one unresolved change per domain, regardless of value
    function test_givenAnotherPoolAdditionQueuedForRoute_reverts()
        public
        givenEnabled
        givenChainAdded
    {
        uint64 holderActionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);
        // A value distinct from the one the holder carries
        bytes memory remotePool = REMOTE_POOL_B;

        _expectRevertConfigKeyPending(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // given a pool removal is queued for the route
    //   [X] it reverts with ConfigKeyPending carrying the remote pools key and the holder id
    // The sibling one-key action reserves the same domain
    function test_givenPoolRemovalQueuedForRoute_reverts() public givenEnabled givenChainAdded {
        uint64 holderActionId = _queueRemoveRemotePoolAction(CHAIN_SELECTOR_A);
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertConfigKeyPending(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // given a token change is queued for the route
    //   [X] it reverts with ConfigKeyPending carrying the remote pools key and the holder id
    // A three-key holder blocks through its remote pools key
    function test_givenTokenChangeQueuedForRoute_reverts() public givenEnabled givenChainAdded {
        uint64 holderActionId = _queueSetRemoteTokenAction(CHAIN_SELECTOR_A);
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertConfigKeyPending(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // ========== SUCCESS ========== //

    // when the caller is the bridge admin
    //   [X] it returns the action id and increments nextActionId
    //   [X] it reserves ONLY the remote pools key: the rate limits and route identity keys
    //       of the route stay free
    //   [X] the stored hash equals the live two-pool aggregate with count two
    //   [X] it stores the destination, a config state count of ONE, the timestamps and the
    //       canonical payload
    //   [X] it emits one ConfigStateQueued, one TimelockSubActionQueued and one
    //       TimelockActionQueued
    // The narrowness assertion is the point: too-broad keys would break the coexistence
    // cases below
    function test_whenCallerIsBridgeAdmin() public givenEnabled givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_THREE;
        bytes memory payload = abi.encode(CHAIN_SELECTOR_A, remotePool);

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = timelock.getRemotePoolsKey(CHAIN_SELECTOR_A);

        bytes32[] memory expectedHashes = new bytes32[](1);
        expectedHashes[0] = _expectedRemotePoolsHash(CHAIN_SELECTOR_A);
        assertEq(
            expectedHashes[0],
            keccak256(
                abi.encode(
                    timelock.REMOTE_POOLS_DOMAIN(),
                    CHAIN_SELECTOR_A,
                    uint256(2),
                    keccak256(REMOTE_POOL_ONE) ^ keccak256(REMOTE_POOL_TWO)
                )
            ),
            "the recorded hash should be the live two-pool aggregate"
        );

        uint64 expectedActionId = timelock.nextActionId();
        // executableAt = now + 1 days (the delay); expiresAt = executableAt + 3 days (the
        // execution window)
        uint48 expectedExecutableAt = uint48(vm.getBlockTimestamp()) + TIMELOCK_DELAY;
        uint48 expectedExpiresAt = expectedExecutableAt + 3 days;
        bytes32 batchHash = keccak256(
            abi.encode(_singleActionBatch(_addRemotePoolBatchAction(CHAIN_SELECTOR_A, remotePool)))
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
            ICCIPBridgeConfig.addRemotePool.selector,
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
        uint64 actionId = timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);

        assertEq(actionId, expectedActionId, "the returned action id should be the next id");
        assertEq(timelock.nextActionId(), expectedActionId + 1, "nextActionId should increment");
        _assertQueuedSingleAction(
            actionId,
            bridgeAdmin,
            ICCIPBridgeConfig.addRemotePool.selector,
            payload,
            keys,
            expectedHashes
        );

        // The narrowness of the reservation: the two sibling domains of the route stay free
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should stay free"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRouteIdentityKey(CHAIN_SELECTOR_A)),
            0,
            "the route identity key should stay free"
        );
    }

    // given a rate limit action is pending for the route
    //   [X] it queues successfully with a sequential id
    //   [X] both actions hold disjoint keys
    // The coexistence the domain split exists for, order rate-limit-first
    function test_givenRateLimitActionPending()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        uint64 poolActionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);

        assertEq(poolActionId, queuedActionId + 1, "the ids should be sequential");
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            queuedActionId,
            "the rate limits key should stay with the rate limit action"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            poolActionId,
            "the remote pools key should belong to the pool action"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRouteIdentityKey(CHAIN_SELECTOR_A)),
            0,
            "the route identity key should stay free"
        );
    }

    // given a pool addition was queued first
    //   [X] a rate limit action for the same route queues successfully afterwards
    // The reverse order of the coexistence pair
    function test_givenPoolActionQueuedFirst() public givenEnabled givenChainAdded {
        uint64 poolActionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);

        uint64 rateLimitActionId = _queueRateLimitAction(CHAIN_SELECTOR_A);

        assertEq(rateLimitActionId, poolActionId + 1, "the ids should be sequential");
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            poolActionId,
            "the remote pools key should stay with the pool action"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            rateLimitActionId,
            "the rate limits key should belong to the rate limit action"
        );
    }

    // given a pool action is queued for another route
    //   [X] it queues successfully and each action holds only its own route's key
    function test_givenSecondRoutePoolActionQueued()
        public
        givenEnabled
        givenChainAdded
        givenSecondChainAdded
    {
        uint64 secondRouteActionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_B);

        uint64 firstRouteActionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);

        assertEq(firstRouteActionId, secondRouteActionId + 1, "the ids should be sequential");
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_B)),
            secondRouteActionId,
            "the second route's remote pools key should belong to its own action"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            firstRouteActionId,
            "the first route's remote pools key should belong to its own action"
        );
    }

    // when the pool value is non-EVM-shaped
    //   [X] it queues successfully
    // The mirror checks emptiness and membership only; a 64-byte value queues
    function test_whenPoolIsNonEvmShaped() public givenEnabled givenChainAdded {
        // Two words instead of the single word of an EVM-shaped address
        bytes memory remotePool = abi.encode(
            keccak256("nonEvmRemotePoolHigh"),
            keccak256("nonEvmRemotePoolLow")
        );
        assertEq(remotePool.length, 64, "the fixture pool value should be 64 bytes");

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueAddRemotePool(CHAIN_SELECTOR_A, remotePool);

        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            actionId,
            "the remote pools key should belong to the action"
        );
        (, , bytes memory storedPayload) = timelock.getQueuedSubAction(actionId, 0);
        assertEq(
            storedPayload,
            abi.encode(CHAIN_SELECTOR_A, remotePool),
            "the stored payload should carry the free-form pool value"
        );
    }
}
