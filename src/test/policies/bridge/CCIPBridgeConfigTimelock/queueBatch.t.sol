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

contract CCIPBridgeConfigTimelockTests_queueBatch is CCIPBridgeConfigTimelockTest {
    // ========== FILE-LOCAL HELPERS ========== //

    /// @notice The valid single-action probe of the gate ladder: the canonical rate limit
    ///         sub-action on route A.
    function _probeBatch() internal view returns (ITimelockBatchQueue.BatchAction[] memory) {
        return
            _singleActionBatch(
                _setChainRateLimitsBatchAction(
                    CHAIN_SELECTOR_A,
                    _canonicalOutboundConfig(),
                    _canonicalInboundConfig()
                )
            );
    }

    function _expectRevertActionInvalid(address target_, bytes4 selector_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                target_,
                selector_
            )
        );
    }

    /// @notice Asserts one stored sub-action triple of a queued batch.
    function _assertStoredBatchSubAction(
        uint64 actionId_,
        uint256 index_,
        bytes4 selector_,
        bytes memory payload_
    ) internal view {
        (address target, bytes4 storedSelector, bytes memory storedPayload) = timelock
            .getQueuedSubAction(actionId_, index_);
        assertEq(target, address(config), "stored sub-action target");
        assertEq(storedSelector, selector_, "stored sub-action selector");
        assertEq(storedPayload, payload_, "stored sub-action payload");
    }

    // ========== SHARED QUEUE GATE LADDER ========== //

    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    // The setUp default state; a valid single-action batch as the probe
    function test_givenTimelockDisabled_reverts() public givenChainAdded {
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // given the config policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenConfigDisabled_reverts()
        public
        givenEnabled
        givenChainAdded
        givenConfigDisabled
    {
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();

        _expectRevertNotEnabled();
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
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
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();

        _expectRevertNotEnabled();
        vm.prank(thirdParty);
        timelock.queueBatch(batch);
    }

    // when the caller does not hold the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Fuzzed; excludes the bridge admin account
    function test_whenCallerIsNotBridgeAdmin_reverts(
        address caller_
    ) public givenEnabled givenChainAdded {
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != address(0));
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(caller_);
        timelock.queueBatch(batch);
    }

    // when the caller holds the admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsAdmin_reverts() public givenEnabled givenChainAdded {
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(admin);
        timelock.queueBatch(batch);
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenChainAdded {
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(emergency);
        timelock.queueBatch(batch);
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled givenChainAdded {
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        timelock.queueBatch(batch);
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
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(thirdParty);
        timelock.queueBatch(batch);
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
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();

        _expectRevertNotConfigOperator(thirdParty);
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
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
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();

        _expectRevertNotConfigOperator(address(0));
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // ========== BATCH SHAPE ========== //

    // when the batch is empty
    //   [X] it reverts with ITimelockBatchQueue_BatchEmpty
    // The emptiness check answers before the gate ladder (it sits in the base wrapper)
    function test_whenBatchIsEmpty_reverts() public givenEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector)
        );
        vm.prank(bridgeAdmin);
        timelock.queueBatch(new ITimelockBatchQueue.BatchAction[](0));
    }

    // when the batch holds sixteen sub-actions
    //   [X] it reverts with ITimelockBatchQueue_BatchTooLarge carrying 16 and 15
    // The size comparison is strict, so 16 is the failing side of the boundary
    function test_whenBatchExceedsMaxSize_reverts() public givenEnabled {
        // The size check runs before any per-sub-action validation, so identical contents
        // are acceptable for the probe
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](16);
        for (uint256 i; i < batch.length; ++i) {
            batch[i] = _setChainRateLimitsBatchAction(
                CHAIN_SELECTOR_A,
                _canonicalOutboundConfig(),
                _canonicalInboundConfig()
            );
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_BatchTooLarge.selector,
                16,
                15
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // ========== SUB-ACTION VALIDITY ========== //

    // when a sub-action targets a contract other than the config
    //   [X] it reverts with ITimelockBatchQueue_ActionInvalid carrying the foreign target
    //       and the selector
    function test_whenTargetIsNotConfig_reverts() public givenEnabled givenChainAdded {
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();
        batch[0].target = thirdParty;

        _expectRevertActionInvalid(thirdParty, ICCIPBridgeConfig.setChainRateLimits.selector);
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // when a sub-action carries a selector outside the seven supported ones
    //   [X] it reverts with ITimelockBatchQueue_ActionInvalid carrying the config and the
    //       selector
    // A real config selector outside the set (for example disableChain) is the probe
    function test_whenSelectorIsUnsupported_reverts() public givenEnabled givenChainAdded {
        ITimelockBatchQueue.BatchAction[] memory batch = _singleActionBatch(
            _batchAction(ICCIPBridgeConfig.disableChain.selector, abi.encode(CHAIN_SELECTOR_A))
        );

        _expectRevertActionInvalid(address(config), ICCIPBridgeConfig.disableChain.selector);
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // when a sub-action payload cannot be decoded with its selector's types
    //   [X] it reverts with the raw decoding revert, propagated as is
    // A truncated payload; the expectation is a bare revert with no error selector
    function test_whenPayloadIsUndecodable_reverts() public givenEnabled givenChainAdded {
        // One byte cannot decode as a uint64 word
        ITimelockBatchQueue.BatchAction[] memory batch = _singleActionBatch(
            _batchAction(ICCIPBridgeConfig.removeChain.selector, hex"12")
        );

        // The abi decoder reverts with no stable revert data, so the bare expectation is the
        // strongest possible match for this failure path
        vm.expectRevert();
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // when a sub-action payload carries trailing bytes
    //   [X] it reverts with ITimelockBatchQueue_ActionInvalid
    // The payload decodes, but the canonical re-encoding is shorter than the stored bytes
    function test_whenPayloadHasTrailingBytes_reverts() public givenEnabled givenChainAdded {
        // The canonical removeChain payload is one 32-byte word; the appended byte survives
        // decoding but not the re-encoding comparison
        bytes memory payload = bytes.concat(abi.encode(CHAIN_SELECTOR_A), hex"00");
        ITimelockBatchQueue.BatchAction[] memory batch = _singleActionBatch(
            _batchAction(ICCIPBridgeConfig.removeChain.selector, payload)
        );

        _expectRevertActionInvalid(address(config), ICCIPBridgeConfig.removeChain.selector);
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // when a sub-action payload uses non-standard dynamic offsets
    //   [X] it reverts with ITimelockBatchQueue_ActionInvalid
    // A bytes head pointing past padding decodes, but the re-encoding normalizes the offset
    function test_whenPayloadUsesNonStandardOffsets_reverts() public givenEnabled givenChainAdded {
        // The canonical abi.encode(uint64, bytes) puts the bytes head at offset 0x40; this
        // encoding points it at 0x60 with one inserted padding word, so the same values
        // decode from a longer, non-canonical byte string
        bytes memory payload = abi.encodePacked(
            uint256(CHAIN_SELECTOR_A),
            uint256(0x60),
            uint256(0),
            uint256(REMOTE_TOKEN_B.length),
            REMOTE_TOKEN_B
        );
        ITimelockBatchQueue.BatchAction[] memory batch = _singleActionBatch(
            _batchAction(ICCIPBridgeConfig.setRemoteToken.selector, payload)
        );

        _expectRevertActionInvalid(address(config), ICCIPBridgeConfig.setRemoteToken.selector);
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // given a later sub-action fails its validation mirror
    //   [X] it reverts with the mirror's error
    //   [X] no key of the earlier sub-action is held afterwards
    // The product-level rollback pin: a valid rate limit sub-action followed by a
    // removeChain of a nonexistent route leaves the rate limits key free
    function test_givenLaterSubActionFailsMirror_reverts() public givenEnabled givenChainAdded {
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](2);
        batch[0] = _setChainRateLimitsBatchAction(
            CHAIN_SELECTOR_A,
            _canonicalOutboundConfig(),
            _canonicalInboundConfig()
        );
        batch[1] = _removeChainBatchAction(CHAIN_SELECTOR_B);

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, CHAIN_SELECTOR_B)
        );
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);

        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(CHAIN_SELECTOR_A)),
            0,
            "the earlier sub-action's key should be free after the rollback"
        );
    }

    // ========== KEY BUDGET ========== //

    // when the batch holds nine addChain sub-actions
    //   [X] it reverts with ConfigKeysTooMany carrying 27 and 24
    // The cumulative counter crosses the budget at the ninth three-key sub-action
    function test_whenBatchExceedsKeyBudgetWithRouteActions_reverts() public givenEnabled {
        // 9 sub-actions x 3 keys = 27 > 24; the fresh selectors keep every mirror passing
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](9);
        for (uint256 i; i < batch.length; ++i) {
            // casting to 'uint64' is safe because the selector base plus the loop counter
            // stays far below the uint64 maximum
            // forge-lint: disable-next-line(unsafe-typecast)
            batch[i] = _addChainBatchAction(_defaultChainUpdate(uint64(20_000 + i)));
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeysTooMany.selector,
                27,
                24
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // when a mixed batch crosses the budget
    //   [X] it reverts with ConfigKeysTooMany carrying 25 and 24
    // Seven addChain sub-actions (21 keys) plus four one-key sub-actions: the counter sums
    // every earlier width
    function test_whenMixedBatchExceedsKeyBudget_reverts() public givenEnabled {
        // The one-key sub-actions need existing routes; _addRoutes claims 10_000+, the
        // addChain sub-actions use 20_000+ to stay disjoint
        uint64[] memory routeSelectors = _addRoutes(4);
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](11);
        for (uint256 i; i < 7; ++i) {
            // casting to 'uint64' is safe because the selector base plus the loop counter
            // stays far below the uint64 maximum
            // forge-lint: disable-next-line(unsafe-typecast)
            batch[i] = _addChainBatchAction(_defaultChainUpdate(uint64(20_000 + i)));
        }
        for (uint256 i; i < 4; ++i) {
            batch[7 + i] = _setChainRateLimitsBatchAction(
                routeSelectors[i],
                _canonicalOutboundConfig(),
                _canonicalInboundConfig()
            );
        }

        // 7 x 3 = 21 keys, then 22, 23, 24 pass and the fourth one-key sub-action crosses
        // at 25 > 24
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeysTooMany.selector,
                25,
                24
            )
        );
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // ========== INTRA-BATCH AND CROSS-BATCH CONFLICTS ========== //

    // when two sub-actions of the batch reserve the same domain
    //   [X] it reverts with ConfigKeyPending whose owner is the CURRENT action id
    // A rate limit sub-action followed by a removeChain of the same route: the key was
    // reserved by the earlier sub-action of this very batch
    function test_whenBatchHoldsSameDomainTwice_reverts() public givenEnabled givenChainAdded {
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](2);
        batch[0] = _setChainRateLimitsBatchAction(
            CHAIN_SELECTOR_A,
            _canonicalOutboundConfig(),
            _canonicalInboundConfig()
        );
        batch[1] = _removeChainBatchAction(CHAIN_SELECTOR_A);
        uint64 currentActionId = timelock.nextActionId();

        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(CHAIN_SELECTOR_A), currentActionId);
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // when the batch holds the same addChain twice
    //   [X] it reverts with ConfigKeyPending whose owner is the CURRENT action id
    // The identical-sub-action shape of the intra-batch conflict
    function test_whenBatchHoldsSameRouteTwice_reverts() public givenEnabled {
        uint64 freshSelector = 3333;
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](2);
        batch[0] = _addChainBatchAction(_defaultChainUpdate(freshSelector));
        batch[1] = _addChainBatchAction(_defaultChainUpdate(freshSelector));
        uint64 currentActionId = timelock.nextActionId();

        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(freshSelector), currentActionId);
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // given a domain is reserved by an earlier typed-wrapper action
    //   [X] it reverts with ConfigKeyPending naming the earlier action as the owner
    // The cross-batch conflict: the batch entry point and the typed wrappers share one
    // reservation namespace
    function test_givenDomainReservedByEarlierAction_reverts()
        public
        givenEnabled
        givenChainAdded
        givenActionQueued
    {
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();

        _expectRevertConfigKeyPending(timelock.getRateLimitsKey(CHAIN_SELECTOR_A), queuedActionId);
        vm.prank(bridgeAdmin);
        timelock.queueBatch(batch);
    }

    // ========== SUCCESS ========== //

    // when the caller is the bridge admin
    //   [X] it queues a two-sub-action batch over independent domains of one route
    //   [X] it reserves the rate limits and remote pools keys under one action id
    //   [X] each ConfigStateQueued event carries its sub-action index
    //   [X] the stored sub-actions are readable in array order via getQueuedSubAction
    //   [X] it emits one TimelockSubActionQueued per sub-action and one TimelockActionQueued
    function test_whenCallerIsBridgeAdmin() public givenEnabled givenChainAdded {
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](2);
        batch[0] = _setChainRateLimitsBatchAction(
            CHAIN_SELECTOR_A,
            _canonicalOutboundConfig(),
            _canonicalInboundConfig()
        );
        batch[1] = _addRemotePoolBatchAction(CHAIN_SELECTOR_A, REMOTE_POOL_THREE);

        bytes32 rateLimitsKey = timelock.getRateLimitsKey(CHAIN_SELECTOR_A);
        bytes32 remotePoolsKey = timelock.getRemotePoolsKey(CHAIN_SELECTOR_A);
        bytes32 rateLimitsHash = _expectedRateLimitsHash(CHAIN_SELECTOR_A);
        bytes32 remotePoolsHash = _expectedRemotePoolsHash(CHAIN_SELECTOR_A);
        uint64 expectedActionId = timelock.nextActionId();
        // executableAt = now + 1 days; expiresAt = executableAt + 3 days
        uint48 expectedExecutableAt = uint48(vm.getBlockTimestamp()) + TIMELOCK_DELAY;
        uint48 expectedExpiresAt = expectedExecutableAt + 3 days;

        vm.expectEmit(true, true, true, true, address(timelock));
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            expectedActionId,
            0,
            rateLimitsKey,
            0,
            address(config),
            rateLimitsHash
        );
        vm.expectEmit(true, true, true, true, address(timelock));
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            expectedActionId,
            1,
            remotePoolsKey,
            0,
            address(config),
            remotePoolsHash
        );
        vm.expectEmit(true, true, true, true, address(timelock));
        emit ITimelockBatchQueue.TimelockSubActionQueued(
            expectedActionId,
            address(config),
            ICCIPBridgeConfig.setChainRateLimits.selector,
            0,
            keccak256(batch[0].payload)
        );
        vm.expectEmit(true, true, true, true, address(timelock));
        emit ITimelockBatchQueue.TimelockSubActionQueued(
            expectedActionId,
            address(config),
            ICCIPBridgeConfig.addRemotePool.selector,
            1,
            keccak256(batch[1].payload)
        );
        vm.expectEmit(true, true, true, true, address(timelock));
        emit ITimelockBatchQueue.TimelockActionQueued(
            expectedActionId,
            bridgeAdmin,
            keccak256(abi.encode(batch)),
            expectedExecutableAt,
            expectedExpiresAt
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueBatch(batch);

        assertEq(actionId, expectedActionId, "the returned action id should be the expected id");
        assertEq(
            timelock.pendingActionId(rateLimitsKey),
            actionId,
            "the rate limits key should be reserved by the batch"
        );
        assertEq(
            timelock.pendingActionId(remotePoolsKey),
            actionId,
            "the remote pools key should be reserved by the batch"
        );
        assertEq(timelock.getQueuedActionLength(actionId), 2, "two sub-actions should be stored");
        _assertStoredBatchSubAction(
            actionId,
            0,
            ICCIPBridgeConfig.setChainRateLimits.selector,
            batch[0].payload
        );
        _assertStoredBatchSubAction(
            actionId,
            1,
            ICCIPBridgeConfig.addRemotePool.selector,
            batch[1].payload
        );
        assertEq(
            timelock.getQueuedConfigStateCount(actionId, 0),
            1,
            "sub-action zero should hold one key"
        );
        assertEq(
            timelock.getQueuedConfigStateCount(actionId, 1),
            1,
            "sub-action one should hold one key"
        );
    }

    // when the batch holds a single sub-action
    //   [X] it queues with the same keys and events as the typed wrapper would
    // The wrapper-parity pin: queueBatch of one action equals the dedicated entry point
    function test_whenBatchIsSingleAction() public givenEnabled givenChainAdded {
        // The probe's payload is built by the same factory the typed wrapper encoding rules
        // define, so the stored shape below is exactly what queueSetChainRateLimits stores
        ITimelockBatchQueue.BatchAction[] memory batch = _probeBatch();
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = timelock.getRateLimitsKey(CHAIN_SELECTOR_A);
        bytes32[] memory expectedHashes = new bytes32[](1);
        expectedHashes[0] = _expectedRateLimitsHash(CHAIN_SELECTOR_A);

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueBatch(batch);

        _assertQueuedSingleAction(
            actionId,
            bridgeAdmin,
            ICCIPBridgeConfig.setChainRateLimits.selector,
            abi.encode(CHAIN_SELECTOR_A, _canonicalOutboundConfig(), _canonicalInboundConfig()),
            keys,
            expectedHashes
        );
    }

    // when the batch holds fifteen sub-actions
    //   [X] it queues successfully
    // The passing side of the size boundary: fifteen one-key rate limit sub-actions over
    // fifteen routes (15 keys, within the budget)
    function test_whenBatchIsAtMaxSize() public givenEnabled {
        uint64[] memory routeSelectors = _addRoutes(15);
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](15);
        for (uint256 i; i < batch.length; ++i) {
            batch[i] = _setChainRateLimitsBatchAction(
                routeSelectors[i],
                _canonicalOutboundConfig(),
                _canonicalInboundConfig()
            );
        }

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueBatch(batch);

        assertEq(
            timelock.getQueuedActionLength(actionId),
            15,
            "fifteen sub-actions should be stored"
        );
        for (uint256 i; i < routeSelectors.length; ++i) {
            assertEq(
                timelock.pendingActionId(timelock.getRateLimitsKey(routeSelectors[i])),
                actionId,
                "each route's rate limits key should be reserved by the batch"
            );
        }
    }

    // when the batch reserves exactly twenty-four keys
    //   [X] it queues successfully
    // The passing side of the budget boundary: eight addChain sub-actions on fresh selectors
    function test_whenBatchReservesExactKeyBudget() public givenEnabled {
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](8);
        for (uint256 i; i < batch.length; ++i) {
            // casting to 'uint64' is safe because the selector base plus the loop counter
            // stays far below the uint64 maximum
            // forge-lint: disable-next-line(unsafe-typecast)
            batch[i] = _addChainBatchAction(_defaultChainUpdate(uint64(20_000 + i)));
        }

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueBatch(batch);

        // 8 sub-actions x 3 keys = exactly the 24-key budget
        uint256 totalKeys;
        for (uint256 i; i < 8; ++i) {
            totalKeys += timelock.getQueuedConfigStateCount(actionId, i);
        }
        assertEq(totalKeys, 24, "the batch should hold exactly twenty-four keys");
        _assertRouteKeysHeldBy(20_000, actionId, "first selector of the budget batch");
        _assertRouteKeysHeldBy(20_007, actionId, "last selector of the budget batch");
    }

    // when the batch spans route domains and the allowlist domain
    //   [X] it queues successfully with four keys under one action id
    // Runs on the allowlist rig: one addChain sub-action plus one allowlist sub-action
    function test_whenBatchSpansRoutesAndAllowList() public givenAllowListPoolRig givenEnabled {
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](2);
        batch[0] = _addChainBatchAction(_defaultChainUpdate(CHAIN_SELECTOR_A));
        batch[1] = _applyAllowListUpdatesBatchAction(
            new address[](0),
            _singleAddress(allowListedThree)
        );

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueBatch(batch);

        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, actionId, "route half of the spanning batch");
        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            actionId,
            "the allowlist key should be reserved by the same batch"
        );
        assertEq(
            timelock.getQueuedConfigStateCount(actionId, 0) +
                timelock.getQueuedConfigStateCount(actionId, 1),
            4,
            "the batch should hold four keys in total"
        );
    }

    // when every selector's payload is built exactly as its typed helper builds it
    //   [X] each of the seven sub-action shapes queues successfully
    // The per-selector canonicality positive control, on the allowlist rig (the only rig
    // where all seven mirrors can pass); queued as separate batches to avoid domain
    // conflicts
    function test_whenPayloadsAreCanonicalForEverySelector()
        public
        givenAllowListPoolRig
        givenEnabled
        givenChainAdded
    {
        // Each action needs its own route so no two reservations share a domain: route A
        // comes from the fixture and routes B, C, D and E are added directly by the admin
        uint64 selectorC = 4444;
        uint64 selectorD = 5555;
        uint64 selectorE = 6666;
        uint64 freshSelector = 7777;
        _directAddChain(_defaultChainUpdate(CHAIN_SELECTOR_B));
        _directAddChain(_defaultChainUpdate(selectorC));
        _directAddChain(_defaultChainUpdate(selectorD));
        _directAddChain(_defaultChainUpdate(selectorE));

        uint64 firstActionId = timelock.nextActionId();
        ITimelockBatchQueue.BatchAction[][]
            memory batches = new ITimelockBatchQueue.BatchAction[][](7);
        batches[0] = _singleActionBatch(_addChainBatchAction(_defaultChainUpdate(freshSelector)));
        batches[1] = _singleActionBatch(_removeChainBatchAction(CHAIN_SELECTOR_B));
        batches[2] = _singleActionBatch(
            _setRemoteTokenBatchAction(CHAIN_SELECTOR_A, REMOTE_TOKEN_B)
        );
        batches[3] = _singleActionBatch(_addRemotePoolBatchAction(selectorC, REMOTE_POOL_THREE));
        batches[4] = _singleActionBatch(_removeRemotePoolBatchAction(selectorD, REMOTE_POOL_TWO));
        batches[5] = _singleActionBatch(
            _setChainRateLimitsBatchAction(
                selectorE,
                _canonicalOutboundConfig(),
                _canonicalInboundConfig()
            )
        );
        batches[6] = _singleActionBatch(
            _applyAllowListUpdatesBatchAction(new address[](0), _singleAddress(allowListedThree))
        );

        for (uint256 i; i < batches.length; ++i) {
            ITimelockBatchQueue.BatchAction[] memory batch = batches[i];
            vm.prank(bridgeAdmin);
            uint64 actionId = timelock.queueBatch(batch);
            // casting to 'uint64' is safe because the loop counter is at most six
            // forge-lint: disable-next-line(unsafe-typecast)
            uint64 expectedActionId = firstActionId + uint64(i);
            assertEq(
                actionId,
                expectedActionId,
                "each canonical batch should queue with a sequential id"
            );
        }

        // One representative reserved key per action pins that every shape reached storage
        _assertRouteKeysHeldBy(freshSelector, firstActionId, "addChain shape");
        _assertRouteKeysHeldBy(CHAIN_SELECTOR_B, firstActionId + 1, "removeChain shape");
        _assertRouteKeysHeldBy(CHAIN_SELECTOR_A, firstActionId + 2, "setRemoteToken shape");
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(selectorC)),
            firstActionId + 3,
            "the addRemotePool shape should hold its remote pools key"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(selectorD)),
            firstActionId + 4,
            "the removeRemotePool shape should hold its remote pools key"
        );
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(selectorE)),
            firstActionId + 5,
            "the setChainRateLimits shape should hold its rate limits key"
        );
        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            firstActionId + 6,
            "the applyAllowListUpdates shape should hold the allowlist key"
        );
    }
}
