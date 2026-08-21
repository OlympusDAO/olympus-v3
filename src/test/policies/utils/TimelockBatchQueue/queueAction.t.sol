// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";
import {MockTimelockBatchQueue} from "src/test/policies/utils/TimelockBatchQueue/fixtures/MockTimelockBatchQueue.sol";

contract TimelockBatchQueueQueueActionTest is TimelockBatchQueueTest {
    function test_queueAction_givenSubActionRejected_revertsWithoutIncrementingId() public {
        queue.setRejectSubAction(true);
        vm.expectRevert(MockTimelockBatchQueue.MockTimelockBatchQueue_SubActionRejected.selector);
        queue.queueAction(target1, selector1, abi.encode(uint256(11)));
        assertEq(queue.nextActionId(), 1, "rejected action does not consume ID");
    }

    function test_queueAction_givenWrongCaller_reverts() public {
        queue.setQueueCaller(proposer);
        vm.prank(executor);
        vm.expectRevert(MockTimelockBatchQueue.MockTimelockBatchQueue_SubActionRejected.selector);
        queue.queueAction(target1, selector1, abi.encode(uint256(11)));
    }

    function test_queueAction_givenAllowedCaller_succeeds() public {
        queue.setQueueCaller(proposer);
        vm.prank(proposer);
        assertEq(
            queue.queueAction(target1, selector1, abi.encode(uint256(11))),
            1,
            "queued action ID"
        );
    }

    function test_queueAction_storesActionAndEmitsEvents() public {
        uint64 actionId = queue.nextActionId();
        uint48 queuedAt = uint48(block.timestamp);
        uint48 executableAt = queuedAt + TIMELOCK_DELAY;
        uint48 expiresAt = executableAt + EXECUTION_WINDOW;
        bytes memory payload = abi.encode(uint256(11));
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: target1,
            selector: selector1,
            payload: payload
        });

        vm.expectEmit(true, true, true, true);
        emit ITimelockBatchQueue.TimelockSubActionQueued(
            actionId,
            target1,
            selector1,
            0,
            keccak256(payload)
        );
        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionQueued(
            actionId,
            proposer,
            keccak256(abi.encode(actions)),
            executableAt,
            expiresAt
        );

        vm.prank(proposer);
        assertEq(queue.queueAction(target1, selector1, payload), actionId, "queued action ID");

        ITimelockBatchQueue.QueuedAction memory queued = queue.getQueuedAction(actionId);
        assertEq(queued.proposer, proposer, "queued proposer");
        assertEq(queued.queuedAt, queuedAt, "queued timestamp");
        assertEq(queued.executableAt, executableAt, "executable timestamp");
        assertEq(queued.expiresAt, expiresAt, "expiry timestamp");
        assertEq(queued.actions.length, 1, "queued sub-action count");
        assertEq(queued.actions[0].target, target1, "queued target");
        assertEq(queued.actions[0].selector, selector1, "queued selector");
        assertEq(queued.actions[0].payload, payload, "queued payload");
        assertEq(queue.nextActionId(), actionId + 1, "next action ID");
    }
}
