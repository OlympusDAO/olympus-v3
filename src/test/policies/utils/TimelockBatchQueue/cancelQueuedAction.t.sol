// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";
import {MockTimelockBatchQueue} from "src/test/policies/utils/TimelockBatchQueue/fixtures/MockTimelockBatchQueue.sol";

contract TimelockBatchQueueCancelQueuedActionTest is TimelockBatchQueueTest {
    function test_cancelQueuedAction_givenUnknownAction_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                uint64(99)
            )
        );
        queue.cancelQueuedAction(99);
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

        assertFalse(queue.getQueuedAction(actionId).cancelled);
        assertEq(queue.getQueuedActionLength(actionId), 1);
        assertEq(queue.getCancellationCalls().length, 0);
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

        assertFalse(queue.getQueuedAction(actionId).cancelled);
        assertEq(queue.getQueuedActionLength(actionId), 1);
        assertEq(queue.getCancellationCalls().length, 0);
    }

    function test_cancelQueuedAction_cancelsBatchAndCallsHook() public {
        (uint64 actionId, ) = _queueThreeBatch();
        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionCancelled(actionId, canceller);
        vm.prank(canceller);
        queue.cancelQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        assertTrue(action.cancelled);
        assertFalse(action.executed);
        assertEq(action.actions.length, 0);
        MockTimelockBatchQueue.CancellationCall[] memory calls = queue.getCancellationCalls();
        assertEq(calls.length, 1);
        assertEq(calls[0].actionId, actionId);
        assertEq(calls[0].subActionCount, 3);
    }

    function test_cancelQueuedAction_succeedsAfterActionIsReady() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId);
        queue.cancelQueuedAction(actionId);
        assertTrue(queue.getQueuedAction(actionId).cancelled);
    }

    function test_cancelQueuedAction_succeedsAfterActionExpires() public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        vm.warp(uint256(action.expiresAt) + 1);
        queue.cancelQueuedAction(actionId);
        assertTrue(queue.getQueuedAction(actionId).cancelled);
    }
}
