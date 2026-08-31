// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";

import {CCIPBridgeConfigTimelockTest} from "./CCIPBridgeConfigTimelockTest.sol";

contract CCIPBridgeConfigTimelockTests_executeQueuedAction is CCIPBridgeConfigTimelockTest {
    // ========== FILE-LOCAL HELPERS ========== //

    /// @notice Executes an action as the uninvolved third party.
    function _execute(uint64 actionId_) internal {
        vm.prank(thirdParty);
        timelock.executeQueuedAction(actionId_);
    }

    /// @notice Asserts the configuration fields of one bucket; the volatile fill level and
    ///         refill timestamp are deliberately not part of the comparison.
    function _assertBucketConfig(
        ICCIPRateLimiter.TokenBucket memory bucket_,
        ICCIPRateLimiter.Config memory expected_,
        string memory label_
    ) internal pure {
        assertEq(bucket_.isEnabled, expected_.isEnabled, string.concat(label_, ": isEnabled"));
        assertEq(bucket_.capacity, expected_.capacity, string.concat(label_, ": capacity"));
        assertEq(bucket_.rate, expected_.rate, string.concat(label_, ": rate"));
    }

    /// @notice Asserts that the canonical rate limit action's configurations landed on the
    ///         pool for route A.
    function _assertCanonicalRateLimitsApplied() internal view {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        _assertBucketConfig(
            rigPool.getCurrentOutboundRateLimiterState(CHAIN_SELECTOR_A),
            _canonicalOutboundConfig(),
            "outbound after execution"
        );
        _assertBucketConfig(
            rigPool.getCurrentInboundRateLimiterState(CHAIN_SELECTOR_A),
            _canonicalInboundConfig(),
            "inbound after execution"
        );
    }

    /// @notice Expects ConfigStateChanged for one stored config state of a single-sub-action
    ///         action (reading the stored hash back) and runs the execution as the third
    ///         party. The caller supplies the recomputed current hash.
    function _expectStateChangedAndExecute(
        uint64 actionId_,
        uint256 configStateIndex_,
        bytes32 key_,
        bytes32 currentStateHash_
    ) internal {
        (, bytes32 storedHash) = timelock.getQueuedConfigState(actionId_, 0, configStateIndex_);
        _expectRevertConfigStateChanged(actionId_, 0, key_, storedHash, currentStateHash_);
        vm.prank(thirdParty);
        timelock.executeQueuedAction(actionId_);
    }

    // ========== TIME BOUNDARIES (PRODUCT EDGES) ========== //

    // when the caller is any address
    //   [X] it executes the ready action
    // Execution is permissionless; the fuzz proves no dependence on one fixed address
    function test_whenCallerIsAnyAddress(
        address caller_
    ) public givenEnabled givenChainAdded givenActionQueued givenActionReady {
        vm.assume(caller_ != address(0));

        vm.prank(caller_);
        timelock.executeQueuedAction(queuedActionId);

        _assertCanonicalRateLimitsApplied();
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be released"
        );
    }

    // given the block timestamp equals executableAt
    //   [X] it executes
    // The readiness comparison is strict, so the boundary itself is open; pins the product
    // delay of one day end to end
    function test_givenTimestampEqualsExecutableAt()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
    {
        ITimelockBatchQueue.QueuedAction memory action = timelock.getQueuedAction(queuedActionId);
        assertEq(
            vm.getBlockTimestamp(),
            action.executableAt,
            "the block timestamp should sit exactly on executableAt"
        );

        _execute(queuedActionId);

        _assertCanonicalRateLimitsApplied();
    }

    // given the block timestamp equals expiresAt
    //   [X] it executes
    // The expiry comparison is strict, so the last second of the three-day window is open
    function test_givenTimestampEqualsExpiresAt()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        _warpToExpiresAt(queuedActionId);
        ITimelockBatchQueue.QueuedAction memory action = timelock.getQueuedAction(queuedActionId);
        assertEq(
            vm.getBlockTimestamp(),
            action.expiresAt,
            "the block timestamp should sit exactly on expiresAt"
        );

        _execute(queuedActionId);

        _assertCanonicalRateLimitsApplied();
    }

    // given the action has expired
    //   given the timelock is disabled
    //     [X] it reverts with ITimelockBatchQueue_ActionExpired
    // The base timestamp checks answer before the product gates: an expired action on a
    // disabled timelock reports the expiry, not NotEnabled
    function test_givenActionExpired_givenTimelockDisabled_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionExpired
        givenDisabled
    {
        ITimelockBatchQueue.QueuedAction memory action = timelock.getQueuedAction(queuedActionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                queuedActionId,
                action.expiresAt
            )
        );
        _execute(queuedActionId);
    }

    // ========== EXECUTION GATE LADDER ========== //

    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    //   [X] every reserved key stays held
    function test_givenTimelockDisabled_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
        givenDisabled
    {
        _expectRevertNotEnabled();
        _execute(queuedActionId);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            queuedActionId,
            "the rate limits key should stay held"
        );
    }

    // given the timelock was disabled through the delay and re-enabled
    //   [X] it executes with no additional wait
    // The delay that elapses while disabled still counts: the action is executable the
    // moment the timelock returns
    function test_givenTimelockReEnabled()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenDisabled
        givenActionReady
        givenReEnabled
    {
        // The body skips no time: the delay elapsed under the disabled timelock and the
        // re-enable alone made the action executable
        _execute(queuedActionId);

        _assertCanonicalRateLimitsApplied();
    }

    // given the config policy is disabled
    //   [X] it reverts with NotEnabled
    //   [X] every reserved key stays held
    // The queued-then-config-disabled action holds its domains until executed after a
    // config re-enable, or cancelled
    function test_givenConfigDisabled_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
        givenConfigDisabled
    {
        _expectRevertNotEnabled();
        _execute(queuedActionId);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            queuedActionId,
            "the rate limits key should stay held"
        );
    }

    // given the config policy was disabled and re-enabled
    //   [X] it executes
    function test_givenConfigReEnabled()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
    {
        vm.prank(admin);
        config.disable("");
        vm.prank(admin);
        config.enable("");

        _execute(queuedActionId);

        _assertCanonicalRateLimitsApplied();
    }

    // given the config operator has been rotated to another account
    //   [X] it reverts with CCIPBridgeConfigTimelock_NotConfigOperator carrying the new
    //       operator
    //   [X] every reserved key stays held
    function test_givenOperatorRotated_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
        givenOperatorRotated
    {
        _expectRevertNotConfigOperator(thirdParty);
        _execute(queuedActionId);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            queuedActionId,
            "the rate limits key should stay held"
        );
    }

    // given the config operator has been revoked
    //   [X] it reverts with CCIPBridgeConfigTimelock_NotConfigOperator carrying the zero
    //       address
    //   [X] every reserved key stays held
    function test_givenOperatorRevoked_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
        givenOperatorRevoked
    {
        _expectRevertNotConfigOperator(address(0));
        _execute(queuedActionId);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            queuedActionId,
            "the rate limits key should stay held"
        );
    }

    // given the config operator was rotated away and restored
    //   [X] it executes
    // The outgoing timelock's actions become executable again when the seat returns
    function test_givenOperatorRestored()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
    {
        address timelockAddress = address(timelock);
        vm.prank(admin);
        config.setConfigOperator(thirdParty);
        vm.prank(admin);
        config.setConfigOperator(timelockAddress);

        _execute(queuedActionId);

        _assertCanonicalRateLimitsApplied();
    }

    // ========== DRIFT MATRIX ========== //

    // given the rate limits were changed directly by the admin
    //   [X] it reverts with ConfigStateChanged carrying the rate limits key, the stored
    //       hash and the recomputed current hash
    //   [X] every reserved key stays held
    function test_givenRateLimitsChangedDirectly_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
    {
        _directSetChainRateLimits(
            CHAIN_SELECTOR_A,
            _rateLimiterConfig(true, 7_000, 70),
            _rateLimiterConfig(true, 9_000, 90)
        );

        _expectStateChangedAndExecute(
            queuedActionId,
            0,
            timelock.getRateLimitsKey(CHAIN_SELECTOR_A),
            _expectedRateLimitsHash(CHAIN_SELECTOR_A)
        );

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            queuedActionId,
            "the rate limits key should stay held after the drift revert"
        );
    }

    // given the route was contained by the emergency role
    //   [X] it reverts with ConfigStateChanged on the rate limits key
    // Containment rewrites capacity and rate, which sit inside the hash: a delayed action
    // cannot silently overwrite an emergency containment
    function test_givenRouteContainedByEmergency_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
    {
        _containRoute(CHAIN_SELECTOR_A, emergency);

        _expectStateChangedAndExecute(
            queuedActionId,
            0,
            timelock.getRateLimitsKey(CHAIN_SELECTOR_A),
            _expectedRateLimitsHash(CHAIN_SELECTOR_A)
        );
    }

    // given the route was contained by the bridge admin
    //   [X] it reverts with ConfigStateChanged on the rate limits key
    // The containment group extends beyond emergency; each holder invalidates alike
    function test_givenRouteContainedByBridgeAdmin_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
    {
        _containRoute(CHAIN_SELECTOR_A, bridgeAdmin);

        _expectStateChangedAndExecute(
            queuedActionId,
            0,
            timelock.getRateLimitsKey(CHAIN_SELECTOR_A),
            _expectedRateLimitsHash(CHAIN_SELECTOR_A)
        );
    }

    // given the route was contained by the bridge rate limiter
    //   [X] it reverts with ConfigStateChanged on the rate limits key
    function test_givenRouteContainedByBridgeRateLimiter_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
    {
        _containRoute(CHAIN_SELECTOR_A, bridgeRateLimiter);

        _expectStateChangedAndExecute(
            queuedActionId,
            0,
            timelock.getRateLimitsKey(CHAIN_SELECTOR_A),
            _expectedRateLimitsHash(CHAIN_SELECTOR_A)
        );
    }

    // given a remote pool was added directly by the admin
    //   [X] it reverts with ConfigStateChanged on the remote pools key
    // The queued action is a pool removal, so its only key is the drifted domain
    function test_givenRemotePoolAddedDirectly_reverts() public givenEnabled givenChainAdded {
        uint64 actionId = _queueRemoveRemotePoolAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);
        _directAddRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_THREE);

        _expectStateChangedAndExecute(
            actionId,
            0,
            timelock.getRemotePoolsKey(CHAIN_SELECTOR_A),
            _expectedRemotePoolsHash(CHAIN_SELECTOR_A)
        );
    }

    // given a remote pool was removed directly by the admin
    //   [X] it reverts with ConfigStateChanged on the remote pools key
    // The queued action is a pool addition of a fresh value
    function test_givenRemotePoolRemovedDirectly_reverts() public givenEnabled givenChainAdded {
        uint64 actionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);
        _directRemoveRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);

        _expectStateChangedAndExecute(
            actionId,
            0,
            timelock.getRemotePoolsKey(CHAIN_SELECTOR_A),
            _expectedRemotePoolsHash(CHAIN_SELECTOR_A)
        );
    }

    // given the remote token was replaced directly by the admin
    //   [X] it reverts with ConfigStateChanged naming exactly the route identity key
    // The precision case: the direct replacement preserves configurations, pools and
    // fills, so the rate limits and remote pools hashes still match and only the identity
    // hash differs. The queued action is a removeChain holding all three domains.
    function test_givenRemoteTokenReplacedDirectly_reverts() public givenEnabled givenChainAdded {
        uint64 actionId = _queueRemoveChainAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);
        _directSetRemoteToken(CHAIN_SELECTOR_A, REMOTE_TOKEN_B);

        // The walk over the stored states passes the rate limits (index 0) and remote pools
        // (index 1) checks and fails on the identity state at index 2
        _expectStateChangedAndExecute(
            actionId,
            2,
            timelock.getRouteIdentityKey(CHAIN_SELECTOR_A),
            _expectedRouteIdentityHash(CHAIN_SELECTOR_A)
        );
    }

    // given the route was removed directly by the admin
    //   [X] it reverts with ConfigStateChanged on the remote pools key
    // The queued action is a pool removal; the emptied set drifts the aggregate and the
    // count
    function test_givenRouteRemovedDirectly_reverts() public givenEnabled givenChainAdded {
        uint64 actionId = _queueRemoveRemotePoolAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);
        _directRemoveChain(CHAIN_SELECTOR_A);

        _expectStateChangedAndExecute(
            actionId,
            0,
            timelock.getRemotePoolsKey(CHAIN_SELECTOR_A),
            _expectedRemotePoolsHash(CHAIN_SELECTOR_A)
        );
    }

    // given the route was removed and re-added with a different token
    //   [X] it reverts with ConfigStateChanged naming the route identity key
    // The re-add restores configurations and pools identically, so the identity hash is
    // the one that stays drifted
    function test_givenRouteRemovedAndReAddedWithDifferentToken_reverts()
        public
        givenEnabled
        givenChainAdded
    {
        uint64 actionId = _queueRemoveChainAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);
        _directRemoveChain(CHAIN_SELECTOR_A);
        _directAddChain(
            _chainUpdate(
                CHAIN_SELECTOR_A,
                _defaultRemotePools(),
                REMOTE_TOKEN_B,
                _defaultOutboundConfig(),
                _defaultInboundConfig()
            )
        );

        _expectStateChangedAndExecute(
            actionId,
            2,
            timelock.getRouteIdentityKey(CHAIN_SELECTOR_A),
            _expectedRouteIdentityHash(CHAIN_SELECTOR_A)
        );
    }

    // given the allowlist was mutated directly by the admin
    //   [X] it reverts with ConfigStateChanged on the allowlist key
    // Runs on the allowlist rig with a queued allowlist action
    function test_givenAllowListMutatedDirectly_reverts()
        public
        givenAllowListPoolRig
        givenEnabled
    {
        uint64 actionId = _queueApplyAllowListUpdatesAction();
        _warpToExecutableAt(actionId);
        _directApplyAllowListUpdates(_singleAddress(allowListedTwo), new address[](0));

        _expectStateChangedAndExecute(
            actionId,
            0,
            timelock.getAllowListKey(),
            _expectedAllowListHash()
        );

        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            actionId,
            "the allowlist key should stay held after the drift revert"
        );
    }

    // ========== NON-DRIFT: STATE-BASED DETECTION AND VOLATILE FIELDS ========== //

    // given the route was removed and re-added with identical parameters
    //   [X] it executes
    // Drift detection is state-based, not history-based: a perfectly restored route makes
    // every hash match again
    function test_givenRouteRemovedAndReAddedIdentically() public givenEnabled givenChainAdded {
        uint64 actionId = _queueRateLimitAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);
        _directRemoveChain(CHAIN_SELECTOR_A);
        _directAddChain(_defaultChainUpdate(CHAIN_SELECTOR_A));

        _execute(actionId);

        _assertCanonicalRateLimitsApplied();
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be released"
        );
    }

    // given a middle remote pool was removed and re-added directly
    //   [X] it executes
    // The enumerable set moves the last member into the removed slot, changing the array
    // order but not the membership; the XOR aggregate is order-independent. Requires a
    // third pool added before queueing.
    function test_givenMiddleRemotePoolRemovedAndReAdded() public givenEnabled givenChainAdded {
        _directAddRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_THREE);
        // The stored hash covers the set {ONE, TWO, THREE} in the array order [ONE, TWO,
        // THREE]
        uint64 actionId = _queueRemoveRemotePoolAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);
        // Removing the middle member moves THREE into its slot ([ONE, THREE]) and the
        // re-add appends TWO ([ONE, THREE, TWO]): same membership, different order
        _directRemoveRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);
        _directAddRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_TWO);

        _execute(actionId);

        bytes[] memory remotePools = ICCIPTokenPoolAdmin(config.pool()).getRemotePools(
            CHAIN_SELECTOR_A
        );
        assertEq(remotePools.length, 2, "the executed removal should leave two remote pools");
        assertEq(remotePools[0], REMOTE_POOL_ONE, "the first remaining pool");
        assertEq(remotePools[1], REMOTE_POOL_THREE, "the second remaining pool");
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            0,
            "the remote pools key should be released"
        );
    }

    // given the outbound bucket was spent through a real transfer
    //   [X] it executes
    // Volatile state is not drift: tokens and lastUpdated are excluded from the preimage.
    // The spend goes through lockOrBurn from the mocked on-ramp with the RMN proxy armed.
    function test_givenOutboundBucketSpent()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
    {
        _consumeOutbound(CHAIN_SELECTOR_A, 500);

        _execute(queuedActionId);

        _assertCanonicalRateLimitsApplied();
    }

    // given the bucket was spent and partially refilled over skipped time
    //   [X] it executes
    // The refill projection moves tokens and lastUpdated between queueing and execution
    function test_givenBucketPartiallyRefilled()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        ITimelockBatchQueue.QueuedAction memory action = timelock.getQueuedAction(queuedActionId);
        // Land two seconds short of readiness, spend, then let the remainder refill part of
        // the spend
        skip(uint256(action.executableAt) - vm.getBlockTimestamp() - 2);
        _consumeOutbound(CHAIN_SELECTOR_A, 500);
        skip(2);

        // The bucket was full at 10_000 (18 hours of refill at 100 per second far exceeds
        // the capacity); the spend removes 500 and the two skipped seconds refill
        // 2 * 100 = 200. Expected: 10_000 - 500 + 200 = 9_700, still below the capacity, so
        // the fill is partially refilled at execution time.
        ICCIPRateLimiter.TokenBucket memory outbound = ICCIPTokenPoolAdmin(config.pool())
            .getCurrentOutboundRateLimiterState(CHAIN_SELECTOR_A);
        assertEq(outbound.tokens, 9_700, "the projected fill should be partially refilled");

        _execute(queuedActionId);

        _assertCanonicalRateLimitsApplied();
    }

    // given a domain of the route the action never reserved changed directly
    //   [X] it executes
    //   [X] the unreserved domain keeps the value the direct writer left
    // The drift check covers only the keys the action actually reserved: a one-key pool
    // addition is untouched by a direct rewrite of the same route's rate limits. This is the
    // execution-side counterpart of the narrowness the queue passes assert on reservations.
    function test_givenUnreservedDomainChangedDirectly() public givenEnabled givenChainAdded {
        // A pool addition reserves the remote pools domain alone
        uint64 actionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "a pool addition should never reserve the rate limits key"
        );
        _warpToExecutableAt(actionId);
        // The admin rewrites the sibling rate limits domain of the same route
        _directSetChainRateLimits(
            CHAIN_SELECTOR_A,
            _canonicalOutboundConfig(),
            _canonicalInboundConfig()
        );

        _execute(actionId);

        assertTrue(
            ICCIPTokenPoolAdmin(config.pool()).isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_THREE),
            "the queued remote pool should be accepted"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            0,
            "the remote pools key should be released"
        );
        // The dispatch left the sibling domain exactly as the direct writer wrote it
        _assertCanonicalRateLimitsApplied();
    }

    // ========== HAPPY PATHS PER SELECTOR ========== //

    // given a ready addChain action
    //   [X] it creates the route on the pool with the queued parameters
    //   [X] the pool and config events interleave before TimelockSubActionExecuted, and
    //       TimelockActionExecuted closes the log
    //   [X] all three keys are released and pendingActionId answers zero
    // The event-interleaving assertion uses recorded logs; the richest dispatch carries it
    function test_givenChainActionReady() public givenEnabled {
        uint64 actionId = _queueAddChainAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);

        vm.recordLogs();
        _execute(actionId);

        // The dispatch order is: the pool writes and emits (ChainAdded among others), the
        // config closes its call with RouteAdded, the base emits TimelockSubActionExecuted
        // for the sub-action, and TimelockActionExecuted closes the batch
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 chainAddedIndex = _indexOfLog(
            logs,
            config.pool(),
            ICCIPTokenPoolAdmin.ChainAdded.selector,
            "pool ChainAdded"
        );
        uint256 routeAddedIndex = _indexOfLog(
            logs,
            address(config),
            ICCIPBridgeConfig.RouteAdded.selector,
            "config RouteAdded"
        );
        uint256 subActionExecutedIndex = _indexOfLog(
            logs,
            address(timelock),
            ITimelockBatchQueue.TimelockSubActionExecuted.selector,
            "TimelockSubActionExecuted"
        );
        uint256 actionExecutedIndex = _indexOfLog(
            logs,
            address(timelock),
            ITimelockBatchQueue.TimelockActionExecuted.selector,
            "TimelockActionExecuted"
        );
        assertLt(
            chainAddedIndex,
            routeAddedIndex,
            "the pool event should precede the config event"
        );
        assertLt(
            routeAddedIndex,
            subActionExecutedIndex,
            "the target events should precede TimelockSubActionExecuted"
        );
        assertLt(
            subActionExecutedIndex,
            actionExecutedIndex,
            "TimelockActionExecuted should close the log"
        );

        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        assertTrue(rigPool.isSupportedChain(CHAIN_SELECTOR_A), "the route should exist");
        assertEq(
            rigPool.getRemoteToken(CHAIN_SELECTOR_A),
            REMOTE_TOKEN,
            "the remote token should be the queued one"
        );
        assertEq(
            rigPool.getRemotePools(CHAIN_SELECTOR_A).length,
            2,
            "both queued remote pools should be accepted"
        );
        _assertBucketConfig(
            rigPool.getCurrentOutboundRateLimiterState(CHAIN_SELECTOR_A),
            _defaultOutboundConfig(),
            "outbound after the dispatch"
        );
        _assertRouteKeysFree(CHAIN_SELECTOR_A, "after the execution");
    }

    // given a ready removeChain action
    //   [X] it removes the route from the pool
    //   [X] all three keys are released
    function test_givenRemoveChainActionReady() public givenEnabled givenChainAdded {
        uint64 actionId = _queueRemoveChainAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);

        _execute(actionId);

        assertFalse(
            ICCIPTokenPoolAdmin(config.pool()).isSupportedChain(CHAIN_SELECTOR_A),
            "the route should be removed"
        );
        _assertRouteKeysFree(CHAIN_SELECTOR_A, "after the execution");
    }

    // given a ready setRemoteToken action
    //   [X] it replaces the remote token and preserves the remote pools, both
    //       configurations and the bucket fills per the config's restore logic
    //   [X] all three keys are released
    function test_givenSetRemoteTokenActionReady() public givenEnabled givenChainAdded {
        uint64 actionId = _queueSetRemoteTokenAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);

        _execute(actionId);

        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        assertEq(
            rigPool.getRemoteToken(CHAIN_SELECTOR_A),
            REMOTE_TOKEN_B,
            "the remote token should be replaced"
        );
        bytes[] memory remotePools = rigPool.getRemotePools(CHAIN_SELECTOR_A);
        assertEq(remotePools.length, 2, "both remote pools should be preserved");
        assertEq(remotePools[0], REMOTE_POOL_ONE, "the first remote pool should be preserved");
        assertEq(remotePools[1], REMOTE_POOL_TWO, "the second remote pool should be preserved");
        // The buckets start full at route creation (tokens = capacity) and the elapsed day
        // keeps them full, so the restore writes back full fills: outbound 10_000 of
        // 10_000 and inbound 20_000 of 20_000
        ICCIPRateLimiter.TokenBucket memory outbound = rigPool.getCurrentOutboundRateLimiterState(
            CHAIN_SELECTOR_A
        );
        _assertBucketConfig(outbound, _defaultOutboundConfig(), "outbound after the replacement");
        assertEq(
            outbound.tokens,
            DEFAULT_OUTBOUND_CAPACITY,
            "the outbound fill should be restored"
        );
        ICCIPRateLimiter.TokenBucket memory inbound = rigPool.getCurrentInboundRateLimiterState(
            CHAIN_SELECTOR_A
        );
        _assertBucketConfig(inbound, _defaultInboundConfig(), "inbound after the replacement");
        assertEq(inbound.tokens, DEFAULT_INBOUND_CAPACITY, "the inbound fill should be restored");
        _assertRouteKeysFree(CHAIN_SELECTOR_A, "after the execution");
    }

    // given a ready addRemotePool action
    //   [X] it adds the remote pool on the pool
    //   [X] the remote pools key is released
    function test_givenAddRemotePoolActionReady() public givenEnabled givenChainAdded {
        uint64 actionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);

        _execute(actionId);

        bytes[] memory remotePools = ICCIPTokenPoolAdmin(config.pool()).getRemotePools(
            CHAIN_SELECTOR_A
        );
        assertEq(remotePools.length, 3, "the queued remote pool should be added");
        assertEq(remotePools[2], REMOTE_POOL_THREE, "the appended pool should be the queued one");
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            0,
            "the remote pools key should be released"
        );
    }

    // given a ready removeRemotePool action
    //   [X] it removes the remote pool on the pool
    //   [X] the remote pools key is released
    function test_givenRemoveRemotePoolActionReady() public givenEnabled givenChainAdded {
        uint64 actionId = _queueRemoveRemotePoolAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);

        _execute(actionId);

        bytes[] memory remotePools = ICCIPTokenPoolAdmin(config.pool()).getRemotePools(
            CHAIN_SELECTOR_A
        );
        assertEq(remotePools.length, 1, "the queued remote pool should be removed");
        assertEq(remotePools[0], REMOTE_POOL_ONE, "the remaining pool should be the first one");
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            0,
            "the remote pools key should be released"
        );
    }

    // given the ready canonical rate limit action
    //   [X] it writes both bucket configurations on the pool
    //   [X] the rate limits key is released and pendingActionId answers zero
    function test_givenRateLimitActionReady()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
    {
        _execute(queuedActionId);

        _assertCanonicalRateLimitsApplied();
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be released"
        );
    }

    // given a ready allowlist action on the allowlist rig
    //   [X] it applies the removes and adds on the pool
    //   [X] the allowlist key is released
    function test_givenAllowListActionReady() public givenAllowListPoolRig givenEnabled {
        uint64 actionId = _queueApplyAllowListUpdatesAction();
        _warpToExecutableAt(actionId);

        _execute(actionId);

        address[] memory allowList = ICCIPTokenPoolAdmin(config.pool()).getAllowList();
        assertEq(allowList.length, 3, "the canonical addition should extend the allowlist");
        assertEq(allowList[2], allowListedThree, "the appended member should be the queued one");
        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            0,
            "the allowlist key should be released"
        );
    }

    // given a ready multi-domain batch
    //   [X] it dispatches the sub-actions in array order
    //   [X] every key of every sub-action is released only after the whole batch
    // A rate limit sub-action plus a pool addition on one route. An earlier sub-action
    // invalidating a later hash is unreachable in this product: every dispatch writes only
    // the domains its own action reserves.
    function test_givenMultiDomainBatchReady() public givenEnabled givenChainAdded {
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](2);
        batch[0] = _setChainRateLimitsBatchAction(
            CHAIN_SELECTOR_A,
            _canonicalOutboundConfig(),
            _canonicalInboundConfig()
        );
        batch[1] = _addRemotePoolBatchAction(CHAIN_SELECTOR_A, REMOTE_POOL_THREE);
        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueBatch(batch);
        _warpToExecutableAt(actionId);

        vm.recordLogs();
        _execute(actionId);

        // The config events land in sub-action array order: the rate limit write first,
        // the pool addition second
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertLt(
            _indexOfLog(
                logs,
                address(config),
                ICCIPBridgeConfig.RouteRateLimitsSet.selector,
                "RouteRateLimitsSet"
            ),
            _indexOfLog(
                logs,
                address(config),
                ICCIPBridgeConfig.RouteRemotePoolAdded.selector,
                "RouteRemotePoolAdded"
            ),
            "the sub-actions should dispatch in array order"
        );

        _assertCanonicalRateLimitsApplied();
        assertEq(
            ICCIPTokenPoolAdmin(config.pool()).getRemotePools(CHAIN_SELECTOR_A).length,
            3,
            "the pool addition should land"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be released after the batch"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            0,
            "the remote pools key should be released after the batch"
        );
    }

    // ========== DISPATCH FAILURES: POOL OWNERSHIP LOST ========== //

    // given the config lost the pool ownership
    //   [X] the route action reverts with OnlyCallableByOwner from inside the pool
    //   [X] every reserved key stays held
    // The hashes still match (ownership does not change route state), so the failure lands
    // at dispatch, not at the drift check
    function test_givenPoolOwnershipLost_reverts()
        public
        givenEnabled
        givenChainAdded
        givenPoolOwnershipLost
    {
        // Queueing succeeds without pool ownership: the mirror only reads state
        uint64 actionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);
        _warpToExecutableAt(actionId);

        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.OnlyCallableByOwner.selector));
        _execute(actionId);

        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            actionId,
            "the remote pools key should stay held after the dispatch failure"
        );
    }

    // given the config lost the pool ownership
    //   given the ready action is a rate limit change
    //     [X] it reverts with Unauthorized from inside the pool
    //     [X] the rate limits key stays held
    // The pool's rate limiter authority check raises a different error than the owner check
    function test_givenPoolOwnershipLost_givenRateLimitAction_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
        givenPoolOwnershipLost
    {
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.Unauthorized.selector, address(config))
        );
        _execute(queuedActionId);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            queuedActionId,
            "the rate limits key should stay held after the dispatch failure"
        );
    }

    // ========== RELEASE AND RE-QUEUE ========== //

    // given the action has executed
    //   when the freed domain is queued again
    //     [X] pendingActionId answered zero after the execution
    //     [X] the re-queue succeeds with a fresh action id
    //     [X] getQueuedAction still reports the executed metadata
    function test_givenActionExecuted_whenDomainIsRequeued()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
        givenActionReady
        givenActionExecuted
    {
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be free after the execution"
        );

        uint64 newActionId = _queueRateLimitAction(CHAIN_SELECTOR_A);
        assertEq(newActionId, queuedActionId + 1, "the re-queue should get a fresh id");
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            newActionId,
            "the freed domain should be reserved by the fresh action"
        );

        ITimelockBatchQueue.QueuedAction memory executedAction = timelock.getQueuedAction(
            queuedActionId
        );
        assertTrue(executedAction.executed, "the executed flag should be retained");
        assertEq(executedAction.proposer, bridgeAdmin, "the proposer should be retained");
        assertEq(executedAction.actions.length, 0, "the sub-actions should be cleared");
    }

    // ========== CROSS-ACTION INDEPENDENCE ========== //

    // given two live actions reserve independent domains of one route
    //   [X] executing the first leaves the second live with its key held
    //   [X] the second still executes afterwards
    // The execution-side counterpart of the queue-time coexistence: a dispatch inside one
    // domain never drifts the recorded hash of the other, so neither action can starve the
    // other once both are ready.
    function test_givenIndependentDomainActionsOnOneRoute() public givenEnabled givenChainAdded {
        uint64 rateLimitActionId = _queueRateLimitAction(CHAIN_SELECTOR_A);
        uint64 poolActionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);
        // Both were queued in the same block under the same delay, so one warp readies both
        _warpToExecutableAt(poolActionId);

        _execute(rateLimitActionId);

        _assertCanonicalRateLimitsApplied();
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the executed action should release its own key"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            poolActionId,
            "the untouched action should keep its key"
        );
        ITimelockBatchQueue.QueuedAction memory pending = timelock.getQueuedAction(poolActionId);
        assertFalse(pending.executed, "the untouched action should stay unexecuted");
        assertFalse(pending.cancelled, "the untouched action should stay uncancelled");

        _execute(poolActionId);

        assertTrue(
            ICCIPTokenPoolAdmin(config.pool()).isRemotePool(CHAIN_SELECTOR_A, REMOTE_POOL_THREE),
            "the second dispatch should accept the remote pool"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            0,
            "the second execution should release its key"
        );
    }

    // given another live action for a different route was cancelled
    //   [X] the cancellation releases only the cancelled action's key
    //   [X] the remaining action still executes
    // Cancellation is scoped to its own reservations: it never disturbs a neighbouring
    // action's readiness, recorded state or reservation.
    function test_givenAnotherActionCancelled()
        public
        givenEnabled
        givenChainAdded
        givenSecondChainAdded
    {
        uint64 cancelledActionId = _queueRateLimitAction(CHAIN_SELECTOR_A);
        uint64 survivingActionId = _queueRateLimitAction(CHAIN_SELECTOR_B);
        _warpToExecutableAt(survivingActionId);

        vm.prank(bridgeAdmin);
        timelock.cancelQueuedAction(cancelledActionId);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the cancellation should release its own key"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_B)),
            survivingActionId,
            "the neighbouring action should keep its key"
        );

        _execute(survivingActionId);

        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        _assertBucketConfig(
            rigPool.getCurrentOutboundRateLimiterState(CHAIN_SELECTOR_B),
            _canonicalOutboundConfig(),
            "outbound of the surviving route"
        );
        _assertBucketConfig(
            rigPool.getCurrentInboundRateLimiterState(CHAIN_SELECTOR_B),
            _canonicalInboundConfig(),
            "inbound of the surviving route"
        );
        // The cancelled action never reached the pool: route A keeps the fixture defaults
        _assertBucketConfig(
            rigPool.getCurrentOutboundRateLimiterState(CHAIN_SELECTOR_A),
            _defaultOutboundConfig(),
            "outbound of the cancelled route"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_B)),
            0,
            "the executed action should release its key"
        );
    }
}
