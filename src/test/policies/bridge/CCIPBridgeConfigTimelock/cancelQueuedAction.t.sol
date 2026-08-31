// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BRIDGE_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPBridgeConfigTimelockTest} from "./CCIPBridgeConfigTimelockTest.sol";

contract CCIPBridgeConfigTimelockTests_cancelQueuedAction is CCIPBridgeConfigTimelockTest {
    // when the caller is not the admin, not the emergency role and not the proposer
    //   [X] it reverts with NotAuthorised
    // Fuzzed; excludes the three authorized identities
    function test_whenCallerIsNotAuthorized_reverts(
        address caller_
    ) public givenEnabled givenChainAdded givenActionQueued {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != emergency);
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != address(0));

        _expectRevertNotAuthorised();
        vm.prank(caller_);
        timelock.cancelQueuedAction(queuedActionId);
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with NotAuthorised
    // The bridge rate limiter holds no timelock authority at all
    function test_whenCallerIsBridgeRateLimiter_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        _expectRevertNotAuthorised();
        vm.prank(bridgeRateLimiter);
        timelock.cancelQueuedAction(queuedActionId);
    }

    // when the caller holds the bridge admin role but is not the proposer
    //   [X] it reverts with NotAuthorised
    // Proposership is personal, not role-based: a second bridge admin granted in the body
    // cannot cancel another proposer's action
    function test_whenCallerIsAnotherBridgeAdmin_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        address secondBridgeAdmin = makeAddr("secondBridgeAdmin");
        rolesAdmin.grantRole(BRIDGE_ADMIN_ROLE, secondBridgeAdmin);

        _expectRevertNotAuthorised();
        vm.prank(secondBridgeAdmin);
        timelock.cancelQueuedAction(queuedActionId);
    }

    // when the caller is the admin
    //   [X] it marks the action cancelled
    //   [X] it releases every reserved key and pendingActionId answers zero
    //   [X] it emits TimelockActionCancelled with the caller
    //   [X] the freed domain can be queued again with a fresh id
    //   [X] getQueuedAction still reports the metadata with the cancelled flag
    function test_whenCallerIsAdmin() public givenEnabled givenChainAdded givenActionQueued {
        vm.expectEmit(true, true, true, true, address(timelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(queuedActionId, admin);
        vm.prank(admin);
        timelock.cancelQueuedAction(queuedActionId);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be released"
        );

        ITimelockBatchQueue.QueuedAction memory action = timelock.getQueuedAction(queuedActionId);
        assertTrue(action.cancelled, "the cancelled flag should be set");
        assertFalse(action.executed, "the executed flag should stay clear");
        assertEq(action.proposer, bridgeAdmin, "the proposer metadata should be retained");
        assertEq(action.actions.length, 0, "the sub-actions should be cleared");

        uint64 newActionId = _queueRateLimitAction(CHAIN_SELECTOR_A);
        assertEq(newActionId, queuedActionId + 1, "the freed domain should re-queue freshly");
    }

    // when the caller holds the emergency role
    //   [X] it cancels and releases the keys
    function test_whenCallerIsEmergency() public givenEnabled givenChainAdded givenActionQueued {
        vm.prank(emergency);
        timelock.cancelQueuedAction(queuedActionId);

        assertTrue(
            timelock.getQueuedAction(queuedActionId).cancelled,
            "the action should be cancelled"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be released"
        );
    }

    // when the caller is the proposer
    //   [X] it cancels and releases the keys
    // The proposer is the bridge admin account that queued the canonical action
    function test_whenCallerIsProposer() public givenEnabled givenChainAdded givenActionQueued {
        vm.prank(bridgeAdmin);
        timelock.cancelQueuedAction(queuedActionId);

        assertTrue(
            timelock.getQueuedAction(queuedActionId).cancelled,
            "the action should be cancelled"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be released"
        );
    }

    // when the caller is the proposer
    //   given the proposer has lost the bridge admin role
    //     [X] it cancels
    // The proposer comparison is by address, so losing the role does not remove personal
    // agency over the queued action
    function test_whenCallerIsProposer_givenProposerLostRole()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        rolesAdmin.revokeRole(BRIDGE_ADMIN_ROLE, bridgeAdmin);

        vm.prank(bridgeAdmin);
        timelock.cancelQueuedAction(queuedActionId);

        assertTrue(
            timelock.getQueuedAction(queuedActionId).cancelled,
            "the roleless proposer should still cancel its own action"
        );
    }

    // given the timelock is disabled
    //   [X] it cancels
    // Stale actions can be cleared before re-enabling; no lifecycle gate exists on
    // cancellation
    function test_givenTimelockDisabled()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenDisabled
    {
        vm.prank(bridgeAdmin);
        timelock.cancelQueuedAction(queuedActionId);

        assertTrue(
            timelock.getQueuedAction(queuedActionId).cancelled,
            "the action should be cancelled while the timelock is disabled"
        );
    }

    // given the action has expired
    //   [X] it cancels and releases the keys
    //   [X] the freed domain can be queued again
    // The only release path for an expired action's keys: expiry alone frees nothing
    function test_givenActionExpired()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionExpired
    {
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            queuedActionId,
            "expiry alone should free nothing"
        );

        vm.prank(bridgeAdmin);
        timelock.cancelQueuedAction(queuedActionId);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the cancellation should release the expired action's key"
        );
        uint64 newActionId = _queueRateLimitAction(CHAIN_SELECTOR_A);
        assertEq(newActionId, queuedActionId + 1, "the freed domain should re-queue freshly");
    }

    // given the config policy is disabled
    //   [X] it cancels
    function test_givenConfigDisabled()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenConfigDisabled
    {
        vm.prank(bridgeAdmin);
        timelock.cancelQueuedAction(queuedActionId);

        assertTrue(
            timelock.getQueuedAction(queuedActionId).cancelled,
            "the action should be cancelled while the config is disabled"
        );
    }

    // given the config policy has been deactivated in the kernel
    //   [X] it cancels
    // Cancellation reads only ROLES and the stored proposer; a broken config binding does
    // not block it
    function test_givenConfigDeactivatedInKernel()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenConfigDeactivatedInKernel
    {
        vm.prank(bridgeAdmin);
        timelock.cancelQueuedAction(queuedActionId);

        assertTrue(
            timelock.getQueuedAction(queuedActionId).cancelled,
            "the action should be cancelled while the config is deactivated"
        );
    }

    // given the config operator has been rotated away
    //   [X] it cancels and releases the keys
    // The migration flow: the outgoing timelock's queue is cleared through cancellation
    // while the seat already points elsewhere
    function test_givenOperatorRotated()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenOperatorRotated
    {
        vm.prank(bridgeAdmin);
        timelock.cancelQueuedAction(queuedActionId);

        assertTrue(
            timelock.getQueuedAction(queuedActionId).cancelled,
            "the outgoing timelock's action should be cancelled"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be released"
        );
    }

    // given the config lost the pool ownership
    //   [X] it cancels and releases the keys
    // The runbook cleanup path for actions that would revert at dispatch forever
    function test_givenPoolOwnershipLost()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenPoolOwnershipLost
    {
        vm.prank(bridgeAdmin);
        timelock.cancelQueuedAction(queuedActionId);

        assertTrue(
            timelock.getQueuedAction(queuedActionId).cancelled,
            "the undispatchable action should be cancelled"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be released"
        );
    }

    // given the action was invalidated by a direct state change
    //   [X] it cancels and releases the drifted domain
    //   [X] the freed domain can be queued again against the new state
    // The recovery flow after a direct admin change invalidated the recorded hash
    function test_givenActionInvalidatedByDrift()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        // The direct write moves the rate limits hash away from the recorded one, so the
        // canonical action can never execute again
        _directSetChainRateLimits(
            CHAIN_SELECTOR_A,
            _rateLimiterConfig(true, 7_000, 70),
            _rateLimiterConfig(true, 9_000, 90)
        );

        vm.prank(bridgeAdmin);
        timelock.cancelQueuedAction(queuedActionId);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the drifted domain should be released"
        );
        uint64 newActionId = _queueRateLimitAction(CHAIN_SELECTOR_A);
        assertEq(
            newActionId,
            queuedActionId + 1,
            "the freed domain should re-queue against the new state"
        );
    }

    // given a multi-domain batch is queued
    //   [X] it releases every key of every sub-action
    function test_givenBatchActionQueued() public givenEnabled givenChainAdded {
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](2);
        batch[0] = _setChainRateLimitsBatchAction(
            CHAIN_SELECTOR_A,
            _canonicalOutboundConfig(),
            _canonicalInboundConfig()
        );
        batch[1] = _addRemotePoolBatchAction(CHAIN_SELECTOR_A, REMOTE_POOL_THREE);
        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueBatch(batch);

        vm.prank(admin);
        timelock.cancelQueuedAction(actionId);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be released"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            0,
            "the remote pools key should be released"
        );
    }
}
