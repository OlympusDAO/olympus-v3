// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";

contract ConfigTimelockBatchQueueCancelQueuedActionTest is ConfigTimelockBatchQueueTest {
    function test_cancelQueuedAction_releasesEveryKeyAndClearsEveryGuard() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = queue.makeAction(_keys(KEY_A, KEY_B), _values(11, 22), 1);
        actions[1] = queue.makeAction(_keys(KEY_C), _values(33), 2);
        uint64 actionId = queue.queueBatch(actions);

        queue.cancelQueuedAction(actionId);

        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "first key released");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), 0, "second key released");
        assertEq(queue.pendingActionId(_scopedKey(KEY_C)), 0, "third key released");
        assertEq(queue.getQueuedConfigStateCount(actionId, 0), 0, "first guards cleared");
        assertEq(queue.getQueuedConfigStateCount(actionId, 1), 0, "second guards cleared");
    }

    function test_givenReleasedKey_cancelledAction_allowsKeyToBeQueuedAgain() public {
        uint64 cancelledActionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        queue.cancelQueuedAction(cancelledActionId);

        uint64 replacementActionId = queue.queueConfig(_keys(KEY_A), _values(12), 2);

        assertEq(
            queue.pendingActionId(_scopedKey(KEY_A)),
            replacementActionId,
            "replacement owns released key"
        );
        assertEq(replacementActionId, cancelledActionId + 1, "replacement action id");
    }

    function test_cancelQueuedAction_afterExpiry_releasesRetainedKeys() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A, KEY_B), _values(11, 22), 1);
        ITimelockBatchQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        vm.warp(uint256(action.expiresAt) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        queue.executeQueuedAction(actionId);
        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), actionId, "first expired key held");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), actionId, "second expired key held");

        queue.cancelQueuedAction(actionId);
        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "first cancelled key released");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), 0, "second cancelled key released");
    }

    function test_cancelQueuedAction_givenOwnershipMismatch_revertsWithoutDeletingForeignLock()
        public
    {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        uint64 corruptOwner = 99;
        bytes32 scopedKey = _scopedKey(KEY_A);
        vm.store(
            address(queue),
            keccak256(abi.encode(scopedKey, uint256(2))),
            bytes32(uint256(corruptOwner))
        );

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
        queue.cancelQueuedAction(actionId);

        assertEq(queue.pendingActionId(scopedKey), corruptOwner, "foreign owner retained");
        assertFalse(queue.getQueuedAction(actionId).cancelled, "action remains pending");
        assertEq(queue.getQueuedConfigStateCount(actionId, 0), 1, "guard retained");
    }

    function test_givenLaterOwnershipMismatch_cancelQueuedAction_rollsBackEarlierRelease() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A, KEY_B), _values(11, 22), 1);
        uint64 corruptOwner = 99;
        bytes32 scopedKeyB = _scopedKey(KEY_B);
        vm.store(
            address(queue),
            keccak256(abi.encode(scopedKeyB, uint256(2))),
            bytes32(uint256(corruptOwner))
        );

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
        queue.cancelQueuedAction(actionId);

        assertEq(
            queue.pendingActionId(_scopedKey(KEY_A)),
            actionId,
            "earlier key release rolled back"
        );
        assertEq(queue.pendingActionId(scopedKeyB), corruptOwner, "foreign owner retained");
        assertFalse(queue.getQueuedAction(actionId).cancelled, "action remains pending");
        assertEq(queue.getQueuedConfigStateCount(actionId, 0), 2, "guards retained");
        assertEq(
            queue.getQueuedConfigDestination(actionId, 0),
            address(target),
            "destination retained"
        );
    }
}
