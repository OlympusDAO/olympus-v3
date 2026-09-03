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

contract CCIPTokenPoolConfigTimelockTests_queueRemoveRemotePool is CCIPTokenPoolConfigTimelockTest {
    // ========== SHARED QUEUE GATE LADDER ========== //

    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    // The setUp default state; the Q1/Q2 order is unobservable (both raise NotEnabled)
    function test_givenTimelockDisabled_reverts() public givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // given the config policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenConfigDisabled_reverts()
        public
        givenEnabled
        givenChainAdded
        givenConfigDisabled
    {
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
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
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertNotEnabled();
        vm.prank(thirdParty);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // when the caller does not hold the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Fuzzed; excludes the bridge admin account
    function test_whenCallerIsNotBridgeAdmin_reverts(
        address caller_
    ) public givenEnabled givenChainAdded {
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != address(0));
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(caller_);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // when the caller holds the admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsAdmin_reverts() public givenEnabled givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(admin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(emergency);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
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
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(thirdParty);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
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
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
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
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertNotConfigOperator(address(0));
        vm.prank(bridgeAdmin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // given the config operator has been rotated away
    //   when the pool value is unknown for the route
    //     [X] it reverts with CCIPTokenPoolConfigTimelock_NotConfigOperator
    // Pins the gate order: the operator gate answers before the validation mirror
    function test_givenOperatorRotated_whenPoolIsUnknown_reverts()
        public
        givenEnabled
        givenChainAdded
        givenOperatorRotated
    {
        bytes memory remotePool = REMOTE_POOL_THREE;

        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // ========== VALIDATION MIRROR LADDER ========== //

    // given the route does not exist
    //   [X] it reverts with NonExistentChain carrying the selector
    function test_givenRouteDoesNotExist_reverts() public givenEnabled {
        bytes memory remotePool = REMOTE_POOL_TWO;

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_A)
        );
        vm.prank(bridgeAdmin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // when the pool value is not accepted for the route
    //   [X] it reverts with InvalidRemotePoolForChain carrying the selector and the value
    function test_whenPoolIsUnknown_reverts() public givenEnabled givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_THREE;

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.InvalidRemotePoolForChain.selector,
                CHAIN_SELECTOR_A,
                remotePool
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);

        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            0,
            "the remote pools key should stay free after the rejected queue"
        );
    }

    // when the pool value is empty
    //   [X] it reverts with InvalidRemotePoolForChain
    // Empty bytes are not special-cased here: they fall through to the membership check,
    // unlike addRemotePool, which maps them to ZeroAddressNotAllowed. Pins the documented
    // sibling asymmetry on the queue path.
    function test_whenPoolIsEmpty_reverts() public givenEnabled givenChainAdded {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolAdmin.InvalidRemotePoolForChain.selector,
                CHAIN_SELECTOR_A,
                bytes("")
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, "");
    }

    // given the route has a single accepted remote pool
    //   [X] it reverts with CCIPTokenPoolConfig_LastRemotePool carrying the selector
    // The floor of one: a queued removal can never strand a route without pools
    function test_givenRouteHasSingleRemotePool_reverts()
        public
        givenEnabled
        givenChainAddedWithSinglePool
    {
        // The single accepted pool passes the membership check and trips the floor
        bytes memory remotePool = REMOTE_POOL_ONE;

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_LastRemotePool.selector,
                CHAIN_SELECTOR_A
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // ========== KEY CONFLICTS ========== //

    // given a pool addition is queued for the route
    //   [X] it reverts with ConfigKeyPending carrying the remote pools key and the holder id
    // The sibling one-key action reserves the same domain
    function test_givenPoolAdditionQueuedForRoute_reverts() public givenEnabled givenChainAdded {
        uint64 holderActionId = _queueAddRemotePoolAction(CHAIN_SELECTOR_A);
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertConfigKeyPending(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
    }

    // given a token change is queued for the route
    //   [X] it reverts with ConfigKeyPending carrying the remote pools key and the holder id
    // A three-key holder blocks through its remote pools key
    function test_givenTokenChangeQueuedForRoute_reverts() public givenEnabled givenChainAdded {
        uint64 holderActionId = _queueSetRemoteTokenAction(CHAIN_SELECTOR_A);
        bytes memory remotePool = REMOTE_POOL_TWO;

        _expectRevertConfigKeyPending(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);
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
    // The two-pool default is the passing side of the last-pool boundary
    function test_whenCallerIsBridgeAdmin() public givenEnabled givenChainAdded {
        bytes memory remotePool = REMOTE_POOL_TWO;
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
            abi.encode(
                _singleActionBatch(_removeRemotePoolBatchAction(CHAIN_SELECTOR_A, remotePool))
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
            ICCIPTokenPoolConfig.removeRemotePool.selector,
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
        uint64 actionId = timelock.queueRemoveRemotePool(CHAIN_SELECTOR_A, remotePool);

        assertEq(actionId, expectedActionId, "the returned action id should be the next id");
        assertEq(timelock.nextActionId(), expectedActionId + 1, "nextActionId should increment");
        _assertQueuedSingleAction(
            actionId,
            bridgeAdmin,
            ICCIPTokenPoolConfig.removeRemotePool.selector,
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
    //   [X] it queues successfully with disjoint keys and a sequential id
    // Coexistence of independent domains; both orders are proven in the addRemotePool pass
    function test_givenRateLimitActionPending()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        uint64 poolActionId = _queueRemoveRemotePoolAction(CHAIN_SELECTOR_A);

        assertEq(poolActionId, queuedActionId + 1, "the ids should be sequential");
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            queuedActionId,
            "the rate limits key should stay with the rate limit action"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(CHAIN_SELECTOR_A)),
            poolActionId,
            "the remote pools key should belong to the pool removal"
        );
    }

    // given a pool removal is queued for another route
    //   [X] it queues successfully and each action holds only its own route's key
    function test_givenSecondRoutePoolRemovalQueued()
        public
        givenEnabled
        givenChainAdded
        givenSecondChainAdded
    {
        // Route B carries a single remote pool by default, which the last-pool floor would
        // reject, so the admin adds a second one directly before the removal is queued
        _directAddRemotePool(CHAIN_SELECTOR_B, REMOTE_POOL_THREE);
        bytes memory remotePoolB = REMOTE_POOL_B;

        vm.prank(bridgeAdmin);
        uint64 secondRouteActionId = timelock.queueRemoveRemotePool(CHAIN_SELECTOR_B, remotePoolB);

        uint64 firstRouteActionId = _queueRemoveRemotePoolAction(CHAIN_SELECTOR_A);

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
}
