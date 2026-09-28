// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";

contract TimelockBatchQueueGetQueuedActionLengthTest is TimelockBatchQueueTest {
    function test_getQueuedActionLength_givenSingleAndBatchActionsQueued() public {
        assertEq(queue.getQueuedActionLength(_queueSingleAction()), 1, "single action length");
        (uint64 actionId, ) = _queueThreeBatch();
        assertEq(queue.getQueuedActionLength(actionId), 3, "batch action length");
    }

    function test_getQueuedActionLength_givenUnknownAction_reverts(uint64 actionId_) public {
        vm.assume(actionId_ != 0);
        _expectRevert(actionId_, ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector);
    }

    function test_getQueuedActionLength_givenExecutedAction_reverts() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId);
        queue.executeQueuedAction(actionId);
        _expectRevert(
            actionId,
            ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector
        );
    }

    function test_getQueuedActionLength_givenCancelledAction_reverts() public {
        uint64 actionId = _queueSingleAction();
        queue.cancelQueuedAction(actionId);
        _expectRevert(actionId, ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector);
    }

    function _expectRevert(uint64 actionId_, bytes4 selector_) internal {
        vm.expectRevert(abi.encodeWithSelector(selector_, actionId_));
        queue.getQueuedActionLength(actionId_);
    }
}
