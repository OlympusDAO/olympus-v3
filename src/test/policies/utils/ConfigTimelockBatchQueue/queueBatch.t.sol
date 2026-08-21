// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";
import {ConfigTimelockBatchQueueHarness} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/ConfigTimelockBatchQueueHarness.sol";

contract ConfigTimelockBatchQueueQueueBatchTest is ConfigTimelockBatchQueueTest {
    function test_queueBatch_givenDuplicateKeyAcrossSubActions_revertsWithoutLeakingGuards()
        public
    {
        ITimelockBatchQueue.BatchAction[] memory actions = _batch(KEY_A, KEY_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(KEY_A),
                uint64(1)
            )
        );
        queue.queueBatch(actions);

        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "duplicate key not leaked");
        assertEq(queue.getQueuedConfigStateCount(1, 0), 0, "duplicate guards rolled back");
        assertEq(queue.nextActionId(), 1, "action id not consumed");
    }

    function test_givenPartiallyOverlappingKeySets_queueBatch_revertsWithoutLeakingGuards() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = queue.makeAction(_keys(KEY_A, KEY_B), _values(11, 22), 1);
        actions[1] = queue.makeAction(_keys(KEY_B, KEY_C), _values(23, 33), 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(KEY_B),
                uint64(1)
            )
        );
        queue.queueBatch(actions);

        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "first key released");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), 0, "overlapping key released");
        assertEq(queue.pendingActionId(_scopedKey(KEY_C)), 0, "later key not acquired");
        assertEq(queue.getQueuedConfigStateCount(1, 0), 0, "first guards rolled back");
        assertEq(queue.getQueuedConfigStateCount(1, 1), 0, "second guards rolled back");
        assertEq(
            queue.getQueuedConfigDestination(1, 0),
            address(0),
            "first destination rolled back"
        );
        assertEq(
            queue.getQueuedConfigDestination(1, 1),
            address(0),
            "second destination rolled back"
        );
        assertEq(queue.nextActionId(), 1, "action id not consumed");
    }

    function test_givenLaterSubActionValidationRejection_queueBatch_rollsBackEarlierGuards()
        public
    {
        queue.setRejectedSubActionIndex(1, true);
        ITimelockBatchQueue.BatchAction[] memory actions = _batch(KEY_A, KEY_B);

        vm.expectRevert(
            ConfigTimelockBatchQueueHarness.ConfigTimelockBatchQueueHarness_ActionInvalid.selector
        );
        queue.queueBatch(actions);

        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "earlier key released");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), 0, "rejected key not acquired");
        assertEq(queue.getQueuedConfigStateCount(1, 0), 0, "earlier guard rolled back");
        assertEq(
            queue.getQueuedConfigDestination(1, 0),
            address(0),
            "earlier destination rolled back"
        );
        assertEq(queue.nextActionId(), 1, "action id not consumed");
    }

    function test_queueBatch_givenAggregateKeyLimitExceeded_revertsWithoutLeakingGuards() public {
        queue.setMaxConfigKeys(2);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = queue.makeAction(_keys(KEY_A, KEY_B), _values(11, 22), 1);
        actions[1] = queue.makeAction(_keys(KEY_C), _values(33), 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeysTooMany.selector,
                uint256(3),
                uint256(2)
            )
        );
        queue.queueBatch(actions);

        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "first key not leaked");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), 0, "second key not leaked");
        assertEq(queue.nextActionId(), 1, "action id not consumed");
    }

    function test_queueBatch_givenBatchValidationRejects_revertsWithoutLeakingGuards() public {
        queue.setRejectBatch(true);
        ITimelockBatchQueue.BatchAction[] memory actions = _batch(KEY_A, KEY_B);
        vm.expectRevert(
            ConfigTimelockBatchQueueHarness.ConfigTimelockBatchQueueHarness_BatchRejected.selector
        );
        queue.queueBatch(actions);

        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "first key not leaked");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), 0, "second key not leaked");
        assertEq(queue.nextActionId(), 1, "action id not consumed");
    }

    function test_queueBatch_givenMultipleKeysPerSubAction_countsAllKeysAgainstBatchLimit() public {
        queue.setMaxConfigKeys(3);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = queue.makeAction(_keys(KEY_A, KEY_B), _values(11, 22), 1);
        actions[1] = queue.makeAction(_keys(KEY_C), _values(33), 2);
        uint64 actionId = queue.queueBatch(actions);

        assertEq(queue.getQueuedConfigStateCount(actionId, 0), 2, "first sub-action keys");
        assertEq(queue.getQueuedConfigStateCount(actionId, 1), 1, "second sub-action keys");
    }
}
