// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";
import {ConfigTimelockBatchQueueHarness} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/ConfigTimelockBatchQueueHarness.sol";

contract ConfigTimelockBatchQueueQueueBatchTest is ConfigTimelockBatchQueueTest {
    function test_givenDuplicateKeyAcrossSubActions_revertsWithoutLeakingGuards() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _batch(_KEY_A, _KEY_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(_KEY_A),
                uint64(1)
            )
        );
        _queue.queueBatch(actions);

        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "duplicate key not leaked");
        assertEq(_queue.getQueuedConfigStateCount(1, 0), 0, "duplicate guards rolled back");
        assertEq(_queue.nextActionId(), 1, "action id not consumed");
    }

    function test_givenPartiallyOverlappingKeySets_revertsWithoutLeakingGuards() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _queue.makeAction(_keys(_KEY_A, _KEY_B), _values(11, 22), 1);
        actions[1] = _queue.makeAction(_keys(_KEY_B, _KEY_C), _values(23, 33), 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(_KEY_B),
                uint64(1)
            )
        );
        _queue.queueBatch(actions);

        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "first key released");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), 0, "overlapping key released");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_C)), 0, "later key not acquired");
        assertEq(_queue.getQueuedConfigStateCount(1, 0), 0, "first guards rolled back");
        assertEq(_queue.getQueuedConfigStateCount(1, 1), 0, "second guards rolled back");
        assertEq(
            _queue.getQueuedConfigDestination(1, 0),
            address(0),
            "first destination rolled back"
        );
        assertEq(
            _queue.getQueuedConfigDestination(1, 1),
            address(0),
            "second destination rolled back"
        );
        assertEq(_queue.nextActionId(), 1, "action id not consumed");
    }

    function test_givenLaterSubActionValidationRejection_rollsBackEarlierGuards() public {
        _queue.setRejectedSubActionIndex(1, true);
        ITimelockBatchQueue.BatchAction[] memory actions = _batch(_KEY_A, _KEY_B);

        vm.expectRevert(
            ConfigTimelockBatchQueueHarness.ConfigTimelockBatchQueueHarness_ActionInvalid.selector
        );
        _queue.queueBatch(actions);

        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "earlier key released");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), 0, "rejected key not acquired");
        assertEq(_queue.getQueuedConfigStateCount(1, 0), 0, "earlier guard rolled back");
        assertEq(
            _queue.getQueuedConfigDestination(1, 0),
            address(0),
            "earlier destination rolled back"
        );
        assertEq(_queue.nextActionId(), 1, "action id not consumed");
    }

    function test_givenAggregateKeyLimitExceeded_revertsWithoutLeakingGuards() public {
        _queue.setMaxConfigKeys(2);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _queue.makeAction(_keys(_KEY_A, _KEY_B), _values(11, 22), 1);
        actions[1] = _queue.makeAction(_keys(_KEY_C), _values(33), 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeysTooMany.selector,
                uint256(3),
                uint256(2)
            )
        );
        _queue.queueBatch(actions);

        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "first key not leaked");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), 0, "second key not leaked");
        assertEq(_queue.nextActionId(), 1, "action id not consumed");
    }

    function test_givenBatchValidationRejects_revertsWithoutLeakingGuards() public {
        _queue.setRejectBatch(true);
        ITimelockBatchQueue.BatchAction[] memory actions = _batch(_KEY_A, _KEY_B);
        vm.expectRevert(
            ConfigTimelockBatchQueueHarness.ConfigTimelockBatchQueueHarness_BatchRejected.selector
        );
        _queue.queueBatch(actions);

        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "first key not leaked");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), 0, "second key not leaked");
        assertEq(_queue.nextActionId(), 1, "action id not consumed");
    }

    function test_givenMultipleKeysPerSubAction_countsAllKeysAgainstBatchLimit() public {
        _queue.setMaxConfigKeys(3);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _queue.makeAction(_keys(_KEY_A, _KEY_B), _values(11, 22), 1);
        actions[1] = _queue.makeAction(_keys(_KEY_C), _values(33), 2);
        uint64 actionId = _queue.queueBatch(actions);

        assertEq(_queue.getQueuedConfigStateCount(actionId, 0), 2, "first sub-action keys");
        assertEq(_queue.getQueuedConfigStateCount(actionId, 1), 1, "second sub-action keys");
    }
}
