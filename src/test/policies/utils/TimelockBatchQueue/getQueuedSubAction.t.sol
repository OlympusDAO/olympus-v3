// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";

contract TimelockBatchQueueGetQueuedSubActionTest is TimelockBatchQueueTest {
    function test_getQueuedSubAction_returnsEachStoredAction() public {
        (uint64 actionId, ITimelockBatchQueue.BatchAction[] memory actions) = _queueThreeBatch();
        for (uint256 i; i < actions.length; ++i) {
            (address target, bytes4 selector, bytes memory payload) = queue.getQueuedSubAction(
                actionId,
                i
            );
            assertEq(target, actions[i].target);
            assertEq(selector, actions[i].selector);
            assertEq(payload, actions[i].payload);
        }
    }

    function test_getQueuedSubAction_givenUnknownAction_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                uint64(99)
            )
        );
        queue.getQueuedSubAction(99, 0);
    }

    function test_getQueuedSubAction_givenOutOfBoundsIndex_reverts(uint256 index_) public {
        uint64 actionId = _queueSingleAction();
        index_ = bound(index_, 1, type(uint128).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_SubActionIndexOutOfBounds.selector,
                actionId,
                index_,
                uint256(1)
            )
        );
        queue.getQueuedSubAction(actionId, index_);
    }

    function test_getQueuedSubAction_givenExecutedAction_reverts() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId);
        queue.executeQueuedAction(actionId);
        _expectTerminalRevert(
            actionId,
            ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector
        );
    }

    function test_getQueuedSubAction_givenCancelledAction_reverts() public {
        uint64 actionId = _queueSingleAction();
        queue.cancelQueuedAction(actionId);
        _expectTerminalRevert(
            actionId,
            ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector
        );
    }

    function _expectTerminalRevert(uint64 actionId_, bytes4 selector_) internal {
        vm.expectRevert(abi.encodeWithSelector(selector_, actionId_));
        queue.getQueuedSubAction(actionId_, 0);
    }
}
