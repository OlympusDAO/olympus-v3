// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";
import {MockTimelockBatchQueue} from "src/test/policies/utils/TimelockBatchQueue/fixtures/MockTimelockBatchQueue.sol";

contract TimelockBatchQueueExecuteQueuedActionTest is TimelockBatchQueueTest {
    function test_executeQueuedAction_givenUnknownAction_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                uint64(99)
            )
        );
        queue.executeQueuedAction(99);
    }

    function test_executeQueuedAction_givenActionNotReady_reverts(uint256 timestamp_) public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        vm.warp(bound(timestamp_, action.queuedAt, action.executableAt - 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                actionId,
                action.executableAt
            )
        );
        queue.executeQueuedAction(actionId);
    }

    function test_executeQueuedAction_givenActionExpired_reverts(uint256 timestamp_) public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        vm.warp(bound(timestamp_, uint256(action.expiresAt) + 1, type(uint48).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        queue.executeQueuedAction(actionId);
    }

    function test_executeQueuedAction_succeedsAtTimestampBoundaries() public {
        uint64 first = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory firstAction = queue.getQueuedAction(first);
        vm.warp(firstAction.executableAt);
        queue.executeQueuedAction(first);

        uint64 second = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory secondAction = queue.getQueuedAction(second);
        vm.warp(secondAction.expiresAt);
        queue.executeQueuedAction(second);
    }

    function test_executeQueuedAction_givenExecutedAction_reverts() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId);
        queue.executeQueuedAction(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.executeQueuedAction(actionId);
    }

    function test_executeQueuedAction_givenCancelledAction_reverts() public {
        uint64 actionId = _queueSingleAction();
        queue.cancelQueuedAction(actionId);
        _warpToExecutableAt(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        queue.executeQueuedAction(actionId);
    }

    function test_executeQueuedAction_givenExecutionRejected_rollsBack() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId);
        queue.setRejectExecution(true);
        vm.expectRevert(MockTimelockBatchQueue.MockTimelockBatchQueue_ExecutionRejected.selector);
        queue.executeQueuedAction(actionId);

        assertFalse(queue.getQueuedAction(actionId).executed);
        assertEq(queue.getQueuedActionLength(actionId), 1);
    }

    function test_executeQueuedAction_givenWrongCaller_reverts() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId);
        queue.setExecutionCaller(executor);
        vm.prank(address(0xBAD));
        vm.expectRevert(MockTimelockBatchQueue.MockTimelockBatchQueue_ExecutionRejected.selector);
        queue.executeQueuedAction(actionId);
    }

    function test_executeQueuedAction_executesBatchInOrderAndClearsActions() public {
        (uint64 actionId, ITimelockBatchQueue.BatchAction[] memory actions) = _queueThreeBatch();
        _warpReady(actionId);

        for (uint256 i; i < actions.length; ++i) {
            vm.expectEmit(true, true, true, true);
            emit ITimelockBatchQueue.TimelockSubActionExecuted(
                actionId,
                actions[i].target,
                actions[i].selector,
                i
            );
        }
        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionExecuted(actionId, executor);
        vm.prank(executor);
        queue.executeQueuedAction(actionId);

        uint256[] memory values = queue.getExecutedValues();
        assertEq(values.length, 3);
        assertEq(values[0], 0);
        assertEq(values[1], 1);
        assertEq(values[2], 2);
        assertTrue(queue.getQueuedAction(actionId).executed);
        assertEq(queue.getQueuedAction(actionId).actions.length, 0);

        MockTimelockBatchQueue.ExecuteSubActionCall[] memory calls = queue
            .getExecuteSubActionCalls();
        assertEq(calls.length, 3);
        for (uint256 i; i < calls.length; ++i) {
            assertEq(calls[i].actionId, actionId);
            assertEq(calls[i].index, i);
            assertEq(calls[i].target, actions[i].target);
            assertEq(calls[i].selector, actions[i].selector);
            assertEq(calls[i].payloadHash, keccak256(actions[i].payload));
        }
    }

    function test_executeQueuedAction_givenLaterSubActionReverts_rollsBackWholeBatch() public {
        (uint64 actionId, ) = _queueThreeBatch();
        _warpReady(actionId);
        queue.setRevertExecutionValue(2);

        vm.expectRevert(
            abi.encodeWithSelector(
                MockTimelockBatchQueue.MockTimelockBatchQueue_ExecutionReverted.selector,
                uint256(2)
            )
        );
        queue.executeQueuedAction(actionId);

        assertFalse(queue.getQueuedAction(actionId).executed);
        assertEq(queue.getQueuedActionLength(actionId), 3);
        assertEq(queue.getExecutedValues().length, 0);
        assertEq(queue.getExecuteSubActionCalls().length, 0);
    }

    function test_executeQueuedAction_callsCompletionHookAfterEverySubAction() public {
        (uint64 actionId, ) = _queueThreeBatch();
        _warpReady(actionId);
        queue.executeQueuedAction(actionId);

        MockTimelockBatchQueue.CompletionCall[] memory calls = queue.getCompletionCalls();
        assertEq(calls.length, 1);
        assertEq(calls[0].actionId, actionId);
        assertEq(calls[0].subActionCount, 3);
        assertEq(calls[0].executionCount, 3);
    }

    function test_executeQueuedAction_givenCompletionHookReverts_rollsBackWholeBatch() public {
        (uint64 actionId, ) = _queueThreeBatch();
        _warpReady(actionId);
        queue.setRejectCompletion(true);

        vm.expectRevert(MockTimelockBatchQueue.MockTimelockBatchQueue_CompletionReverted.selector);
        queue.executeQueuedAction(actionId);

        assertFalse(queue.getQueuedAction(actionId).executed);
        assertEq(queue.getQueuedActionLength(actionId), 3);
        assertEq(queue.getExecutedValues().length, 0);
        assertEq(queue.getCompletionCalls().length, 0);
    }

    function test_executeQueuedAction_givenReentrantExecution_revertsWholeBatch() public {
        vm.prank(proposer);
        uint64 actionId = queue.queueAction(address(reentrant), selector1, hex"01");
        _warpReady(actionId);
        reentrant.arm(abi.encodeCall(TimelockBatchQueue.executeQueuedAction, (actionId)));
        queue.setCallThroughTarget(address(reentrant));

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.executeQueuedAction(actionId);
    }

    function test_executeQueuedAction_givenReentrantCancellation_revertsWholeBatch() public {
        vm.prank(proposer);
        uint64 actionId = queue.queueAction(address(reentrant), selector1, hex"01");
        _warpReady(actionId);
        reentrant.arm(abi.encodeCall(TimelockBatchQueue.cancelQueuedAction, (actionId)));
        queue.setCallThroughTarget(address(reentrant));

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.executeQueuedAction(actionId);
    }

    function test_executeQueuedAction_allowsReentrantQueueOfNewAction() public {
        vm.prank(proposer);
        uint64 actionId = queue.queueAction(address(reentrant), selector1, hex"01");
        _warpReady(actionId);
        uint64 newActionId = queue.nextActionId();
        reentrant.arm(
            abi.encodeCall(
                MockTimelockBatchQueue.queueAction,
                (target1, selector1, abi.encode(uint256(99)))
            )
        );
        queue.setCallThroughTarget(address(reentrant));

        queue.executeQueuedAction(actionId);

        assertTrue(queue.getQueuedAction(actionId).executed);
        assertEq(queue.getQueuedActionLength(newActionId), 1);
        assertEq(queue.nextActionId(), newActionId + 1);
    }

    function _warpToExecutableAt(uint64 actionId_) internal {
        vm.warp(queue.getQueuedAction(actionId_).executableAt);
    }
}
