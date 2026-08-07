// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYRFTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYRFTimelock.sol";

// Contracts
import {YieldRepurchaseFacilityV2} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol";

import {YRFTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YRFTimelock/YRFTimelockTestBase.sol";

contract YRFTimelockTests_Execute is YRFTimelockTestBase {
    // executeQueuedAction
    // given the action id has never been queued
    //  when executing it
    //   then it reverts with ITimelockBatchQueue_ActionNotFound
    function test_givenActionNotFound_reverts() public {
        uint64 actionId = yrfTimelock.nextActionId();

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                actionId
            )
        );
        yrfTimelock.executeQueuedAction(actionId);
    }

    // executeQueuedAction
    // given a queued action
    //  when called at any timestamp before the timelock delay has elapsed
    //   then it reverts with ITimelockBatchQueue_ActionNotReady and the facility is unchanged
    function test_givenBeforeDelay_reverts(uint48 elapsed_) public {
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueSetInitialDiscount(1e16);
        ITimelockBatchQueue.QueuedAction memory action = yrfTimelock.getQueuedAction(actionId);
        elapsed_ = uint48(bound(elapsed_, 0, yrfTimelockDelay - 1));
        vm.warp(queuedAt + elapsed_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                actionId,
                action.executableAt
            )
        );
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 0, "discount unchanged");
    }

    // executeQueuedAction
    // given a queued action
    //  when called at any timestamp after the execution window expires
    //   then it reverts with ITimelockBatchQueue_ActionExpired and the facility is unchanged
    function test_givenExpired_reverts(uint48 elapsed_) public {
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueSetInitialDiscount(1e16);
        ITimelockBatchQueue.QueuedAction memory action = yrfTimelock.getQueuedAction(actionId);
        uint48 firstExpiredElapsed = yrfTimelockDelay + yrfTimelock.EXECUTION_WINDOW() + 1;
        elapsed_ = uint48(bound(elapsed_, firstExpiredElapsed, type(uint48).max));
        vm.warp(queuedAt + elapsed_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 0, "discount unchanged");
    }

    // executeQueuedAction
    // given the action has already been executed
    //  when executing it again
    //   then it reverts with ITimelockBatchQueue_ActionAlreadyExecuted
    function test_givenExecutedAction_reverts() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        _warpToExecutable(yrfTimelock, actionId);
        yrfTimelock.executeQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        yrfTimelock.executeQueuedAction(actionId);
    }

    // executeQueuedAction
    // given the action has been cancelled
    //  when executing it
    //   then it reverts with ITimelockBatchQueue_ActionCancelled
    function test_givenCancelledAction_reverts() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        vm.prank(guardian);
        yrfTimelock.cancelQueuedAction(actionId);
        _warpToExecutable(yrfTimelock, actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        yrfTimelock.executeQueuedAction(actionId);
    }

    // executeQueuedAction
    // given the timelock policy is disabled
    //  when executing a ready action
    //   then it reverts with NotEnabled
    function test_givenTimelockDisabled_reverts() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        vm.prank(guardian);
        yrfTimelock.disable("");
        _warpToExecutable(yrfTimelock, actionId);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        yrfTimelock.executeQueuedAction(actionId);
    }

    // executeQueuedAction
    // given the timelock was disabled and re-enabled within the grace window
    //  when executing a still-unexpired queued action
    //   then it executes (the queue survives the disable)
    function test_givenTimelockReEnabled_executesAction() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        vm.prank(guardian);
        yrfTimelock.disable("");
        // One day of downtime: within the 7-day grace window, and exactly at executableAt.
        _warpToExecutable(yrfTimelock, actionId);

        vm.prank(yrfAdmin);
        yrfTimelock.reEnable();
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 1e16, "discount applied");
    }

    // executeQueuedAction
    // given the grace window expired and the admin restarted the policy through `enable`
    //  when executing a still-unexpired queued action
    //   then it executes (the queue also survives the full enable path)
    function test_givenTimelockEnabledAfterGraceExpiry_executesAction() public {
        // Shrink the grace window below the timelock delay so that it can expire while the
        // action's execution window is still open.
        vm.prank(guardian);
        yrfTimelock.setGracePeriod(1 hours);
        uint256 disabledAt = vm.getBlockTimestamp();
        uint64 actionId = _queueSetInitialDiscount(1e16);
        vm.prank(guardian);
        yrfTimelock.disable("");
        vm.warp(disabledAt + 2 hours);

        // The grace path is closed, so the yrf_admin cannot resume the policy.
        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGracePeriod.GracePeriod_Expired.selector,
                uint48(disabledAt + 1 hours)
            )
        );
        yrfTimelock.reEnable();

        vm.prank(guardian);
        yrfTimelock.enable("");
        _warpToExecutable(yrfTimelock, actionId);
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 1e16, "discount applied");
    }

    // executeQueuedAction
    // given a locked-parameter action whose execution reverted as stale
    //  when reading the pending slot views after the failed execution
    //   then the slot is still held (the revert rolls back the slot release)
    function test_givenStaleExecutionReverted_pendingSlotStillHeld() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        // The admin overwrites the discount directly, invalidating the queue-time binding.
        vm.prank(guardian);
        yieldRepo.setInitialDiscount(5e16);
        _warpToExecutable(yrfTimelock, actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYRFTimelock.IYRFTimelock_PreStateChanged.selector,
                actionId,
                uint256(0),
                keccak256(abi.encode(uint256(0))),
                keccak256(abi.encode(uint256(5e16)))
            )
        );
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yrfTimelock.pendingInitialDiscountActionId(), actionId, "pending slot held");
        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYRFTimelock.IYRFTimelock_ConflictingActionPending.selector,
                IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
                actionId
            )
        );
        yrfTimelock.queueSetInitialDiscount(2e16);
    }

    // executeQueuedAction
    // given the facility is disabled
    //  when executing a ready action
    //   then it executes (facility downtime is a supported execution path)
    function test_givenFacilityDisabled_executesAction() public {
        _enableFacility();
        uint64 actionId = _queueSetInitialDiscount(1e16);
        vm.prank(guardian);
        yieldRepo.disable("");
        _warpToExecutable(yrfTimelock, actionId);

        yrfTimelock.executeQueuedAction(actionId);

        assertFalse(yieldRepo.isEnabled(), "facility still disabled");
        assertEq(yieldRepo.initialDiscount(), 1e16, "discount applied");
    }

    // executeQueuedAction
    // given the facility slot was rotated after the queue
    //  when executing the action
    //   then it reverts with IYRFTimelock_FacilityStale
    function test_givenFacilityRotated_revertsAsStale() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        YieldRepurchaseFacilityV2 newFacility = _deployFacilityPinnedTo(address(yrfTimelock));
        vm.prank(guardian);
        yrfTimelock.setFacility(address(newFacility));
        _warpToExecutable(yrfTimelock, actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYRFTimelock.IYRFTimelock_FacilityStale.selector,
                actionId,
                uint256(0),
                address(yieldRepo),
                address(newFacility)
            )
        );
        yrfTimelock.executeQueuedAction(actionId);
    }

    // executeQueuedAction
    // given the facility slot was rotated away and back to the queued facility
    //  when executing the action within its window
    //   then it executes (the stale check compares against the live slot)
    function test_givenFacilityRotatedBack_executesAction() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        YieldRepurchaseFacilityV2 newFacility = _deployFacilityPinnedTo(address(yrfTimelock));
        vm.startPrank(guardian);
        yrfTimelock.setFacility(address(newFacility));
        yrfTimelock.setFacility(address(yieldRepo));
        vm.stopPrank();
        _warpToExecutable(yrfTimelock, actionId);

        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 1e16, "discount applied");
    }

    // executeQueuedAction
    // given a valid queued action
    //  when any caller executes at any timestamp within the execution window
    //   then the facility call is applied and the execution events are emitted
    function test_givenDelayElapsed_executesAction(address executor_, uint48 elapsed_) public {
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueSetInitialDiscount(1e16);
        elapsed_ = uint48(
            bound(elapsed_, yrfTimelockDelay, yrfTimelockDelay + yrfTimelock.EXECUTION_WINDOW())
        );
        vm.warp(queuedAt + elapsed_);
        ITimelockBatchQueue.BatchAction[] memory actions = _singleAction(
            address(yieldRepo),
            IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
            abi.encode(uint256(1e16))
        );

        // The facility event precedes the sub-action event, which precedes the closing event.
        vm.expectEmit(false, false, false, true, address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.InitialDiscountSet(1e16);
        _expectActionExecuted(yrfTimelock, actionId, executor_, actions);
        vm.prank(executor_);
        yrfTimelock.executeQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory action = yrfTimelock.getQueuedAction(actionId);
        assertTrue(action.executed, "executed");
        assertEq(action.actions.length, 0, "sub-actions cleared");
        assertEq(yieldRepo.initialDiscount(), 1e16, "discount applied");
    }

    // executeQueuedAction
    // given a valid batch covering every supported selector
    //  when any caller executes within the execution window
    //   then all sub-actions apply in array order with interleaved events
    function test_givenDelayElapsed_executesBatchInOrder(
        address executor_,
        uint48 elapsed_
    ) public {
        // Backing asset for the share update and the next-yield correction; two secondary
        // assets so that the batch can both enable a disabled asset and disable an enabled
        // one; an included Clearinghouse for the exclusion; receivables for the offset.
        _registerBackingAsset(yieldRepo, 100e18);
        address vaultToDisable = _registerSecondaryAsset(yieldRepo, "vaultToDisable", 0);
        address vaultToEnable = _registerSecondaryAsset(yieldRepo, "vaultToEnable", 0);
        address includedClearinghouse = address(includableClearinghouse);
        vm.startPrank(guardian);
        yieldRepo.disableAsset(vaultToEnable);
        yieldRepo.includeClearinghouse(includedClearinghouse);
        vm.stopPrank();
        clearinghouse.setPrincipalReceivables(1_000e18);

        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](7);
        actions[0] = _facilityAction(
            IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
            abi.encode(uint256(2e16))
        );
        actions[1] = _facilityAction(
            IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
            abi.encode(address(sReserve), uint256(5e17))
        );
        actions[2] = _facilityAction(
            IYieldRepurchaseFacilityV2.enableAsset.selector,
            abi.encode(vaultToEnable)
        );
        actions[3] = _facilityAction(
            IYieldRepurchaseFacilityV2.disableAsset.selector,
            abi.encode(vaultToDisable)
        );
        actions[4] = _facilityAction(
            IYieldRepurchaseFacilityV2.excludeClearinghouse.selector,
            abi.encode(includedClearinghouse)
        );
        actions[5] = _facilityAction(
            IYieldRepurchaseFacilityV2.increaseClearinghouseOffset.selector,
            abi.encode(address(clearinghouse), uint256(250e18))
        );
        actions[6] = _facilityAction(
            IYieldRepurchaseFacilityV2.decreaseNextYield.selector,
            abi.encode(address(sReserve), uint256(100e18), uint256(40e18))
        );
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueBatch(actions);
        elapsed_ = uint48(
            bound(elapsed_, yrfTimelockDelay, yrfTimelockDelay + yrfTimelock.EXECUTION_WINDOW())
        );
        vm.warp(queuedAt + elapsed_);

        _expectActionExecuted(yrfTimelock, actionId, executor_, actions);
        vm.prank(executor_);
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 2e16, "discount applied");
        assertEq(
            yieldRepo.getAssetConfig(address(sReserve)).yieldBuybackShare,
            5e17,
            "share applied"
        );
        assertTrue(yieldRepo.getAssetConfig(vaultToEnable).isAssetEnabled, "asset enabled");
        assertFalse(yieldRepo.getAssetConfig(vaultToDisable).isAssetEnabled, "asset disabled");
        assertFalse(
            yieldRepo.isClearinghouseIncluded(includedClearinghouse),
            "clearinghouse excluded"
        );
        assertEq(yieldRepo.clearinghouseOffset(address(clearinghouse)), 250e18, "offset increased");
        assertEq(
            yieldRepo.getAssetConfig(address(sReserve)).nextYield,
            40e18,
            "next yield decreased"
        );
        ITimelockBatchQueue.QueuedAction memory action = yrfTimelock.getQueuedAction(actionId);
        assertTrue(action.executed, "executed");
        assertEq(action.actions.length, 0, "sub-actions cleared");
    }

    // executeQueuedAction
    // given a queued batch
    //  when called at any timestamp before the timelock delay has elapsed
    //   then it reverts and no sub-action is applied
    function test_givenBatchBeforeDelay_reverts(uint48 elapsed_) public {
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueBatch(_discountAndOffsetBatch());
        ITimelockBatchQueue.QueuedAction memory action = yrfTimelock.getQueuedAction(actionId);
        elapsed_ = uint48(bound(elapsed_, 0, yrfTimelockDelay - 1));
        vm.warp(queuedAt + elapsed_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                actionId,
                action.executableAt
            )
        );
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 0, "discount unchanged");
        assertEq(yieldRepo.clearinghouseOffset(address(clearinghouse)), 0, "offset unchanged");
    }

    // executeQueuedAction
    // given a queued batch
    //  when called at any timestamp after the execution window expires
    //   then it reverts and no sub-action is applied
    function test_givenBatchExpired_reverts(uint48 elapsed_) public {
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueBatch(_discountAndOffsetBatch());
        ITimelockBatchQueue.QueuedAction memory action = yrfTimelock.getQueuedAction(actionId);
        uint48 firstExpiredElapsed = yrfTimelockDelay + yrfTimelock.EXECUTION_WINDOW() + 1;
        elapsed_ = uint48(bound(elapsed_, firstExpiredElapsed, type(uint48).max));
        vm.warp(queuedAt + elapsed_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 0, "discount unchanged");
        assertEq(yieldRepo.clearinghouseOffset(address(clearinghouse)), 0, "offset unchanged");
    }

    // executeQueuedAction
    // given a batch whose later sub-action fails facility re-validation
    //  when executing the batch
    //   then the whole batch reverts and the earlier sub-action is rolled back
    function test_givenLaterSubActionReverts_revertsAtomically() public {
        address includedClearinghouse = address(includableClearinghouse);
        vm.prank(guardian);
        yieldRepo.includeClearinghouse(includedClearinghouse);
        // Both duplicate exclusions are valid against the live queue-time state; at
        // execution the first one flips the flag and the second reverts on the facility.
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _facilityAction(
            IYieldRepurchaseFacilityV2.excludeClearinghouse.selector,
            abi.encode(includedClearinghouse)
        );
        actions[1] = _facilityAction(
            IYieldRepurchaseFacilityV2.excludeClearinghouse.selector,
            abi.encode(includedClearinghouse)
        );
        uint64 actionId = _queueBatch(actions);
        _warpToExecutable(yrfTimelock, actionId);

        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_ClearinghouseNotIncluded.selector
        );
        yrfTimelock.executeQueuedAction(actionId);

        assertTrue(
            yieldRepo.isClearinghouseIncluded(includedClearinghouse),
            "first exclusion rolled back"
        );
        assertFalse(yrfTimelock.getQueuedAction(actionId).executed, "executed flag rolled back");
        // The stuck batch remains cancellable.
        vm.prank(guardian);
        yrfTimelock.cancelQueuedAction(actionId);
        assertTrue(yrfTimelock.getQueuedAction(actionId).cancelled, "cancelled");
    }

    // executeQueuedAction
    // given an executed batch that held pending parameter slots
    //  when reading the pending slot views and the recorded per-sub-action state
    //   then they are cleared and the parameters can be queued again
    function test_givenExecutedAction_releasesPendingSlots() public {
        _registerBackingAsset(harnessFacility, 0);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _harnessAction(
            IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
            abi.encode(address(sReserve), uint256(5e17))
        );
        actions[1] = _harnessAction(
            IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
            abi.encode(uint256(1e16))
        );
        vm.prank(yrfAdmin);
        uint64 actionId = timelockHarness.queueBatch(actions);

        bytes32 shareLockKey = _yieldBuybackShareLockKey(address(sReserve));
        bytes32 discountLockKey = _initialDiscountLockKey();
        // The share was registered as 1e18 and the discount is unset, so the pre-state
        // hashes bind those values.
        assertEq(timelockHarness.lockKey(actionId, 0), shareLockKey, "share lock key stored");
        assertEq(timelockHarness.lockKey(actionId, 1), discountLockKey, "discount lock key stored");
        assertEq(
            timelockHarness.expectedPreStateHash(actionId, 0),
            keccak256(abi.encode(address(sReserve), uint256(1e18))),
            "share pre-state stored"
        );
        assertEq(
            timelockHarness.expectedPreStateHash(actionId, 1),
            keccak256(abi.encode(uint256(0))),
            "discount pre-state stored"
        );
        assertEq(timelockHarness.pendingActionId(shareLockKey), actionId, "share slot held");
        assertEq(timelockHarness.pendingActionId(discountLockKey), actionId, "discount slot held");

        _warpToExecutable(timelockHarness, actionId);
        timelockHarness.executeQueuedAction(actionId);

        assertEq(
            harnessFacility.getAssetConfig(address(sReserve)).yieldBuybackShare,
            5e17,
            "share applied"
        );
        assertEq(harnessFacility.initialDiscount(), 1e16, "discount applied");
        assertEq(timelockHarness.lockKey(actionId, 0), bytes32(0), "share lock key cleared");
        assertEq(timelockHarness.lockKey(actionId, 1), bytes32(0), "discount lock key cleared");
        assertEq(
            timelockHarness.expectedPreStateHash(actionId, 0),
            bytes32(0),
            "share pre-state cleared"
        );
        assertEq(
            timelockHarness.expectedPreStateHash(actionId, 1),
            bytes32(0),
            "discount pre-state cleared"
        );
        assertEq(timelockHarness.pendingActionId(shareLockKey), 0, "share slot released");
        assertEq(timelockHarness.pendingActionId(discountLockKey), 0, "discount slot released");
        assertEq(
            timelockHarness.pendingYieldBuybackShareActionId(address(sReserve)),
            0,
            "share pending view"
        );
        assertEq(timelockHarness.pendingInitialDiscountActionId(), 0, "discount pending view");

        vm.prank(yrfAdmin);
        assertEq(
            timelockHarness.queueSetYieldBuybackShare(address(sReserve), 6e17),
            actionId + 1,
            "share can be queued again"
        );
        vm.prank(yrfAdmin);
        assertEq(
            timelockHarness.queueSetInitialDiscount(2e16),
            actionId + 2,
            "discount can be queued again"
        );
    }

    // executeQueuedAction
    // given an executed action
    //  when reading getQueuedAction
    //   then the metadata remains readable and the sub-actions array is empty
    function test_givenExecutedAction_keepsAuditMetadata() public {
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueSetInitialDiscount(1e16);
        _warpToExecutable(yrfTimelock, actionId);
        yrfTimelock.executeQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory action = yrfTimelock.getQueuedAction(actionId);
        assertEq(action.proposer, yrfAdmin, "proposer");
        assertEq(action.queuedAt, queuedAt, "queuedAt");
        assertEq(action.executableAt, queuedAt + yrfTimelockDelay, "executableAt");
        assertEq(
            action.expiresAt,
            queuedAt + yrfTimelockDelay + yrfTimelock.EXECUTION_WINDOW(),
            "expiresAt"
        );
        assertTrue(action.executed, "executed");
        assertFalse(action.cancelled, "not cancelled");
        assertEq(action.actions.length, 0, "sub-actions cleared");
    }

    // executeQueuedAction
    // given an executed action
    //  when reading getQueuedActionLength or getQueuedSubAction
    //   then they revert with ITimelockBatchQueue_ActionAlreadyExecuted
    function test_givenExecutedAction_cannotReadSubActions() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        _warpToExecutable(yrfTimelock, actionId);
        yrfTimelock.executeQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        yrfTimelock.getQueuedActionLength(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        yrfTimelock.getQueuedSubAction(actionId, 0);
    }

    // ========== HELPERS ========== //

    /// @notice A two-selector batch that requires no facility state preparation.
    function _discountAndOffsetBatch()
        private
        view
        returns (ITimelockBatchQueue.BatchAction[] memory actions)
    {
        actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _facilityAction(
            IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
            abi.encode(uint256(1e16))
        );
        actions[1] = _facilityAction(
            IYieldRepurchaseFacilityV2.increaseClearinghouseOffset.selector,
            abi.encode(address(clearinghouse), uint256(0))
        );
    }
}
