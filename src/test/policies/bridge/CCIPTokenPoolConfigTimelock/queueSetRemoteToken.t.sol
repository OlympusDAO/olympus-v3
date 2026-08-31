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

contract CCIPTokenPoolConfigTimelockTests_queueSetRemoteToken is CCIPTokenPoolConfigTimelockTest {
    // ========== SHARED QUEUE GATE LADDER ========== //

    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    // The setUp default state; the Q1/Q2 order is unobservable (both raise NotEnabled)
    function test_givenTimelockDisabled_reverts() public givenChainAdded {
        bytes memory remoteToken = REMOTE_TOKEN_B;

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // given the config policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenConfigDisabled_reverts()
        public
        givenEnabled
        givenChainAdded
        givenConfigDisabled
    {
        bytes memory remoteToken = REMOTE_TOKEN_B;

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
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
        bytes memory remoteToken = REMOTE_TOKEN_B;

        _expectRevertNotEnabled();
        vm.prank(thirdParty);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // when the caller does not hold the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Fuzzed; excludes the bridge admin account
    function test_whenCallerIsNotBridgeAdmin_reverts(
        address caller_
    ) public givenEnabled givenChainAdded {
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != address(0));
        bytes memory remoteToken = REMOTE_TOKEN_B;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(caller_);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // when the caller holds the admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // The admin replaces tokens directly on the config, never through the queue
    function test_whenCallerIsAdmin_reverts() public givenEnabled givenChainAdded {
        bytes memory remoteToken = REMOTE_TOKEN_B;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(admin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenChainAdded {
        bytes memory remoteToken = REMOTE_TOKEN_B;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(emergency);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled givenChainAdded {
        bytes memory remoteToken = REMOTE_TOKEN_B;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
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
        bytes memory remoteToken = REMOTE_TOKEN_B;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(thirdParty);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
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
        bytes memory remoteToken = REMOTE_TOKEN_B;

        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
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
        bytes memory remoteToken = REMOTE_TOKEN_B;

        _expectRevertNotConfigOperator(address(0));
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // given the config operator has been rotated away
    //   when the token is empty
    //     [X] it reverts with CCIPTokenPoolConfigTimelock_NotConfigOperator
    // Pins the gate order: the operator gate answers before the validation mirror
    function test_givenOperatorRotated_whenTokenIsEmpty_reverts()
        public
        givenEnabled
        givenChainAdded
        givenOperatorRotated
    {
        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, "");
    }

    // ========== VALIDATION MIRROR LADDER ========== //

    // given the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    function test_givenRouteDoesNotExist_reverts() public givenEnabled {
        bytes memory remoteToken = REMOTE_TOKEN_B;

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // when the token is empty
    //   [X] it reverts with CCIPTokenPoolConfig_RemoteTokenEmpty
    function test_whenTokenIsEmpty_reverts() public givenEnabled givenChainAdded {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RemoteTokenEmpty.selector
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, "");

        _assertRouteKeysFree(CHAIN_SELECTOR_A, "after the rejected queue");
    }

    // when the token equals the current remote token
    //   [X] it reverts with CCIPTokenPoolConfig_RemoteTokenUnchanged
    // The comparison is over exact bytes
    function test_whenTokenIsUnchanged_reverts() public givenEnabled givenChainAdded {
        bytes memory remoteToken = REMOTE_TOKEN;

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RemoteTokenUnchanged.selector
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // given the outbound bucket of the route is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    // The disabled shape {false, 0, 0} is producible only by direct pool seeding; the mirror
    // reads the live bucket state
    function test_givenOutboundBucketIsDisabled_reverts()
        public
        givenRouteWithDisabledOutboundBucket
        givenEnabled
    {
        bytes memory remoteToken = REMOTE_TOKEN_B;

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // given the inbound bucket of the route is disabled
    //   [X] it reverts with CCIPTokenPoolConfig_RateLimiterDisabled
    function test_givenInboundBucketIsDisabled_reverts()
        public
        givenRouteWithDisabledInboundBucket
        givenEnabled
    {
        bytes memory remoteToken = REMOTE_TOKEN_B;

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_RateLimiterDisabled.selector
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // ========== KEY CONFLICTS ========== //

    // given a token change for the same route is already queued
    //   [X] it reverts with ConfigKeyPending carrying the rate limits key and the holder id
    // A three-domain conflict names the first key in the _configKeys order
    function test_givenSameRouteTokenChangeAlreadyQueued_reverts()
        public
        givenEnabled
        givenChainAdded
    {
        uint64 holderActionId = _queueSetRemoteTokenAction(CHAIN_SELECTOR_A);
        bytes memory remoteToken = REMOTE_POOL_B;

        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // given a rate limit action is pending for the route
    //   [X] it reverts with ConfigKeyPending carrying the rate limits key and the holder id
    // An identity change reserves all three domains and therefore excludes every same-route
    // action
    function test_givenRateLimitActionPending_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        bytes memory remoteToken = REMOTE_TOKEN_B;

        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(CHAIN_SELECTOR_A), queuedActionId);
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // given a remote pool action is pending for the route
    //   [X] it reverts with ConfigKeyPending carrying the remote pools key and the holder id
    // The rate limits key is free, so the walk reaches and rejects on the second key
    function test_givenRemotePoolActionPending_reverts() public givenEnabled givenChainAdded {
        uint64 holderActionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);
        bytes memory remoteToken = REMOTE_TOKEN_B;
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the rate limits key should be free before the conflicting queue"
        );

        _expectRevertConfigKeyPending(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);
    }

    // ========== SUCCESS ========== //

    // when the caller is the bridge admin
    //   [X] it returns the action id and increments nextActionId
    //   [X] it reserves the rate limits, remote pools and route identity keys of the route
    //   [X] the stored route identity hash covers the OLD token, not the queued one
    //   [X] it stores the destination, the config state count of three, the timestamps and
    //       the canonical payload
    //   [X] it emits three ConfigStateQueued events, one TimelockSubActionQueued and one
    //       TimelockActionQueued
    function test_whenCallerIsBridgeAdmin() public givenEnabled givenChainAdded {
        bytes memory remoteToken = REMOTE_TOKEN_B;
        bytes memory payload = abi.encode(CHAIN_SELECTOR_A, remoteToken);

        // The scoped keys in _configKeys order: rate limits, remote pools, route identity
        bytes32[] memory keys = new bytes32[](3);
        keys[0] = timelock.getRateLimitsKey(CHAIN_SELECTOR_A);
        keys[1] = timelock.getRemotePoolsKey(CHAIN_SELECTOR_A);
        keys[2] = timelock.getRouteIdentityKey(CHAIN_SELECTOR_A);

        bytes32[] memory expectedHashes = new bytes32[](3);
        expectedHashes[0] = _expectedRateLimitsHash(CHAIN_SELECTOR_A);
        expectedHashes[1] = _expectedRemotePoolsHash(CHAIN_SELECTOR_A);
        expectedHashes[2] = _expectedRouteIdentityHash(CHAIN_SELECTOR_A);

        // The identity hash records the state at queue time, so it carries the OLD token
        assertEq(
            expectedHashes[2],
            keccak256(
                abi.encode(timelock.ROUTE_IDENTITY_DOMAIN(), CHAIN_SELECTOR_A, true, REMOTE_TOKEN)
            ),
            "the recorded identity hash should cover the old remote token"
        );
        assertTrue(
            expectedHashes[2] !=
                keccak256(
                    abi.encode(
                        timelock.ROUTE_IDENTITY_DOMAIN(),
                        CHAIN_SELECTOR_A,
                        true,
                        REMOTE_TOKEN_B
                    )
                ),
            "the recorded identity hash should differ from the hash over the queued token"
        );

        uint64 expectedActionId = timelock.nextActionId();
        // executableAt = now + 1 days (the delay); expiresAt = executableAt + 3 days (the
        // execution window)
        uint48 expectedExecutableAt = uint48(vm.getBlockTimestamp()) + TIMELOCK_DELAY;
        uint48 expectedExpiresAt = expectedExecutableAt + 3 days;
        bytes32 batchHash = keccak256(
            abi.encode(
                _singleActionBatch(_setRemoteTokenBatchAction(CHAIN_SELECTOR_A, remoteToken))
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
            ICCIPTokenPoolConfig.setRemoteToken.selector,
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
        uint64 actionId = timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);

        assertEq(actionId, expectedActionId, "the returned action id should be the next id");
        assertEq(timelock.nextActionId(), expectedActionId + 1, "nextActionId should increment");
        _assertQueuedSingleAction(
            actionId,
            bridgeAdmin,
            ICCIPTokenPoolConfig.setRemoteToken.selector,
            payload,
            keys,
            expectedHashes
        );
    }

    // when the token is non-EVM-shaped
    //   [X] it queues successfully
    // The mirror checks only non-empty and changed; a 64-byte value queues
    function test_whenTokenIsNonEvmShaped() public givenEnabled givenChainAdded {
        // Two words instead of the single word of an EVM-shaped address
        bytes memory remoteToken = abi.encode(
            keccak256("nonEvmRemoteTokenHigh"),
            keccak256("nonEvmRemoteTokenLow")
        );
        assertEq(remoteToken.length, 64, "the fixture token should be 64 bytes");

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueSetRemoteToken(CHAIN_SELECTOR_A, remoteToken);

        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, actionId, "non-EVM-shaped token queue");
        (, , bytes memory storedPayload) = timelock.getQueuedSubAction(actionId, 0);
        assertEq(
            storedPayload,
            abi.encode(CHAIN_SELECTOR_A, remoteToken),
            "the stored payload should carry the free-form token"
        );
    }

    // given the route is contained
    //   [X] it queues successfully
    // The containment shape {true, 2, 1} is an enabled configuration, so the bucket check
    // passes; re-pins the sibling suite's product decision on the queue path
    function test_givenRouteIsContained() public givenEnabled givenChainAdded givenRouteContained {
        uint64 actionId = _queueSetRemoteTokenAction(CHAIN_SELECTOR_A);

        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, actionId, "contained-route token change");
    }
}
