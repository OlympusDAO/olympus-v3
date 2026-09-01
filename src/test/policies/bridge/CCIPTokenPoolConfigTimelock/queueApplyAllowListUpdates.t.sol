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

contract CCIPTokenPoolConfigTimelockTests_queueApplyAllowListUpdates is
    CCIPTokenPoolConfigTimelockTest
{
    // ========== FILE-LOCAL HELPERS ========== //

    /// @notice Returns whether an address is a member of the current rig pool's allowlist.
    function _isAllowListed(address entry_) internal view returns (bool) {
        address[] memory allowList = ICCIPTokenPoolAdmin(config.pool()).getAllowList();
        for (uint256 i; i < allowList.length; ++i) {
            if (allowList[i] == entry_) return true;
        }
        return false;
    }

    // ========== SHARED QUEUE GATE LADDER (PRIMARY RIG) ========== //

    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    // The setUp default state; the Q1/Q2 order is unobservable (both raise NotEnabled)
    function test_givenTimelockDisabled_reverts() public {
        address[] memory adds = _singleAddress(allowListedThree);

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueApplyAllowListUpdates(new address[](0), adds);
    }

    // given the config policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenConfigDisabled_reverts() public givenEnabled givenConfigDisabled {
        address[] memory adds = _singleAddress(allowListedThree);

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueApplyAllowListUpdates(new address[](0), adds);
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
        address[] memory adds = _singleAddress(allowListedThree);

        _expectRevertNotEnabled();
        vm.prank(thirdParty);
        timelock.queueApplyAllowListUpdates(new address[](0), adds);
    }

    // when the caller does not hold the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Fuzzed; excludes the bridge admin account
    function test_whenCallerIsNotBridgeAdmin_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != address(0));
        address[] memory adds = _singleAddress(allowListedThree);

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(caller_);
        timelock.queueApplyAllowListUpdates(new address[](0), adds);
    }

    // when the caller holds the admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsAdmin_reverts() public givenEnabled {
        address[] memory adds = _singleAddress(allowListedThree);

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(admin);
        timelock.queueApplyAllowListUpdates(new address[](0), adds);
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled {
        address[] memory adds = _singleAddress(allowListedThree);

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(emergency);
        timelock.queueApplyAllowListUpdates(new address[](0), adds);
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled {
        address[] memory adds = _singleAddress(allowListedThree);

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        timelock.queueApplyAllowListUpdates(new address[](0), adds);
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
        address[] memory adds = _singleAddress(allowListedThree);

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(thirdParty);
        timelock.queueApplyAllowListUpdates(new address[](0), adds);
    }

    // given the config operator has been rotated to another account
    //   [X] it reverts with CCIPTokenPoolConfigTimelock_NotConfigOperator carrying the new
    //       operator
    function test_givenOperatorRotated_reverts() public givenEnabled givenOperatorRotated {
        address[] memory adds = _singleAddress(allowListedThree);

        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueApplyAllowListUpdates(new address[](0), adds);
    }

    // given the config operator has been revoked
    //   [X] it reverts with CCIPTokenPoolConfigTimelock_NotConfigOperator carrying the zero
    //       address
    function test_givenOperatorRevoked_reverts() public givenEnabled givenOperatorRevoked {
        address[] memory adds = _singleAddress(allowListedThree);

        _expectRevertNotConfigOperator(address(0));
        vm.prank(bridgeAdmin);
        timelock.queueApplyAllowListUpdates(new address[](0), adds);
    }

    // given the config operator has been rotated away
    //   when the updates are empty
    //     [X] it reverts with CCIPTokenPoolConfigTimelock_NotConfigOperator
    // Pins the gate order: the operator gate answers before the validation mirror
    function test_givenOperatorRotated_whenUpdatesAreEmpty_reverts()
        public
        givenEnabled
        givenOperatorRotated
    {
        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueApplyAllowListUpdates(new address[](0), new address[](0));
    }

    // ========== VALIDATION MIRROR ========== //

    // given the pool was deployed without an allowlist
    //   [X] it reverts with AllowListNotEnabled
    // The primary-rig case: a valid payload from the bridge admin with every gate passed
    // still cannot reach the domain, for any caller and any payload
    function test_givenAllowListNotEnabled_reverts() public givenEnabled {
        assertFalse(
            ICCIPTokenPoolAdmin(config.pool()).getAllowListEnabled(),
            "the primary rig pool should carry no allowlist"
        );
        address[] memory adds = _singleAddress(allowListedThree);

        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.AllowListNotEnabled.selector));
        vm.prank(bridgeAdmin);
        timelock.queueApplyAllowListUpdates(new address[](0), adds);

        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            0,
            "the allowlist key should stay free on the primary rig"
        );
    }

    // when both the removes and the adds are empty
    //   [X] it reverts with CCIPTokenPoolConfig_AllowListUpdatesEmpty
    // Runs on the allowlist rig, where the pool-side flag check passes
    function test_whenUpdatesAreEmpty_reverts() public givenAllowListPoolRig givenEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_AllowListUpdatesEmpty.selector
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueApplyAllowListUpdates(new address[](0), new address[](0));

        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            0,
            "the allowlist key should stay free after the rejected queue"
        );
    }

    // ========== KEY CONFLICT ========== //

    // given an allowlist action is already queued
    //   [X] it reverts with ConfigKeyPending carrying the allowlist key and the holder id
    // The pool-wide domain conflicts with itself: one unresolved allowlist change at a time
    function test_givenAllowListActionAlreadyQueued_reverts()
        public
        givenAllowListPoolRig
        givenEnabled
    {
        uint64 holderActionId = _queueApplyAllowListUpdatesAction();
        // A different payload: the domain conflicts regardless of the values
        address[] memory removes = _singleAddress(allowListedOne);

        _expectRevertConfigKeyPending(timelock.getAllowListKey(), holderActionId);
        vm.prank(bridgeAdmin);
        timelock.queueApplyAllowListUpdates(removes, new address[](0));
    }

    // ========== SUCCESS (ALLOWLIST RIG) ========== //

    // when the caller is the bridge admin
    //   [X] it returns the action id and increments nextActionId
    //   [X] it reserves the pool-wide allowlist key and no route key
    //   [X] the stored hash equals the recomputed two-entry preimage
    //       (ALLOWLIST_DOMAIN, true, 2, xor of the hashed members)
    //   [X] it stores the destination, a config state count of ONE, the timestamps and the
    //       canonical payload
    //   [X] it emits one ConfigStateQueued, one TimelockSubActionQueued and one
    //       TimelockActionQueued
    function test_whenCallerIsBridgeAdmin() public givenAllowListPoolRig givenEnabled {
        address[] memory removes = new address[](0);
        address[] memory adds = _singleAddress(allowListedThree);
        bytes memory payload = abi.encode(removes, adds);

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = timelock.getAllowListKey();

        bytes32[] memory expectedHashes = new bytes32[](1);
        expectedHashes[0] = _expectedAllowListHash();
        // The rig's pool carries the two constructor entries, so the preimage is
        // (domain, true, 2, keccak(abi.encode(one)) xor keccak(abi.encode(two)))
        assertEq(
            expectedHashes[0],
            keccak256(
                abi.encode(
                    timelock.ALLOWLIST_DOMAIN(),
                    true,
                    uint256(2),
                    keccak256(abi.encode(allowListedOne)) ^ keccak256(abi.encode(allowListedTwo))
                )
            ),
            "the recorded hash should be the two-entry allowlist preimage"
        );

        uint64 expectedActionId = timelock.nextActionId();
        // executableAt = now + 1 days (the delay); expiresAt = executableAt + 3 days (the
        // execution window)
        uint48 expectedExecutableAt = uint48(vm.getBlockTimestamp()) + TIMELOCK_DELAY;
        uint48 expectedExpiresAt = expectedExecutableAt + 3 days;
        bytes32 batchHash = keccak256(
            abi.encode(_singleActionBatch(_applyAllowListUpdatesBatchAction(removes, adds)))
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
            ICCIPTokenPoolConfig.applyAllowListUpdates.selector,
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
        uint64 actionId = timelock.queueApplyAllowListUpdates(removes, adds);

        assertEq(actionId, expectedActionId, "the returned action id should be the next id");
        assertEq(timelock.nextActionId(), expectedActionId + 1, "nextActionId should increment");
        _assertQueuedSingleAction(
            actionId,
            bridgeAdmin,
            ICCIPTokenPoolConfig.applyAllowListUpdates.selector,
            payload,
            keys,
            expectedHashes
        );

        // The domain is pool-wide: no route key is touched
        _assertRouteKeysFree(CHAIN_SELECTOR_A, "after the allowlist queue");
    }

    // when the update carries adds only
    //   [X] it queues successfully
    // One side of the emptiness OR: a single-element adds array with empty removes
    function test_whenUpdateIsAddsOnly() public givenAllowListPoolRig givenEnabled {
        address[] memory adds = _singleAddress(allowListedThree);

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueApplyAllowListUpdates(new address[](0), adds);

        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            actionId,
            "the allowlist key should belong to the adds-only action"
        );
    }

    // when the update carries removes only
    //   [X] it queues successfully
    // The other side of the emptiness OR
    function test_whenUpdateIsRemovesOnly() public givenAllowListPoolRig givenEnabled {
        address[] memory removes = _singleAddress(allowListedOne);

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueApplyAllowListUpdates(removes, new address[](0));

        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            actionId,
            "the allowlist key should belong to the removes-only action"
        );
    }

    // when the removes contain entries that are not allowlisted
    //   [X] it queues successfully
    // The mirror checks no membership; the pool skips absent removes silently at dispatch
    function test_whenRemovesContainAbsentEntries() public givenAllowListPoolRig givenEnabled {
        address[] memory removes = _singleAddress(thirdParty);
        address[] memory adds = _singleAddress(allowListedThree);
        assertFalse(
            _isAllowListed(thirdParty),
            "the removed entry should not be allowlisted before the queue"
        );

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueApplyAllowListUpdates(removes, adds);

        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            actionId,
            "the allowlist key should belong to the action"
        );
        (, , bytes memory storedPayload) = timelock.getQueuedSubAction(actionId, 0);
        assertEq(
            storedPayload,
            abi.encode(removes, adds),
            "the stored payload should carry the absent remove verbatim"
        );
    }

    // given a route action is pending
    //   [X] the allowlist action queues successfully with disjoint keys
    // A pending addChain holds all three route domains at once, so one pending action proves
    // independence from every route domain
    function test_givenRouteActionPending() public givenAllowListPoolRig givenEnabled {
        uint64 routeActionId = _queueAddChainAction(CHAIN_SELECTOR_A);

        uint64 allowListActionId = _queueApplyAllowListUpdatesAction();

        assertEq(allowListActionId, routeActionId + 1, "the ids should be sequential");
        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, routeActionId, "pending route action");
        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            allowListActionId,
            "the allowlist key should belong to the allowlist action"
        );
    }

    // given the allowlist action was queued first
    //   [X] a three-domain route action queues successfully afterwards
    // The reverse order of the independence pair
    function test_givenAllowListActionQueuedFirst() public givenAllowListPoolRig givenEnabled {
        uint64 allowListActionId = _queueApplyAllowListUpdatesAction();

        uint64 routeActionId = _queueAddChainAction(CHAIN_SELECTOR_A);

        assertEq(routeActionId, allowListActionId + 1, "the ids should be sequential");
        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            allowListActionId,
            "the allowlist key should stay with the allowlist action"
        );
        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, routeActionId, "route action queued second");
    }
}
