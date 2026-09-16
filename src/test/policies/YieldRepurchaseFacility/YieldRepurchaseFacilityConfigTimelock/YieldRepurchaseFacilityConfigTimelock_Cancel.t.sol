// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityConfigTimelock.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {YieldRepurchaseFacilityV2} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol";
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {YieldRepurchaseFacilityConfigTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityConfigTimelock/YieldRepurchaseFacilityConfigTimelockTestBase.sol";

contract YieldRepurchaseFacilityConfigTimelockTests_Cancel is
    YieldRepurchaseFacilityConfigTimelockTestBase
{
    // cancelQueuedAction
    // given the caller does not hold the emergency role
    //  when cancelling a queued action
    //   then it reverts with ROLES_RequireRole(emergency)
    function test_givenNonEmergencyCaller_reverts(address caller_) public {
        vm.assume(caller_ != guardian);
        uint64 actionId = _queueSetInitialDiscount(1e16);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        configTimelock.cancelQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given the caller holds only the yrf_admin role
    //  when cancelling a queued action
    //   then it reverts (the emergency role is the sole canceller)
    function test_givenYrfAdminCaller_reverts() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);

        vm.prank(yrfAdmin);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        configTimelock.cancelQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given the action id has never been queued
    //  when the emergency role cancels it
    //   then it reverts with ITimelockBatchQueue_ActionNotFound
    function test_givenActionNotFound_reverts() public {
        uint64 actionId = configTimelock.nextActionId();

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                actionId
            )
        );
        configTimelock.cancelQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given the action has already been executed
    //  when the emergency role cancels it
    //   then it reverts with ITimelockBatchQueue_ActionAlreadyExecuted
    function test_givenExecutedAction_reverts() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        _warpToExecutable(configTimelock, actionId);
        configTimelock.executeQueuedAction(actionId);

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        configTimelock.cancelQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given the action has already been cancelled
    //  when the emergency role cancels it again
    //   then it reverts with ITimelockBatchQueue_ActionCancelled
    function test_givenCancelledAction_reverts() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        vm.prank(guardian);
        configTimelock.cancelQueuedAction(actionId);

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        configTimelock.cancelQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given a cancelled action
    //  when executing it at any later timestamp
    //   then execution reverts with ITimelockBatchQueue_ActionCancelled
    function test_givenCancelledAction_executionReverts(uint48 elapsed_) public {
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueSetInitialDiscount(1e16);
        elapsed_ = uint48(bound(elapsed_, 0, type(uint48).max));

        vm.prank(guardian);
        configTimelock.cancelQueuedAction(actionId);
        vm.warp(queuedAt + elapsed_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 0, "discount unchanged");
    }

    // cancelQueuedAction
    // given a cancelled action
    //  when reading getQueuedActionLength
    //   then it reverts with ITimelockBatchQueue_ActionCancelled
    function test_givenCancelledAction_cannotReadLength() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        vm.prank(guardian);
        configTimelock.cancelQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        configTimelock.getQueuedActionLength(actionId);
    }

    // cancelQueuedAction
    // given the timelock policy is disabled
    //  when the emergency role cancels a queued action
    //   then it cancels (cancellation is available while disabled)
    function test_givenTimelockDisabled_allowsEmergencyCancellation() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        vm.prank(guardian);
        configTimelock.disable("");

        assertFalse(configTimelock.isEnabled(), "disabled");
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(actionId, guardian);
        vm.prank(guardian);
        configTimelock.cancelQueuedAction(actionId);

        assertTrue(configTimelock.getQueuedAction(actionId).cancelled, "cancelled");
    }

    // cancelQueuedAction
    // given the action has expired without execution
    //  when the emergency role cancels it
    //   then it cancels and releases the held pending slot
    function test_givenExpiredAction_allowsEmergencyCancellation() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        _warpPastExpiry(configTimelock, actionId);

        vm.prank(guardian);
        configTimelock.cancelQueuedAction(actionId);

        assertTrue(configTimelock.getQueuedAction(actionId).cancelled, "cancelled");
        assertEq(configTimelock.pendingInitialDiscountActionId(), 0, "pending slot released");
        assertEq(_queueSetInitialDiscount(2e16), actionId + 1, "parameter can be queued again");
    }

    // cancelQueuedAction
    // given a queued action
    //  when the emergency role cancels at any timestamp before finalization
    //   then the action is cancelled, sub-actions are cleared, and the event is emitted
    function test_givenEmergencyCaller_cancelsAction(uint48 elapsed_) public {
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueSetInitialDiscount(1e16);
        elapsed_ = uint48(bound(elapsed_, 0, type(uint48).max));
        vm.warp(queuedAt + elapsed_);

        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(actionId, guardian);
        vm.prank(guardian);
        configTimelock.cancelQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId);
        assertTrue(action.cancelled, "cancelled");
        assertFalse(action.executed, "not executed");
        assertEq(action.actions.length, 0, "sub-actions cleared");
        assertEq(action.proposer, yrfAdmin, "proposer metadata retained");
        assertEq(action.queuedAt, queuedAt, "queuedAt metadata retained");
    }

    // cancelQueuedAction
    // given a queued batch
    //  when the emergency role cancels it
    //   then the batch is cancelled and every stored sub-action is cleared
    function test_givenEmergencyCaller_cancelsBatchAndClearsSubActions(uint48 elapsed_) public {
        uint256 queuedAt = vm.getBlockTimestamp();
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _facilityAction(
            IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
            abi.encode(uint256(1e16))
        );
        actions[1] = _facilityAction(
            IYieldRepurchaseFacilityV2.increaseClearinghouseOffset.selector,
            abi.encode(address(clearinghouse), uint256(0))
        );
        uint64 actionId = _queueBatch(actions);
        elapsed_ = uint48(bound(elapsed_, 0, type(uint48).max));
        vm.warp(queuedAt + elapsed_);

        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(actionId, guardian);
        vm.prank(guardian);
        configTimelock.cancelQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId);
        assertTrue(action.cancelled, "cancelled");
        assertEq(action.actions.length, 0, "sub-actions cleared");
        assertEq(configTimelock.pendingInitialDiscountActionId(), 0, "pending slot released");
    }

    // cancelQueuedAction
    // given a cancelled batch that held pending parameter slots
    //  when reading the pending slot views and the recorded per-sub-action state
    //   then they are cleared and the parameters can be queued again
    function test_givenCancelledAction_releasesPendingSlots() public {
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
        assertEq(timelockHarness.lockKey(actionId, 0), shareLockKey, "share lock key stored");
        assertEq(timelockHarness.lockKey(actionId, 1), discountLockKey, "discount lock key stored");
        // The share was registered as 1e18 and the discount is unset, so the pre-state
        // hashes bind those values.
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

        vm.prank(guardian);
        timelockHarness.cancelQueuedAction(actionId);

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
            timelockHarness.queueSetYieldBuybackShare(address(sReserve), 5e17),
            actionId + 1,
            "share can be queued again"
        );
        vm.prank(yrfAdmin);
        assertEq(
            timelockHarness.queueSetInitialDiscount(1e16),
            actionId + 2,
            "discount can be queued again"
        );
    }

    // cancelQueuedAction
    // given a locked-parameter action queued against a previous facility
    //  when the emergency role cancels it after the rotation
    //   then the slot is released and the parameter can be queued against the new facility
    function test_givenFacilityRotated_cancellationReleasesSlotForNewFacility() public {
        uint64 staleActionId = _queueSetInitialDiscount(1e16);
        YieldRepurchaseFacilityV2 newFacility = _deployFacilityPinnedTo(address(configTimelock));
        vm.prank(guardian);
        configTimelock.setFacility(address(newFacility));

        vm.prank(guardian);
        configTimelock.cancelQueuedAction(staleActionId);

        assertEq(configTimelock.pendingInitialDiscountActionId(), 0, "pending slot released");
        uint64 actionId = _queueSetInitialDiscount(2e16);
        assertEq(actionId, staleActionId + 1, "parameter can be queued again");
        (address target, , ) = configTimelock.getQueuedSubAction(actionId, 0);
        assertEq(target, address(newFacility), "queued against the new facility");
    }
}
