// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";

contract ConfigTimelockBatchQueueCancelQueuedActionTest is ConfigTimelockBatchQueueTest {
    function test_cancelQueuedAction_releasesEveryKeyAndClearsEveryGuard() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _queue.makeAction(_keys(_KEY_A, _KEY_B), _values(11, 22), 1);
        actions[1] = _queue.makeAction(_keys(_KEY_C), _values(33), 2);
        uint64 actionId = _queue.queueBatch(actions);

        _queue.cancelQueuedAction(actionId);

        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "first key released");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), 0, "second key released");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_C)), 0, "third key released");
        assertEq(_queue.getQueuedConfigStateCount(actionId, 0), 0, "first guards cleared");
        assertEq(_queue.getQueuedConfigStateCount(actionId, 1), 0, "second guards cleared");
    }

    function test_givenReleasedKey_cancelledAction_allowsKeyToBeQueuedAgain() public {
        uint64 cancelledActionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        _queue.cancelQueuedAction(cancelledActionId);

        uint64 replacementActionId = _queue.queueConfig(_keys(_KEY_A), _values(12), 2);

        assertEq(
            _queue.pendingActionId(_scopedKey(_KEY_A)),
            replacementActionId,
            "replacement owns released key"
        );
        assertEq(replacementActionId, cancelledActionId + 1, "replacement action id");
    }

    function test_cancelQueuedAction_afterExpiry_releasesRetainedKeys() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A, _KEY_B), _values(11, 22), 1);
        ITimelockBatchQueue.QueuedAction memory action = _queue.getQueuedAction(actionId);
        vm.warp(uint256(action.expiresAt) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        _queue.executeQueuedAction(actionId);
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), actionId, "first expired key held");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), actionId, "second expired key held");

        _queue.cancelQueuedAction(actionId);
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "first cancelled key released");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), 0, "second cancelled key released");
    }

    function test_cancelQueuedAction_givenOwnershipMismatch_revertsWithoutDeletingForeignLock()
        public
    {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        uint64 corruptOwner = 99;
        bytes32 scopedKey = _scopedKey(_KEY_A);
        assertEq(_queue.pendingActionId(scopedKey), actionId, "expected owner before corruption");
        vm.store(address(_queue), _pendingActionIdSlot(scopedKey), bytes32(uint256(corruptOwner)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigKeyOwnershipInvalid
                    .selector,
                actionId,
                uint256(0),
                scopedKey,
                corruptOwner
            )
        );
        _queue.cancelQueuedAction(actionId);

        assertEq(_queue.pendingActionId(scopedKey), corruptOwner, "foreign owner retained");
        assertFalse(_queue.getQueuedAction(actionId).cancelled, "action remains pending");
        assertEq(_queue.getQueuedConfigStateCount(actionId, 0), 1, "guard retained");
    }

    function test_givenLaterOwnershipMismatch_cancelQueuedAction_rollsBackEarlierRelease() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A, _KEY_B), _values(11, 22), 1);
        uint64 corruptOwner = 99;
        bytes32 scopedKeyB = _scopedKey(_KEY_B);
        assertEq(_queue.pendingActionId(scopedKeyB), actionId, "expected owner before corruption");
        vm.store(address(_queue), _pendingActionIdSlot(scopedKeyB), bytes32(uint256(corruptOwner)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigKeyOwnershipInvalid
                    .selector,
                actionId,
                uint256(0),
                scopedKeyB,
                corruptOwner
            )
        );
        _queue.cancelQueuedAction(actionId);

        assertEq(
            _queue.pendingActionId(_scopedKey(_KEY_A)),
            actionId,
            "earlier key release rolled back"
        );
        assertEq(_queue.pendingActionId(scopedKeyB), corruptOwner, "foreign owner retained");
        assertFalse(_queue.getQueuedAction(actionId).cancelled, "action remains pending");
        assertEq(_queue.getQueuedConfigStateCount(actionId, 0), 2, "guards retained");
        assertEq(
            _queue.getQueuedConfigDestination(actionId, 0),
            address(_target),
            "destination retained"
        );
    }
}
