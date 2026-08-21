// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";
import {MockTimelockBatchQueue} from "src/test/policies/utils/TimelockBatchQueue/fixtures/MockTimelockBatchQueue.sol";

contract TimelockBatchQueueQueueBatchActionTest is TimelockBatchQueueTest {
    function test_queueBatchAction_givenEmptyBatch_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](0);
        vm.expectRevert(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector);
        queue.queueBatchAction(actions);
        assertEq(queue.nextActionId(), 1, "action ID not consumed");
    }

    function test_queueBatchAction_givenBatchAboveDefaultMaximum_reverts() public {
        uint256 maximum = queue.getMaxBatchSize();
        _expectBatchTooLarge(_buildBatchOfSize(maximum + 1), maximum);
    }

    function test_queueBatchAction_givenBatchAboveOverrideMaximum_reverts() public {
        queue.setMaxBatchSizeOverride(3);
        _expectBatchTooLarge(_buildBatchOfSize(4), 3);
    }

    function test_queueBatchAction_whenBatchIsAtDefaultMaximum() public {
        uint256 maximum = queue.getMaxBatchSize();
        uint64 actionId = queue.queueBatchAction(_buildBatchOfSize(maximum));
        assertEq(queue.getQueuedActionLength(actionId), maximum, "stored action count");
    }

    function test_queueBatchAction_whenBatchIsAtOverrideMaximum() public {
        uint256 maximum = 3;
        queue.setMaxBatchSizeOverride(maximum);
        vm.prank(proposer);
        uint64 actionId = queue.queueBatchAction(_buildBatchOfSize(maximum));
        assertEq(actionId, 1, "action ID");
        assertEq(queue.getQueuedActionLength(actionId), maximum, "stored action count");
    }

    function test_queueBatchAction_givenSubActionRejected_revertsAllQueueState() public {
        queue.setRejectSubActionAtIndex(1);
        uint64 actionId = queue.nextActionId();
        vm.expectRevert(
            abi.encodeWithSelector(
                MockTimelockBatchQueue.MockTimelockBatchQueue_SubActionRejectedAt.selector,
                uint256(1)
            )
        );
        queue.queueBatchAction(_buildBatchOfThree());
        assertEq(queue.nextActionId(), actionId, "action ID not consumed");
        _expectActionNotFound(actionId);
    }

    function test_queueBatchAction_givenBatchRejected_revertsAllQueueState() public {
        queue.setRejectBatch(true);
        uint64 actionId = queue.nextActionId();
        vm.expectRevert(MockTimelockBatchQueue.MockTimelockBatchQueue_BatchRejected.selector);
        queue.queueBatchAction(_buildBatchOfThree());
        assertEq(queue.nextActionId(), actionId, "action ID not consumed");
        _expectActionNotFound(actionId);
    }

    function test_queueBatchAction_storesActionsInOrderAndEmitsEvents() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _buildBatchOfThree();
        uint64 actionId = queue.nextActionId();
        uint48 queuedAt = uint48(block.timestamp);
        uint48 executableAt = queuedAt + TIMELOCK_DELAY;
        uint48 expiresAt = executableAt + EXECUTION_WINDOW;

        for (uint256 i; i < actions.length; ++i) {
            vm.expectEmit(true, true, true, true);
            emit ITimelockBatchQueue.TimelockSubActionQueued(
                actionId,
                actions[i].target,
                actions[i].selector,
                i,
                keccak256(actions[i].payload)
            );
        }
        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionQueued(
            actionId,
            proposer,
            keccak256(abi.encode(actions)),
            executableAt,
            expiresAt
        );

        vm.prank(proposer);
        assertEq(queue.queueBatchAction(actions), actionId, "queued action ID");

        ITimelockBatchQueue.QueuedAction memory queued = queue.getQueuedAction(actionId);
        assertEq(queued.actions.length, actions.length, "stored action count");
        for (uint256 i; i < actions.length; ++i) {
            assertEq(queued.actions[i].target, actions[i].target, "stored target");
            assertEq(queued.actions[i].selector, actions[i].selector, "stored selector");
            assertEq(queued.actions[i].payload, actions[i].payload, "stored payload");
        }
    }

    function test_queueBatchAction_incrementsActionIdOncePerBatch() public {
        uint64 first = queue.queueBatchAction(_buildBatchOfThree());
        uint64 second = queue.queueBatchAction(_buildBatchOfThree());
        assertEq(second, first + 1, "second action ID");
        assertEq(queue.nextActionId(), second + 1, "next action ID");
    }

    function _expectBatchTooLarge(
        ITimelockBatchQueue.BatchAction[] memory actions_,
        uint256 maximum_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_BatchTooLarge.selector,
                actions_.length,
                maximum_
            )
        );
        queue.queueBatchAction(actions_);
        assertEq(queue.nextActionId(), 1, "action ID not consumed");
    }

    function _expectActionNotFound(uint64 actionId_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                actionId_
            )
        );
        queue.getQueuedAction(actionId_);
    }
}
