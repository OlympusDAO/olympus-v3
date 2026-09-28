// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

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

    function test_getQueuedAction_givenActionPending() public {
        (uint64 actionId, ITimelockBatchQueue.BatchAction[] memory actions) = _queueThreeBatch();
        ITimelockBatchQueue.QueuedAction memory queued = queue.getQueuedAction(actionId);
        assertEq(queued.proposer, proposer, "proposer");
        assertEq(queued.actions.length, actions.length, "stored action count");
        assertFalse(queued.executed, "not executed");
        assertFalse(queued.cancelled, "not cancelled");
    }

    function test_getQueuedAction_givenActionExecuted() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId);
        queue.executeQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory queued = queue.getQueuedAction(actionId);
        assertTrue(queued.executed, "executed");
        assertFalse(queued.cancelled, "not cancelled");
        assertEq(queued.actions.length, 0, "actions cleared");
        assertEq(queued.proposer, proposer, "proposer retained");
    }

    function test_getQueuedAction_givenActionCancelled() public {
        uint64 actionId = _queueSingleAction();
        queue.cancelQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory queued = queue.getQueuedAction(actionId);
        assertFalse(queued.executed, "not executed");
        assertTrue(queued.cancelled, "cancelled");
        assertEq(queued.actions.length, 0, "actions cleared");
        assertEq(queued.proposer, proposer, "proposer retained");
    }
}
