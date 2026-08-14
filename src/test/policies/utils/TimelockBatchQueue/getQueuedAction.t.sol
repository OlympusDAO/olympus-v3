// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";

contract TimelockBatchQueueGetQueuedActionTest is TimelockBatchQueueTest {
    function test_getQueuedAction_givenUnknownAction_reverts(uint64 actionId_) public {
        vm.assume(actionId_ != 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                actionId_
            )
        );
        queue.getQueuedAction(actionId_);
    }

    function test_getQueuedAction_returnsCompletePendingAction() public {
        (uint64 actionId, ITimelockBatchQueue.BatchAction[] memory actions) = _queueThreeBatch();
        ITimelockBatchQueue.QueuedAction memory queued = queue.getQueuedAction(actionId);
        assertEq(queued.proposer, proposer);
        assertEq(queued.actions.length, actions.length);
        assertFalse(queued.executed);
        assertFalse(queued.cancelled);
    }

    function test_getQueuedAction_afterExecution_returnsHistoricalRecord() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId);
        queue.executeQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory queued = queue.getQueuedAction(actionId);
        assertTrue(queued.executed);
        assertFalse(queued.cancelled);
        assertEq(queued.actions.length, 0);
    }

    function test_getQueuedAction_afterCancellation_returnsHistoricalRecord() public {
        uint64 actionId = _queueSingleAction();
        queue.cancelQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory queued = queue.getQueuedAction(actionId);
        assertFalse(queued.executed);
        assertTrue(queued.cancelled);
        assertEq(queued.actions.length, 0);
    }
}
