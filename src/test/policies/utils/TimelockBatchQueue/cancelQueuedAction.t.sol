// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";
import {MockTimelockBatchQueue} from "src/test/policies/utils/TimelockBatchQueue/fixtures/MockTimelockBatchQueue.sol";

contract TimelockBatchQueueCancelQueuedActionTest is TimelockBatchQueueTest {
    function test_cancelQueuedAction_givenUnknownAction_reverts(uint64 actionId_) public {
        vm.assume(actionId_ != 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                actionId_
            )
        );
        queue.cancelQueuedAction(actionId_);
    }

    function test_cancelQueuedAction_givenExecutedAction_reverts() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId);
        queue.executeQueuedAction(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.cancelQueuedAction(actionId);
    }

    function test_cancelQueuedAction_givenCancelledAction_reverts() public {
        uint64 actionId = _queueSingleAction();
        queue.cancelQueuedAction(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        queue.cancelQueuedAction(actionId);
    }

    function test_cancelQueuedAction_givenCancellationRejected_rollsBack() public {
        uint64 actionId = _queueSingleAction();
        queue.setRejectCancellation(true);
        vm.expectRevert(
            MockTimelockBatchQueue.MockTimelockBatchQueue_CancellationRejected.selector
        );
        queue.cancelQueuedAction(actionId);

        assertFalse(queue.getQueuedAction(actionId).cancelled, "not cancelled");
        assertEq(queue.getQueuedActionLength(actionId), 1, "action retained");
        assertEq(queue.getCancellationCalls().length, 0, "cancellation hook not called");
    }

    function test_cancelQueuedAction_givenWrongCaller_reverts() public {
        uint64 actionId = _queueSingleAction();
        queue.setCancellationCaller(canceller);
        vm.prank(address(0xBAD));
        vm.expectRevert(
            MockTimelockBatchQueue.MockTimelockBatchQueue_CancellationRejected.selector
        );
        queue.cancelQueuedAction(actionId);
    }

    function test_cancelQueuedAction_givenCancellationHookReverts_rollsBackWholeCancellation()
        public
    {
        uint64 actionId = _queueSingleAction();
        queue.setRejectCancellationHook(true);
        vm.expectRevert(
            MockTimelockBatchQueue.MockTimelockBatchQueue_CancellationHookReverted.selector
        );
        queue.cancelQueuedAction(actionId);

        assertFalse(queue.getQueuedAction(actionId).cancelled, "not cancelled");
        assertEq(queue.getQueuedActionLength(actionId), 1, "action retained");
        assertEq(queue.getCancellationCalls().length, 0, "cancellation hook not called");
    }

    function test_cancelQueuedAction_givenBatchQueued_whenCallerIsNonZero(address caller_) public {
        vm.assume(caller_ != address(0));
        (uint64 actionId, ) = _queueThreeBatch();
        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionCancelled(actionId, caller_);
        vm.prank(caller_);
        queue.cancelQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        assertTrue(action.cancelled, "cancelled");
        assertFalse(action.executed, "not executed");
        assertEq(action.actions.length, 0, "actions cleared");
        MockTimelockBatchQueue.CancellationCall[] memory calls = queue.getCancellationCalls();
        assertEq(calls.length, 1, "cancellation call count");
        assertEq(calls[0].actionId, actionId, "cancellation action ID");
        assertEq(calls[0].subActionCount, 3, "cancelled sub-action count");
    }

    function test_cancelQueuedAction_givenSingleAction_whenCallerIsNonZero(address caller_) public {
        vm.assume(caller_ != address(0));
        uint64 actionId = _queueSingleAction();
        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionCancelled(actionId, caller_);
        vm.prank(caller_);
        queue.cancelQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        assertTrue(action.cancelled, "cancelled");
        assertEq(action.actions.length, 0, "actions cleared");

        MockTimelockBatchQueue.CancellationCall[] memory calls = queue.getCancellationCalls();
        assertEq(calls.length, 1, "cancellation call count");
        assertEq(calls[0].actionId, actionId, "cancellation action ID");
        assertEq(calls[0].subActionCount, 1, "cancelled sub-action count");
    }

    function test_cancelQueuedAction_givenActionReady() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId);
        queue.cancelQueuedAction(actionId);
        assertTrue(queue.getQueuedAction(actionId).cancelled, "cancelled after ready");
    }

    function test_cancelQueuedAction_givenActionExpired() public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        vm.warp(uint256(action.expiresAt) + 1);
        queue.cancelQueuedAction(actionId);
        assertTrue(queue.getQueuedAction(actionId).cancelled, "cancelled after expiry");
    }
}
